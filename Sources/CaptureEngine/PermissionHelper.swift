import Foundation
import AppKit

/// Handles screen recording permission requests and authorization status.
/// Provides UX guidance when permission is denied.
final class PermissionHelper: PermissionHelperProtocol {

    /// Current screen recording authorization status.
    /// Must be called on the main thread as it accesses system preferences.
    func currentAuthorizationStatus() -> CaptureAuthorizationStatus {
        // ScreenCaptureKit authorization check — actual implementation
        // uses CGPreflightScreenCaptureAccess() on macOS 14+
        let hasPermission = CGPreflightScreenCaptureAccess()

        if hasPermission {
            return .granted
        }

        // Check if it's been explicitly denied vs. never asked
        // CGRequestScreenCaptureAccess returns false for both denied and notDetermined;
        // we distinguish by checking if a request has ever been made.
        // On first launch, neither prompt nor denial has occurred.
        let hasBeenPrompted = UserDefaults.standard.bool(forKey: "screen_capture_permission_prompted")
        return hasBeenPrompted ? .denied : .notDetermined
    }

    /// Returns whether screen capture is currently authorized.
    var isAuthorized: Bool {
        currentAuthorizationStatus() == .granted
    }

    /// Requests screen recording permission from the user.
    /// On first call, macOS shows the system permission prompt.
    /// On subsequent calls when denied, opens System Preferences.
    /// - Returns: The resulting authorization status.
    @MainActor
    func requestPermission() async -> CaptureAuthorizationStatus {
        let current = currentAuthorizationStatus()

        switch current {
        case .granted:
            return .granted

        case .notDetermined:
            // Trigger the system prompt
            let granted = await requestSystemPrompt()
            UserDefaults.standard.set(true, forKey: "screen_capture_permission_prompted")
            return granted ? .granted : .denied

        case .denied:
            // User has previously denied — offer to open System Preferences
            openSystemPreferences()
            return .denied
        }
    }

    /// Opens System Preferences to the Screen Recording privacy pane.
    /// Uses the modern URL scheme (macOS 13+) with fallback.
    func openSystemPreferences() {
        // macOS Ventura+ uses x-apple.systempreferences:
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
            return
        }

        // Fallback: open Security & Privacy pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    /// Triggers the system screen recording permission prompt.
    /// Uses CGRequestScreenCaptureAccess which shows the native macOS dialog.
    private func requestSystemPrompt() async -> Bool {
        await withCheckedContinuation { continuation in
            CGRequestScreenCaptureAccess { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - C API Declarations

/// Check whether screen capture access has been granted.
@_silgen_name("CGPreflightScreenCaptureAccess")
private func CGPreflightScreenCaptureAccess() -> Bool

/// Request screen capture access. Shows system prompt if not yet determined.
@_silgen_name("CGRequestScreenCaptureAccess")
private func CGRequestScreenCaptureAccess(completion: @escaping (Bool) -> Void)
