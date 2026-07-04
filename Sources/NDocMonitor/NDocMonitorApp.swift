import SwiftUI
import Combine

/// The main entry point for n-doc-monitor.
///
/// This app lives entirely in the macOS menu bar — there is no main window
/// and no Dock icon.  Clicking the menu bar icon opens a floating panel
/// showing the current build status.
///
/// **SwiftUI concepts used here:**
/// - `@main` marks this struct as the application entry point.
///
/// **Step 9 — Floating Window:**
/// We replaced `MenuBarExtra` with a custom `StatusItemController`
/// backed by `NSStatusItem` + `FloatingPanel`.  This gives us full
/// control over window behaviour:
/// - The panel stays visible when you click outside it.
/// - It floats above other windows.
/// - It can be dragged anywhere.
/// - A "reset position" button snaps it back under the menu bar icon.
///
/// **AppKit concept — `NSApplicationDelegateAdaptor`:**
/// Since we no longer have a `MenuBarExtra` scene, we need an
/// `NSApplicationDelegate` to set up the status item when the app
/// launches.  `@NSApplicationDelegateAdaptor` bridges AppKit's
/// delegate pattern into SwiftUI's app lifecycle.
@main
struct NDocMonitorApp: App {
    /// Bridge to AppKit's application delegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible scenes — everything is managed by the
        // StatusItemController via the AppDelegate.
        //
        // **Step 8 — Settings scene:**
        // The `Settings` scene creates a standard macOS Preferences
        // window.  It's accessible programmatically via
        // `NSApp.sendAction(Selector(("showSettingsWindow:")))`.
        Settings {
            SettingsView()
        }
    }
}

/// The AppKit application delegate that owns the status item and monitor.
///
/// **Why a delegate instead of `MenuBarExtra`?**
/// `MenuBarExtra(.window)` auto-dismisses the panel on focus loss.
/// We need the panel to persist as a floating window.  Using
/// `NSApplicationDelegate` + `StatusItemController` gives us that
/// control while still hosting SwiftUI views inside the panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let monitor = BuildMonitor()
    private let statusItemController = StatusItemController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon — this app lives only in the menu bar.
        // With `MenuBarExtra` this was automatic; with a custom
        // `NSStatusItem` we need to set it explicitly.
        NSApp.setActivationPolicy(.accessory)
        // Set up the status item with the initial monitor view.
        statusItemController.setUp(icon: "doc.text.magnifyingglass") { [weak self] in
            MonitorView(
                monitor: self?.monitor ?? BuildMonitor(),
                onResetPosition: { self?.statusItemController.resetPanelPosition() },
                onShowAbout: { Self.showAboutPanel() },
                onShowSettings: { Self.showSettingsWindow() },
                onQuit: { NSApp.terminate(nil) }
            )
        }

        // Start monitoring.
        monitor.startMonitoring()

        // Update the menu bar icon when build state changes.
        monitor.$activeBuilds
            .receive(on: RunLoop.main)
            .sink { [weak self] builds in
                let icon = builds.isEmpty
                    ? "doc.text.magnifyingglass"
                    : "hammer.fill"
                self?.statusItemController.updateIcon(icon)
            }
            .store(in: &cancellables)
    }

    // MARK: - About & Settings

    /// Show the standard macOS About panel.
    ///
    /// **AppKit concept — `orderFrontStandardAboutPanel`:**
    /// Every macOS app has a built-in About panel that shows the
    /// app name, version, and copyright.  It reads from the app's
    /// `Info.plist` (or we can pass custom options).
    ///
    /// We also temporarily switch to `.regular` activation policy
    /// so the About panel can appear in front of other apps.
    static func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "n-doc monitor",
            .applicationVersion: "1.0.0",
            .version: "1",
            .credits: NSAttributedString(
                string: "A macOS menu bar app for monitoring n-doc LaTeX builds.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ])
    }

    /// Open the SwiftUI Settings window.
    ///
    /// **Step 8 — opening Settings programmatically:**
    /// SwiftUI's `Settings` scene creates a window that responds to
    /// the `showSettingsWindow:` selector.  We send that action to
    /// the first responder, which lets the SwiftUI framework handle
    /// presenting it.
    static func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
