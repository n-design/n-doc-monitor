import SwiftUI

/// The panel that appears when the user clicks the menu bar icon.
///
/// **SwiftUI concepts used here:**
/// - `VStack` arranges child views vertically.
/// - `Image(systemName:)` renders an SF Symbol — Apple's built-in
///   icon library (see https://developer.apple.com/sf-symbols/).
/// - `.font()`, `.foregroundStyle()`, `.padding()` are *view modifiers*
///   that adjust appearance and layout.
/// - `some View` is an *opaque return type* — the compiler knows the
///   concrete type, but callers only see "some View".
///
/// **New in Step 3:**
/// - `@ObservedObject` — a reference to an `ObservableObject` that
///   this view does *not* own (the `App` struct owns it via
///   `@StateObject`).  When the monitor's `@Published` properties
///   change, this view re-renders automatically.
/// - `if`/`else` in a view builder — SwiftUI's way of showing
///   different content based on state.
/// - `.onAppear` / `.onDisappear` — lifecycle callbacks that fire
///   when a view enters or leaves the screen.
struct MonitorView: View {
    @ObservedObject var monitor: BuildMonitor

    /// The user's chosen accent color, stored in `UserDefaults`.
    ///
    /// **Step 11 — Configurable accent color:**
    /// Both `MonitorView` and `DocumentBuildRow` read this same key.
    /// When the user changes the color in Settings, every view that
    /// uses `@AppStorage("accentColor")` re-renders automatically.
    @AppStorage("accentColor") private var accentColor: Color = defaultAccentColor

    /// Callback to reset the panel position under the menu bar icon.
    /// `nil` when running inside `MenuBarExtra` (position is automatic).
    var onResetPosition: (() -> Void)? = nil

    /// Callback to show the About panel.
    var onShowAbout: (() -> Void)? = nil

    /// Callback to open the Settings window.
    var onShowSettings: (() -> Void)? = nil

    /// Callback to quit the application.
    /// `nil` hides the quit button (e.g. in tests or previews).
    var onQuit: (() -> Void)? = nil

    /// A timer that fires every second to update the elapsed-time display.
    ///
    /// **SwiftUI concept — `TimelineView`:**
    /// We *could* use `TimelineView(.periodic(from:, by:))` for this,
    /// but a simple `Timer.publish` into a `@State` is more explicit
    /// and easier to understand at this stage.
    @State private var now = Date()
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if monitor.isBuildActive {
                activeBuildView
            } else if let completed = monitor.lastCompletedBuild {
                completedBuildView(completed)
            } else {
                idleView
            }

            // Toolbar: always show (has About, Settings, Quit)
            Divider()
                .padding(.top, 8)
            toolbarView
        }
        .padding(16)
        .frame(minWidth: 300)
        .onAppear {
            monitor.startMonitoring()
        }
        .onReceive(clockTimer) { self.now = $0 }
    }

    // MARK: - Active build

    /// **SwiftUI concept — extracted computed views:**
    /// Breaking the body into `@ViewBuilder` properties keeps
    /// each section readable and avoids deeply nested closures.
    @ViewBuilder
    private var activeBuildView: some View {
        // Header
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.title2)
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Build in progress")
                    .font(.headline)

                if let started = monitor.buildStartedAt {
                    Text(elapsedString(from: started))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()

            // Document count badge
            Text("\(monitor.documentBuilds.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(accentColor))
        }
        .padding(.bottom, 10)

        if monitor.documentBuilds.isEmpty {
            // make is running but no latexmk yet
            Text("Waiting for documents…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            Divider()

            // Document list, sorted alphabetically
            let sorted = monitor.documentBuilds.sorted { $0.name < $1.name }
            ForEach(sorted) { doc in
                DocumentBuildRow(document: doc)
            }
        }
    }

    // MARK: - Completed build

    @ViewBuilder
    private func completedBuildView(_ completed: CompletedBuild) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            Text("Build finished")
                .font(.headline)

            Spacer()
        }
        .padding(.bottom, 10)

        Divider()

        let sorted = completed.documents.sorted { $0.name < $1.name }
        ForEach(sorted, id: \.name) { doc in
            HStack {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)

                Text(doc.name)
                    .font(.subheadline)

                Spacer()

                Text("\(doc.totalRuns) run\(doc.totalRuns == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("No build active")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Watching for n-doc builds…")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Toolbar

    /// **Step 9 — action buttons at the bottom of the panel.**
    ///
    /// **SwiftUI concept — `Button` with closures:**
    /// The `action` parameter is a closure that runs when the button
    /// is clicked.  We use optional closures from the parent so the
    /// toolbar adapts to different hosting contexts.
    @ViewBuilder
    private var toolbarView: some View {
        HStack(spacing: 12) {
            if let resetAction = onResetPosition {
                Button(action: resetAction) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Reset window position")
            }

            if let aboutAction = onShowAbout {
                Button(action: aboutAction) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("About n-doc monitor")
            }

            if let settingsAction = onShowSettings {
                Button(action: settingsAction) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Settings")
            }

            Spacer()

            if let quitAction = onQuit {
                Button(action: quitAction) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Quit n-doc monitor")
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Helpers

    /// Format elapsed time as "1m 23s" or "45s".
    private func elapsedString(from start: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }
}
