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

    /// Convenience: `true` when at least one build is running.
    var isBuildActive: Bool { !activeBuilds.isEmpty }

    /// The polling interval in seconds.
    let pollInterval: TimeInterval

    /// Combine subscription for the timer.
    private var timerCancellable: AnyCancellable?

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
    }

    /// Perform a single scan right now.
    func scan() {
        activeBuilds = BuildDetector.detectBuilds()
    }
}
