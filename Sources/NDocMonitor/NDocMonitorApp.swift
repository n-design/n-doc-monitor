import SwiftUI

/// The main entry point for n-doc-monitor.
///
/// This app lives entirely in the macOS menu bar — there is no main window
/// and no Dock icon.  Clicking the menu bar icon opens a panel showing
/// the current build status.
///
/// **SwiftUI concepts used here:**
/// - `@main` marks this struct as the application entry point.
/// - `MenuBarExtra` is a *Scene* that places an icon in the menu bar
///   instead of opening a window.  The first argument is the title
///   (used for accessibility), `systemImage` sets the SF Symbol icon,
///   and the trailing closure provides the view shown when the user
///   clicks the icon.
@main
struct NDocMonitorApp: App {
    var body: some Scene {
        // MenuBarExtra creates a menu-bar-only app.
        // .window style gives us a detachable panel (as opposed to a
        // pull-down menu).
        MenuBarExtra("n-doc monitor", systemImage: "doc.text.magnifyingglass") {
            MonitorView()
        }
        .menuBarExtraStyle(.window)
    }
}
