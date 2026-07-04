import AppKit
import SwiftUI

/// Manages the menu bar status item and its associated floating panel.
///
/// **Step 9 — Floating Window:**
///
/// SwiftUI's `MenuBarExtra` is convenient but limited: the `.window`
/// style creates a panel that auto-dismisses on focus loss, and we
/// can't customise the underlying `NSWindow`.
///
/// This controller replaces `MenuBarExtra` with AppKit's
/// `NSStatusItem` + our custom `FloatingPanel`.  The panel:
/// - Stays visible until explicitly closed
/// - Floats above other windows
/// - Can be dragged anywhere on screen
/// - Has a "reset position" action to snap back under the status item
///
/// **AppKit concept — `NSStatusItem`:**
/// An `NSStatusItem` is the AppKit equivalent of a menu bar icon.
/// We create one via `NSStatusBar.system.statusItem(withLength:)`.
/// When the user clicks it, we toggle the floating panel.
@MainActor
final class StatusItemController {

    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?

    /// The SwiftUI view hosted inside the panel.
    /// Stored so we can update it when the monitor changes.
    private var hostingView: NSHostingView<AnyView>?

    /// Set up the status item and panel with the given SwiftUI content.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name for the menu bar icon.
    ///   - content: A closure returning the SwiftUI view to display.
    func setUp<Content: View>(icon: String, content: @escaping () -> Content) {
        // Create status item
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: icon, accessibilityDescription: "n-doc monitor")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        self.statusItem = item

        // Create floating panel
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200))
        let hosting = NSHostingView(rootView: AnyView(content()))
        panel.contentView = hosting
        self.hostingView = hosting
        self.panel = panel
    }

    /// Update the menu bar icon.
    func updateIcon(_ symbolName: String) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "n-doc monitor"
        )
    }

    /// Update the panel's SwiftUI content.
    func updateContent<Content: View>(_ content: Content) {
        hostingView?.rootView = AnyView(content)
    }

    /// Toggle the panel's visibility.
    func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionPanelUnderStatusItem()
            panel.orderFront(nil)
        }
    }

    /// Snap the panel back to its default position under the status item.
    ///
    /// This is the "reset position" action requested in Step 9.
    func resetPanelPosition() {
        positionPanelUnderStatusItem()
    }

    /// Whether the panel is currently visible.
    var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Private

    @objc private func statusItemClicked(_ sender: Any?) {
        togglePanel()
    }

    /// Position the panel directly below the status item, centered.
    private func positionPanelUnderStatusItem() {
        guard let panel = panel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // Get the status item's frame in screen coordinates.
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)

        // Centre the panel horizontally under the button, 4pt gap.
        let panelWidth = panel.frame.width
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY - panel.frame.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
