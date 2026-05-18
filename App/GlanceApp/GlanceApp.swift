import SwiftUI
import AppKit
import Combine
import KeyboardShortcuts

/// Glance main application — SwiftUI App with NSApplicationDelegate.
///
/// Wires together:
/// - MenuBarManager (menu bar icon + menu)
/// - KeyboardShortcutManager (global shortcut ⌃⌥⌘G)
/// - StateMachineViewModel (UX state machine)
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
/// Manages the app lifecycle, menu bar, overlay, and preferences.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Managers

    private let menuBarManager = MenuBarManager()
    private let viewModel = StateMachineViewModel()
    private let preferencesViewModel = PreferencesViewModel()
    private var preferencesWindowController: PreferencesWindowController?
    private var overlayWindow: OverlayWindow?

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
        // Save preferences on quit.
        preferencesViewModel.saveCredentials()
    }

    // MARK: - Capture Flow

    /// Trigger a new screen capture flow.
    private func triggerCapture() {
        let defaultMode = preferencesViewModel.defaultCaptureMode
        viewModel.startCaptureFlow(mode: defaultMode)

        // Show the overlay immediately (mode picker).
        showOverlay(for: defaultMode)
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
                // Mode selected — the capture engine (Phase 1.1) would take over here.
                // For now, simulate capture completion after mode selection.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.viewModel.completeCapture()
                    self?.refreshOverlay()
                }
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
                // Re-entry from "Share Again" — handled by the view model.
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
        // Use Combine to react to state transitions.
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

