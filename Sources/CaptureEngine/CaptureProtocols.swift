import Foundation
import CoreMedia
import CoreGraphics

// MARK: - ScreenCaptureKit Protocols (Testability Layer)

/// Wraps SCStream for testability
protocol SCStreamProtocol: AnyObject {
    func startCapture(configuration: SCStreamConfigurationProtocol,
                      filter: SCContentFilterProtocol) throws
    func stopCapture() throws
}

/// Wraps SCStreamConfiguration
protocol SCStreamConfigurationProtocol: AnyObject {
    var width: Int { get set }
    var height: Int { get set }
    var pixelFormat: PixelFormat { get set }
    var queueDepth: Int { get set }
    var minimumFrameInterval: CMTime { get set }
    var colorSpaceName: CFString? { get set }
}

/// Wraps SCContentFilter
protocol SCContentFilterProtocol: AnyObject {
    var contentRect: CGRect { get set }
    var pointPixelScale: CGFloat { get set }
}

// MARK: - Shared Content Protocols

protocol ShareableContentProtocol {
    var displays: [DisplayProtocol] { get }
    var applications: [ApplicationProtocol] { get }
    var windows: [WindowProtocol] { get }
}

protocol DisplayProtocol {
    var displayID: UInt32 { get }
    var width: Int { get }
    var height: Int { get }
}

protocol ApplicationProtocol {
    var bundleIdentifier: String { get }
    var applicationName: String { get }
}

protocol WindowProtocol {
    var windowID: UInt32 { get }
    var title: String { get }
    var applicationName: String { get }
}

// MARK: - Pixel Format

enum PixelFormat {
    case BGRA8
    case YUV420
}

// MARK: - Frame Status

enum SCFrameStatus {
    case complete
    case idle
    case blank
    case suspended
    case started
    case stopped
}

// MARK: - Frame Metadata

/// Metadata accompanying each captured frame
struct FrameMetadata {
    let timestamp: CMTime
    let contentRect: CGRect
    let scaleFactor: CGFloat
    let status: SCFrameStatus

    init(timestamp: CMTime = .invalid,
         contentRect: CGRect = .zero,
         scaleFactor: CGFloat = 1.0,
         status: SCFrameStatus = .complete) {
        self.timestamp = timestamp
        self.contentRect = contentRect
        self.scaleFactor = scaleFactor
        self.status = status
    }
}

// MARK: - Captured Frame Protocol

protocol CapturedFrameProtocol {
    var pixelBuffer: CVPixelBuffer { get }
    var timestamp: CMTime { get }
    var contentRect: CGRect { get }
    var scaleFactor: CGFloat { get }
}

// MARK: - Capture Engine Protocols

protocol CaptureEngineProtocol: AnyObject {
    var delegate: CaptureEngineDelegate? { get set }
    var isCapturing: Bool { get }

    func canCapture() -> Bool
    func listShareableContent() async throws -> ShareableContentProtocol
    func startCapture(filter: SCContentFilterProtocol, fps: Int)
    func stopCapture()
}

// MARK: - Capture Engine Delegate

protocol CaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: CaptureEngineProtocol,
                       didReceiveFrame buffer: CVPixelBuffer,
                       metadata: FrameMetadata)
    func captureEngineDidStop(_ engine: CaptureEngineProtocol)
    func captureEngine(_ engine: CaptureEngineProtocol,
                       didEncounterError error: Error)
}

// MARK: - Permission Authorization

protocol PermissionHelperProtocol: AnyObject {
    var isAuthorized: Bool { get }
    func requestPermission() async -> CaptureAuthorizationStatus
    func openSystemPreferences()
}

enum CaptureAuthorizationStatus {
    case notDetermined
    case denied
    case granted
}

// MARK: - Shareable Content (Concrete)

/// Concrete result from listing shareable content
struct ShareableContent: ShareableContentProtocol {
    let displays: [DisplayProtocol]
    let applications: [ApplicationProtocol]
    let windows: [WindowProtocol]
}

// MARK: - Capture Engine Errors

enum CaptureEngineError: LocalizedError {
    case permissionDenied
    case noDisplayAvailable
    case streamAlreadyActive
    case invalidConfiguration
    case streamError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required. Grant access in System Preferences > Privacy & Security > Screen Recording."
        case .noDisplayAvailable:
            return "No display available for capture."
        case .streamAlreadyActive:
            return "Capture stream is already active. Stop the current stream first."
        case .invalidConfiguration:
            return "Invalid capture configuration."
        case .streamError(let error):
            return "Stream error: \(error.localizedDescription)"
        }
    }
}
