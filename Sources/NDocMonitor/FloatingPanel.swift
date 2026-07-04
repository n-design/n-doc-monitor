import AppKit
import SwiftUI

/// An `NSPanel` subclass configured as a floating, always-on-top panel.
///
/// **Step 9 — Floating Window:**
///
/// `MenuBarExtra` with `.window` style creates a panel that dismisses
/// when the user clicks outside.  For a build monitor, the user wants
/// the window to stay visible while they work.
///
/// This class provides:
/// - Always-on-top (`level = .floating`)
/// - Moveable by dragging the background
/// - Stays visible when the app is not focused
/// - Transparent title bar for a clean look
/// - Can host any SwiftUI view via `NSHostingView`
///
/// **AppKit concept — `NSPanel`:**
/// `NSPanel` is a subclass of `NSWindow` designed for auxiliary
/// windows like inspectors and tool palettes.  The key style mask
/// `.nonactivatingPanel` means clicking the panel does *not* steal
/// focus from the user's current app (e.g. their editor).
class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Float above normal windows.
        isFloatingPanel = true
        level = .floating

        // Overlay in fullscreen spaces.
        collectionBehavior.insert(.fullScreenAuxiliary)
        // Allow the panel to join all spaces if desired.
        collectionBehavior.insert(.canJoinAllSpaces)

        // Transparent title bar for a clean look.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Drag anywhere on the background to move.
        isMovableByWindowBackground = true

        // Don't hide when the app deactivates — this is the key
        // difference from the default MenuBarExtra behavior.
        hidesOnDeactivate = false

        // Hide traffic light buttons.
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Utility animation style.
        animationBehavior = .utilityWindow

        // Don't give any button the initial keyboard focus
        // (avoids the blue focus ring on first appearance).
        initialFirstResponder = nil
    }

    /// Allow the panel to become the key window (needed for
    /// interactive controls like buttons inside the SwiftUI content).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
