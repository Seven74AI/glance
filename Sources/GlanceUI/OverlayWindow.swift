import AppKit
import SwiftUI

/// Floating, non-activating overlay window for Glance UI.
///
/// Design decisions (ROADMAP.md):
/// - `level = .floating` — stays above normal windows
/// - `collectionBehavior = [.canJoinAllSpaces, .stationary]` — follows spaces
/// - Non-activating — doesn't steal focus from the user's current app
/// - Semi-transparent with blur background (macOS HIG panel style)
public final class OverlayWindow: NSWindow {

    // MARK: - Initialization

    /// Create a floating overlay window hosting a SwiftUI view.
    /// - Parameters:
    ///   - contentRect: Initial frame (typically centered on screen).
    ///   - view: The SwiftUI root view to host.
    public convenience init(contentRect: NSRect, rootView: some View) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating window level — above normal apps but below modal dialogs.
        level = .floating

        // Follow spaces, stay in place when switching.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Non-activating — user can type in other apps while overlay is visible.
        isOpaque = false
        hasShadow = true

        // Visual style: glass-like with subtle border.
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        isMovableByWindowBackground = false

        // Rounded corners.
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 16
        contentView?.layer?.masksToBounds = true

        // Host the SwiftUI view.
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView

        // Close on Esc key.
        self.isReleasedWhenClosed = false
    }

    // MARK: - Key Handling

    /// Override to handle Esc key for dismiss.
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            close()
            return
        }
        super.keyDown(with: event)
    }

    /// Allow Esc to close even without being key window.
    public override func cancelOperation(_ sender: Any?) {
        close()
    }

    // MARK: - Convenience

    /// Center the window on the main screen.
    public func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = frame
        let origin = NSPoint(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2
        )
        setFrameOrigin(origin)
    }

    /// Fade-in animation.
    public func animateIn() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }
    }

    /// Fade-out animation then close.
    public func animateOut(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.close()
            completion?()
        }
    }
}
