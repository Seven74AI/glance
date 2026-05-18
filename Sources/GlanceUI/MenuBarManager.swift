import AppKit
import SwiftUI

/// Manages the Glance menu bar icon and menu.
///
/// Features:
/// - Menu bar icon (gray = idle, green = active, orange = thinking)
/// - Menu items: "Share Screen", "Preferences...", "Quit"
/// - Status item updates based on UX state
public final class MenuBarManager: NSObject, NSMenuDelegate {
    // MARK: - State

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    /// Current UX state — drives icon color.
    private var currentState: UXState = .idle

    /// Callbacks for menu actions.
    public var onShareScreen: (() -> Void)?
    public var onOpenPreferences: (() -> Void)?

    // MARK: - Setup

    /// Create and configure the menu bar item.
    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Set initial icon.
        updateIcon(for: .idle)

        // Click to open menu.
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Tooltip.
        button.toolTip = "Glance — Share screen with AI (⌃⌥⌘G)"

        // Build menu.
        buildMenu()
    }

    // MARK: - Menu Building

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = true

        // Share Screen item.
        let shareItem = NSMenuItem(
            title: "Share Screen",
            action: #selector(shareScreenAction),
            keyEquivalent: ""
        )
        shareItem.target = self
        shareItem.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "Share Screen"
        )
        menu.addItem(shareItem)

        menu.addItem(.separator())

        // Preferences item.
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferencesAction),
            keyEquivalent: ","
        )
        prefsItem.target = self
        prefsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Preferences"
        )
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // Status section (non-interactive).
        let statusTitle = "Status: Ready"
        let statusItem = NSMenuItem(
            title: statusTitle,
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        statusItem.identifier = NSUserInterfaceItemIdentifier("statusItem")
        menu.addItem(statusItem)

        menu.addItem(.separator())

        // Quit item.
        let quitItem = NSMenuItem(
            title: "Quit Glance",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
    }

    // MARK: - State Updates

    /// Update the menu bar icon based on UX state.
    public func updateState(_ state: UXState) {
        currentState = state
        updateIcon(for: state)

        // Update status text in menu.
        if let statusMenuItem = menu?.items.first(where: {
            $0.identifier?.rawValue == "statusItem"
        }) {
            statusMenuItem.title = statusLabel(for: state)
        }
    }

    /// Update icon color based on state.
    private func updateIcon(for state: UXState) {
        guard let button = statusItem?.button else { return }

        let symbolName = "camera.macro"
        let color: NSColor

        switch state {
        case .idle:
            color = .secondaryLabelColor       // Gray
        case .selecting, .preview:
            color = .systemGreen                 // Green (active)
        case .thinking:
            color = .systemOrange                // Orange (thinking)
        case .showing:
            color = .systemGreen                 // Green (response showing)
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            button.image = image.withSymbolConfiguration(config)
        }
    }

    private func statusLabel(for state: UXState) -> String {
        switch state {
        case .idle:     return "Status: Ready"
        case .selecting: return "Status: Selecting capture mode..."
        case .preview:  return "Status: Previewing screenshot"
        case .thinking:  return "Status: AI analyzing..."
        case .showing:  return "Status: AI response ready"
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button, let menu = menu else { return }
        statusItem?.menu = menu
        button.performClick(nil)
    }

    @objc private func shareScreenAction() {
        onShareScreen?()
    }

    @objc private func openPreferencesAction() {
        onOpenPreferences?()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    public func menuDidClose(_ menu: NSMenu) {
        // Detach menu so left-click works as a toggle next time.
        statusItem?.menu = nil
    }
}
