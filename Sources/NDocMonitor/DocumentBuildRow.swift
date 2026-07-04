import SwiftUI

/// A single row in the monitor panel showing one document's build status.
///
/// **SwiftUI concepts introduced here:**
/// - `HStack` — arranges child views horizontally.
/// - Ternary expressions in view modifiers — choosing colours or
///   symbols based on state.
/// - Extracting a reusable sub-view: rather than putting all the
///   layout logic in `MonitorView`, we break it into a small,
///   focused component.  This is a core SwiftUI best practice.
struct DocumentBuildRow: View {
    let document: DocumentBuild

    var body: some View {
        HStack(spacing: 10) {
            // Activity indicator: spinning if lualatex is running
            Image(systemName: document.isRunning
                  ? "arrow.trianglehead.2.counterclockwise"
                  : "checkmark.circle.fill")
                .foregroundStyle(document.isRunning ? .orange : .green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(document.isRunning ? "Run \(document.runCount)" : "Idle")
                        .font(.subheadline)
                        .foregroundStyle(document.isRunning ? .primary : .secondary)

                    if document.runCount > 0 && !document.isRunning {
                        Text("(\(document.runCount) run\(document.runCount == 1 ? "" : "s") completed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
