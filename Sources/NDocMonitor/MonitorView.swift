import SwiftUI

/// The panel that appears when the user clicks the menu bar icon.
///
/// For now this shows a static placeholder.  In later steps we will
/// replace the placeholder with live build data.
///
/// **SwiftUI concepts used here:**
/// - `VStack` arranges child views vertically.
/// - `Image(systemName:)` renders an SF Symbol — Apple's built-in
///   icon library (see https://developer.apple.com/sf-symbols/).
/// - `.font()`, `.foregroundStyle()`, `.padding()` are *view modifiers*
///   that adjust appearance and layout.
/// - `some View` is an *opaque return type* — the compiler knows the
///   concrete type, but callers only see "some View".
struct MonitorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No build active")
                .font(.headline)

            Text("n-doc monitor is watching for builds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 260)
    }
}
