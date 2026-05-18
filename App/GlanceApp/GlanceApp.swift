import SwiftUI
import AppKit
import Combine
import KeyboardShortcuts
import CaptureEngine
import FrameProcessor

/// Glance main application — SwiftUI App with NSApplicationDelegate.
///
/// Wires together:
/// - GlancePipeline (CaptureEngine → FrameProcessor → AIClient → StateMachineViewModel)
/// - MenuBarManager (menu bar icon + menu)
/// - KeyboardShortcutManager (global shortcut ⌃⌥⌘G)
/// - OverlayWindow (floating overlay)
/// - PreferencesWindowController (preferences)
@main
public struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public var body: some Scene {
        // No main window — Glance is a menu bar app.
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

/// NSApplicationDelegate for Glance.
/// Manages the app lifecycle, pipeline, menu bar, overlay, and preferences.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Managers

    private let menuBarManager = MenuBarManager()
    private let preferencesViewModel = PreferencesViewModel()
    private var preferencesWindowController: PreferencesWindowController?
    private var overlayWindow: OverlayWindow?

    // MARK: - Pipeline

    /// The GlancePipeline orchestrating: Capture → Process → AI → Display.
    private let pipeline: GlancePipeline

    /// The ViewModel driving UX state (from the pipeline).
    private let viewModel: StateMachineViewModel

    // MARK: - Initialization

    public override init() {
        // Create the pipeline with default dependencies.
        let vm = StateMachineViewModel()
        self.viewModel = vm
        self.pipeline = GlancePipeline(viewModel: vm)
        super.init()
    }

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — menu bar app.
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar.
        menuBarManager.setup()
        menuBarManager.onShareScreen = { [weak self] in
            self?.triggerCapture()
        }
        menuBarManager.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }

        // Register global shortcut.
        KeyboardShortcuts.onKeyDown(for: .triggerCapture) { [weak self] in
            self?.triggerCapture()
        }

        // Observe state changes to update menu bar icon.
        observeViewModel()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Stop any active capture.
        pipeline.stopCapture()

        // Save preferences on quit.
        preferencesViewModel.saveCredentials()
    }

    // MARK: - Capture Flow

    /// Trigger a new screen capture flow.
    private func triggerCapture() {
        let mode = preferencesViewModel.defaultCaptureMode

        // Show the overlay immediately (mode picker).
        showOverlay(for: mode)

        // Start the capture pipeline asynchronously.
        Task {
            guard preferencesViewModel.hasAPIKey else {
                await MainActor.run {
                    viewModel.receiveError(message: "No API key configured. Add your key in Preferences.")
                }
                return
            }

            let apiKey = preferencesViewModel.apiKey
            let provider = preferencesViewModel.selectedProvider

            await pipeline.startCapture(
                mode: mode,
                apiKey: apiKey,
                provider: provider
            )
        }
    }

    // MARK: - Overlay Management

    /// Show the floating overlay panel with the current view.
    private func showOverlay(for mode: CaptureMode) {
        // Close any existing overlay.
        overlayWindow?.close()

        // Build the overlay content.
        let overlayView = OverlayContainer(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.dismissOverlay()
            },
            onCaptureModeSelected: { [weak self] selectedMode in
                // Mode selected via UI — update the pipeline's capture mode.
                // The capture engine handles the actual capture based on mode.
                self?.viewModel.selectedCaptureMode = selectedMode
                // Capture completion will be triggered by the pipeline once
                // the first frame arrives from ScreenCaptureKit.
            }
        )

        // Calculate initial size based on content.
        let windowRect = NSRect(x: 0, y: 0, width: 460, height: 320)

        // Create and show the overlay window.
        let window = OverlayWindow(contentRect: windowRect, rootView: overlayView)
        window.centerOnScreen()
        window.animateIn()

        // Handle window close (Esc key or programmatic).
        window.delegate = self

        overlayWindow = window

        // Update menu bar.
        menuBarManager.updateState(viewModel.state)
    }

    /// Refresh the overlay content when state changes.
    private func refreshOverlay() {
        guard let window = overlayWindow else { return }

        let overlayView = OverlayContainer(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.dismissOverlay()
            },
            onCaptureModeSelected: { [weak self] _ in
                // Re-entry from "Share Again" — handled by the pipeline.
                self?.triggerCapture()
            }
        )

        window.contentView = NSHostingView(rootView: overlayView)
        menuBarManager.updateState(viewModel.state)
    }

    /// Dismiss the overlay and reset state.
    private func dismissOverlay() {
        overlayWindow?.animateOut { [weak self] in
            self?.overlayWindow = nil
        }
        pipeline.stopCapture()
        viewModel.reset()
        menuBarManager.updateState(.idle)
    }

    // MARK: - Preferences

    /// Open the preferences window.
    private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                viewModel: preferencesViewModel
            )
        }
        preferencesWindowController?.show()
    }

    // MARK: - State Observation

    /// Observe ViewModel state changes to update UI.
    private func observeViewModel() {
        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func handleStateChange(_ newState: UXState) {
        menuBarManager.updateState(newState)

        switch newState {
        case .idle:
            // Overlay is dismissed — no action needed.
            break

        case .selecting, .preview, .thinking, .showing:
            // Refresh overlay content for state transitions.
            if overlayWindow != nil {
                refreshOverlay()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window === overlayWindow {
            overlayWindow = nil
            if !viewModel.isIdle {
                viewModel.reset()
                menuBarManager.updateState(.idle)
            }
        }
    }
}
