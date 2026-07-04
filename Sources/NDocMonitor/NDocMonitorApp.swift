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
///
/// **New in Step 3:**
/// - `@StateObject` creates and *owns* an `ObservableObject`.  The
///   object's lifetime is tied to this view hierarchy — SwiftUI keeps
///   it alive and re-renders views when its `@Published` properties
///   change.  Use `@StateObject` for the *first* (owning) reference
///   and `@ObservedObject` or `@EnvironmentObject` for downstream views.
@main
struct NDocMonitorApp: App {
    /// The shared build monitor — created once, lives for the app's lifetime.
    @StateObject private var monitor = BuildMonitor()

    /// The SF Symbol icon changes based on build state:
    /// - Idle: `doc.text.magnifyingglass` (outline)
    /// - Building: `doc.text.magnifyingglass` with a filled style
    ///   isn't available, so we switch to `hammer.fill`.
    ///
    /// **SwiftUI concept — computed properties in the body:**
    /// `MenuBarExtra` accepts a `systemImage` string, so we use a
    /// computed property to pick the right icon dynamically.
    private var menuBarIcon: String {
        monitor.isBuildActive ? "hammer.fill" : "doc.text.magnifyingglass"
    }

    var body: some Scene {
        // MenuBarExtra creates a menu-bar-only app.
        // .window style gives us a detachable panel (as opposed to a
        // pull-down menu).
        MenuBarExtra("n-doc monitor", systemImage: menuBarIcon) {
            MonitorView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
