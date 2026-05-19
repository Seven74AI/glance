import Foundation
import CoreMedia
import CoreVideo
@testable import CaptureEngine

// MARK: - Mock SCStream

final class MockSCStream: SCStreamProtocol {
    var didStart = false
    var didStop = false
    var lastConfiguration: MockSCStreamConfiguration?
    var outputHandler: ((CapturedFrame) -> Void)?

    // Error simulation
    var errorHandler: ((Error) -> Void)?

    func startCapture(configuration: SCStreamConfigurationProtocol,
                      filter: SCContentFilterProtocol) throws {
        didStart = true
        // Store configuration values regardless of concrete type
        lastConfiguration = MockSCStreamConfiguration()
        lastConfiguration?.width = configuration.width
        lastConfiguration?.height = configuration.height
        lastConfiguration?.pixelFormat = configuration.pixelFormat
        lastConfiguration?.queueDepth = configuration.queueDepth
        lastConfiguration?.minimumFrameInterval = configuration.minimumFrameInterval
    }

    func stopCapture() throws {
        didStop = true
        outputHandler = nil
    }

    func simulateFrame(buffer: CVPixelBuffer, status: SCFrameStatus) {
        guard status == .complete else { return }
        let frame = CapturedFrame(
            pixelBuffer: buffer,
            timestamp: CMTime(value: 1, timescale: 10),
            contentRect: .zero,
            scaleFactor: 1.0
        )
        outputHandler?(frame)
    }

    func simulateError(_ error: Error) {
        errorHandler?(error)
    }
}

// MARK: - Mock SCStreamConfiguration

final class MockSCStreamConfiguration: NSObject, SCStreamConfigurationProtocol {
    var width: Int = 0
    var height: Int = 0
    var pixelFormat: Int = 0
    var queueDepth: Int = 3
    var minimumFrameInterval: CMTime = .invalid
    var colorSpaceName: CGColorSpace? = nil
}

// MARK: - Mock SCContentFilter

final class MockSCContentFilter: NSObject, SCContentFilterProtocol {
    var contentRect: CGRect = .zero
    var pointPixelScale: CGFloat = 1.0
}

// MARK: - Mock Shareable Content Types

struct MockShareableContent: ShareableContentProtocol {
    let displays: [DisplayProtocol]
    let applications: [ApplicationProtocol]
    let windows: [WindowProtocol]
}

struct MockDisplay: DisplayProtocol {
    let displayID: UInt32
    let width: Int
    let height: Int
}

struct MockApp: ApplicationProtocol {
    let bundleIdentifier: String
    let applicationName: String
}

struct MockWindow: WindowProtocol {
    let windowID: UInt32
    let title: String?
    let applicationName: String
}

// MARK: - Mock CVPixelBuffer (Test Helper)

/// Creates a real CVPixelBuffer for use in tests.
/// Uses CoreVideo to allocate a BGRA8 buffer matching production config.
func makeTestPixelBuffer(width: Int = 1920, height: Int = 1080) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]

    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width, height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        fatalError("Failed to create test pixel buffer: \(status)")
    }

    return buffer
}

// MARK: - Mock CapturedFrame

struct MockCapturedFrame: CapturedFrameProtocol {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let contentRect: CGRect
    let scaleFactor: CGFloat
}

// MARK: - Mock CaptureEngine Delegate

final class MockCaptureEngineDelegate: CaptureEngineDelegate {
    var didReceiveFrame = false
    var lastBuffer: CVPixelBuffer?
    var lastMetadata: FrameMetadata?
    var receivedFrames: [(CVPixelBuffer, FrameMetadata)] = []
    var processingDelay: TimeInterval = 0

    var didStopWasCalled = false
    var didEncounterError = false
    var lastError: Error?

    func captureEngine(_ engine: CaptureEngineProtocol,
                       didReceiveFrame buffer: CVPixelBuffer,
                       metadata: FrameMetadata) {
        didReceiveFrame = true
        lastBuffer = buffer
        lastMetadata = metadata
        receivedFrames.append((buffer, metadata))

        if processingDelay > 0 {
            Thread.sleep(forTimeInterval: processingDelay)
        }
    }

    func captureEngineDidStop(_ engine: CaptureEngineProtocol) {
        didStopWasCalled = true
    }

    func captureEngine(_ engine: CaptureEngineProtocol,
                       didEncounterError error: Error) {
        didEncounterError = true
        lastError = error
    }
}

// MARK: - Mock Authorization Status

enum MockAuthorizationStatus {
    case notDetermined
    case denied
    case granted
}

// MARK: - Mock PermissionHelper

final class MockPermissionHelper: PermissionHelperProtocol {
    var mockIsAuthorized = false
    var didRequestPermission = false
    var didOpenPreferences = false
    var mockPermissionResult: CaptureAuthorizationStatus = .denied

    var isAuthorized: Bool {
        mockIsAuthorized
    }

    func requestPermission() async -> CaptureAuthorizationStatus {
        didRequestPermission = true
        return mockPermissionResult
    }

    func openSystemPreferences() {
        didOpenPreferences = true
    }
}
