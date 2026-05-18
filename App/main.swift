import AppKit
import ScreenCaptureKit
import CaptureEngine

/// Minimal test application to verify screen capture functionality.
/// Displays captured frames in a window as a live preview.

@main
struct GlanceTestApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var imageView: NSImageView!
    private let engine = CaptureEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check permission
        checkAndRequestPermission()

        // 2. Create window
        setupWindow()

        // 3. Set up capture delegate
        engine.delegate = self

        // 4. Start capture (uses first available display)
        startCapture()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stopCapture()
    }

    // MARK: - Setup

    private func checkAndRequestPermission() {
        guard !engine.canCapture() else { return }

        Task { @MainActor in
            let helper = PermissionHelper()
            let status = await helper.requestPermission()

            if status == .denied {
                showPermissionAlert()
            }
        }
    }

    private func setupWindow() {
        let rect = NSRect(x: 100, y: 100, width: 960, height: 540)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Glance — Capture Test"
        window.makeKeyAndOrderFront(nil)

        imageView = NSImageView(frame: window.contentView!.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(imageView)
    }

    private func startCapture() {
        Task {
            do {
                let content = try await engine.listShareableContent()

                guard let display = content.displays.first as? SCDisplay else {
                    print("No displays available for capture")
                    return
                }

                // Create a content filter for the primary display
                let filter = SCContentFilter(display: display,
                                              excludingWindows: [])

                engine.startCapture(filter: filter, fps: 10)
                print("Capture started at 10fps on display \(display.displayID)")

            } catch {
                print("Failed to start capture: \(error.localizedDescription)")
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        Glance needs screen recording permission to capture your screen.

        Please enable it in:
        System Preferences > Privacy & Security > Screen Recording
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            PermissionHelper().openSystemPreferences()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - CaptureEngineDelegate

extension AppDelegate: CaptureEngineDelegate {
    func captureEngine(_ engine: CaptureEngineProtocol,
                       didReceiveFrame buffer: CVPixelBuffer,
                       metadata: FrameMetadata) {
        // Convert CVPixelBuffer to NSImage for display
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        DispatchQueue.main.async { [weak self] in
            self?.imageView.image = nsImage
        }
    }

    func captureEngineDidStop(_ engine: CaptureEngineProtocol) {
        print("Capture stopped")
    }

    func captureEngine(_ engine: CaptureEngineProtocol,
                       didEncounterError error: Error) {
        print("Capture error: \(error.localizedDescription)")
    }
}
