import Foundation

/// Capture mode selected by the user.
public enum CaptureMode: Equatable, Sendable {
    /// Click a window to capture it (uses SCContentSharingPicker).
    case windowUnderCursor
    /// Draw a rectangle region (crosshair cursor).
    case drawRegion
    /// Capture the entire current display.
    case fullScreen

    /// Human-readable label for the capture mode.
    public var label: String {
        switch self {
        case .windowUnderCursor: return "Window under cursor"
        case .drawRegion: return "Draw region"
        case .fullScreen: return "Full screen"
        }
    }
}
