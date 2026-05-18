import AppKit
import KeyboardShortcuts

/// Global keyboard shortcut manager for Glance.
///
/// Default shortcut: ⌃⌥⌘G (Control-Option-Command-G)
/// Configurable via Preferences.
extension KeyboardShortcuts.Name {
    /// The global shortcut to trigger screen capture.
    static let triggerCapture = Self("triggerCapture", default: .init(.g, modifiers: [.control, .option, .command]))
}
