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

    var body: some View {
        VStack(spacing: 12) {
            if monitor.isBuildActive {
                // Active build(s) detected
                Image(systemName: "hammer.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                if monitor.documentBuilds.isEmpty {
                    // Build detected but no latexmk processes yet
                    // (make is still in early setup phase)
                    Text("Build starting…")
                        .font(.headline)
                    ForEach(monitor.activeBuilds, id: \.makePID) { build in
                        Text(build.repoPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                } else {
                    // Show each document being typeset
                    ForEach(monitor.documentBuilds) { doc in
                        DocumentBuildRow(document: doc)
                    }
                }
            } else if let completed = monitor.lastCompletedBuild {
                // Build just finished — show summary briefly
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)

                Text("Build finished")
                    .font(.headline)

                ForEach(completed.documents, id: \.name) { doc in
                    HStack(spacing: 4) {
                        Text(doc.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(doc.totalRuns) run\(doc.totalRuns == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Idle state
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("No build active")
                    .font(.headline)

                Text("n-doc monitor is watching for builds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
        .onAppear {
            monitor.startMonitoring()
        }
    }
}
