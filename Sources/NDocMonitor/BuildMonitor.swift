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
        activeBuilds = []
        documentBuilds = []
        trackedDocuments = [:]
    }

    /// Perform a single scan right now.
    func scan() {
        activeBuilds = BuildDetector.detectBuilds()

        // For each detected build, walk the tree to find documents.
        var newSnapshots: [DocumentBuild] = []
        for build in activeBuilds {
            let snapshots = BuildDetector.scanDocumentBuilds(for: build)
            newSnapshots.append(contentsOf: snapshots)
        }

        // Merge snapshots with our tracked state to preserve run counts.
        documentBuilds = mergeSnapshots(newSnapshots)

        // Clean up tracked documents that are no longer present.
        let activePIDs = Set(documentBuilds.map(\.id))
        trackedDocuments = trackedDocuments.filter { activePIDs.contains($0.key) }
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
