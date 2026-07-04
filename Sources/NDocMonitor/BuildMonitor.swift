import SwiftUI
import Combine

/// Periodically polls for n-doc builds and publishes the results.
///
/// This is the bridge between the low-level `BuildDetector` (which
/// answers "what's happening *right now*?") and the SwiftUI views
/// (which need to *react* when the answer changes).
///
/// ## SwiftUI concepts introduced
///
/// ### `ObservableObject`
/// A class that SwiftUI can *watch*.  When any of its `@Published`
/// properties change, every view that holds a reference to it
/// (via `@StateObject` or `@ObservedObject`) re-renders automatically.
///
/// ### `@Published`
/// A property wrapper that emits change notifications through
/// Combine's publisher infrastructure.  SwiftUI subscribes to these
/// under the hood.
///
/// ### `Timer.publish`
/// Creates a Combine publisher that emits a value at a fixed interval.
/// We use it to trigger a process scan every 2 seconds.  The timer
/// is started with `.autoconnect()` so it begins immediately.
///
/// ### `@MainActor`
/// Ensures all property access and UI updates happen on the main
/// thread — required by SwiftUI.
@MainActor
final class BuildMonitor: ObservableObject {

    /// The currently detected n-doc builds.  Empty when idle.
    @Published private(set) var activeBuilds: [BuildDetector.DetectedBuild] = []

    /// The documents currently being typeset, keyed by `latexmk` PID.
    ///
    /// **New in Step 4:**
    /// This is where the UI gets its per-document information.
    /// Each `DocumentBuild` tracks the document name, run count,
    /// and whether lualatex is currently running.
    @Published private(set) var documentBuilds: [DocumentBuild] = []

    /// Summary of the last completed build, shown briefly before
    /// returning to the idle state.
    ///
    /// **Step 7 — robustness:**
    /// When a build finishes (root make exits), we keep a snapshot
    /// of the final document states so the UI can show "Build
    /// finished — 10 documents, 3 runs each" for a few seconds
    /// before clearing to idle.
    @Published private(set) var lastCompletedBuild: CompletedBuild?

    /// Convenience: `true` when at least one build is running.
    var isBuildActive: Bool { !activeBuilds.isEmpty }

    /// The polling interval in seconds.
    let pollInterval: TimeInterval

    /// Combine subscription for the timer.
    private var timerCancellable: AnyCancellable?

    /// Tracks the last-seen lualatex PID per latexmk PID, so we can
    /// detect when a *new* lualatex run starts (different PID = new run).
    /// Also tracks accumulated run counts that survive across snapshots.
    private var trackedDocuments: [pid_t: DocumentBuild] = [:]

    /// Cancellable for the "build finished" dismiss timer.
    private var dismissCancellable: AnyCancellable?

    /// How long the "build finished" summary stays visible.
    private let dismissDelay: TimeInterval = 8.0

    init(pollInterval: TimeInterval = 2.0) {
        self.pollInterval = pollInterval
    }

    /// Start polling.  Safe to call multiple times — restarts the timer.
    func startMonitoring() {
        timerCancellable?.cancel()
        // Fire immediately on start, then every `pollInterval` seconds.
        scan()
        timerCancellable = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.scan()
            }
    }

    /// Stop polling and clear state.
    func stopMonitoring() {
        timerCancellable?.cancel()
        timerCancellable = nil
        dismissCancellable?.cancel()
        dismissCancellable = nil
        activeBuilds = []
        documentBuilds = []
        trackedDocuments = [:]
        lastCompletedBuild = nil
    }

    /// Perform a single scan right now.
    ///
    /// **Step 7 — robustness:**
    /// Uses `BuildDetector.fullScan()` which takes a single process
    /// snapshot, ensuring make-detection and tree-walking see the
    /// same set of processes.
    ///
    /// Also detects the build→idle transition and captures a
    /// `CompletedBuild` summary that the UI can show briefly.
    func scan() {
        let previouslyActive = isBuildActive
        let previousDocuments = documentBuilds

        let result = BuildDetector.fullScan()
        activeBuilds = result.builds

        // Merge snapshots with our tracked state to preserve run counts.
        documentBuilds = mergeSnapshots(result.documents)

        // Clean up tracked documents that are no longer present.
        let activePIDs = Set(documentBuilds.map(\.id))
        trackedDocuments = trackedDocuments.filter { activePIDs.contains($0.key) }

        // Detect build→idle transition.
        if previouslyActive && !isBuildActive && !previousDocuments.isEmpty {
            lastCompletedBuild = CompletedBuild(
                repoPath: "", // Could be multiple repos; UI can check
                documents: previousDocuments.map { doc in
                    CompletedBuild.DocumentSummary(
                        name: doc.name,
                        totalRuns: doc.runCount
                    )
                },
                finishedAt: Date()
            )

            // Auto-dismiss after a delay.
            dismissCancellable?.cancel()
            dismissCancellable = Just(())
                .delay(for: .seconds(dismissDelay), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.lastCompletedBuild = nil
                }
        }
    }

    /// Feed a list of document snapshots directly (for testing).
    ///
    /// This bypasses the live process scan and lets tests simulate
    /// successive polling cycles with controlled data.
    func applyDocumentSnapshots(_ snapshots: [DocumentBuild]) {
        documentBuilds = mergeSnapshots(snapshots)
        let activePIDs = Set(documentBuilds.map(\.id))
        trackedDocuments = trackedDocuments.filter { activePIDs.contains($0.key) }
    }

    /// Simulate a complete scan cycle with synthetic data (for testing).
    ///
    /// This drives the same transition logic as `scan()` but with
    /// controlled inputs instead of live processes.
    func simulateScanResult(
        builds: [BuildDetector.DetectedBuild],
        documents: [DocumentBuild]
    ) {
        let previouslyActive = isBuildActive
        let previousDocuments = documentBuilds

        activeBuilds = builds
        documentBuilds = mergeSnapshots(documents)

        let activePIDs = Set(documentBuilds.map(\.id))
        trackedDocuments = trackedDocuments.filter { activePIDs.contains($0.key) }

        // Detect build→idle transition.
        if previouslyActive && !isBuildActive && !previousDocuments.isEmpty {
            lastCompletedBuild = CompletedBuild(
                repoPath: builds.first?.repoPath ?? "",
                documents: previousDocuments.map { doc in
                    CompletedBuild.DocumentSummary(
                        name: doc.name,
                        totalRuns: doc.runCount
                    )
                },
                finishedAt: Date()
            )
        }
    }

    /// Merge fresh snapshots with previously tracked state.
    ///
    /// **Key insight — state diffing:**
    /// The snapshot from `BuildDetector` always has `runCount = 0`
    /// because it only knows what's happening *right now*.  We
    /// maintain the cumulative run count here by comparing the
    /// current `lualatex` PID with the previously seen one:
    ///
    /// - **New PID appeared** → a new lualatex run started, increment count.
    /// - **Same PID** → same run still going.
    /// - **No PID** → between runs or finished.
    private func mergeSnapshots(_ snapshots: [DocumentBuild]) -> [DocumentBuild] {
        snapshots.map { snapshot in
            var doc = snapshot

            if let prev = trackedDocuments[doc.id] {
                // Carry forward the accumulated run count.
                doc.runCount = prev.runCount

                // Detect a new lualatex run by comparing PIDs.
                if let currentPID = snapshot.currentLualatexPID {
                    if prev.currentLualatexPID != currentPID {
                        // New lualatex process — increment the count.
                        doc.runCount += 1
                    }
                }
            } else {
                // First time seeing this latexmk process.
                if snapshot.currentLualatexPID != nil {
                    doc.runCount = 1
                }
            }

            trackedDocuments[doc.id] = doc
            return doc
        }
    }
}
