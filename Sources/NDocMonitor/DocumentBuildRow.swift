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
        HStack(spacing: 8) {
            // Activity indicator
            Image(systemName: document.isRunning
                  ? "circle.fill"
                  : "checkmark.circle.fill")
                .foregroundStyle(document.isRunning ? .orange : .green)
                .font(.caption)
                .frame(width: 14)

            Text(document.name)
                .font(.subheadline)

            Spacer()

            // Run count — monospaced so the column doesn't jump
            if document.isRunning {
                Text("Run \(document.runCount)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            } else if document.runCount > 0 {
                Text("\(document.runCount) run\(document.runCount == 1 ? "" : "s")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
