import Foundation
import CoreMedia
import ScreenCaptureKit

// MARK: - CaptureEngine

/// Core screen capture engine wrapping ScreenCaptureKit.
///
/// Provides window + display capture with configurable frame rate,
/// frame dropping strategy, and permission management.
///
/// Thread safety: delegate callbacks are delivered on a dedicated
/// serial dispatch queue. Public API is main-thread safe.
final class CaptureEngine: CaptureEngineProtocol {

    // MARK: - Public Properties

    weak var delegate: CaptureEngineDelegate?

    /// Whether the engine is currently capturing frames
    private(set) var isCapturing = false

    // MARK: - Private Properties

    /// Active SCK stream
    private var stream: SCStreamProtocol?

    /// Frame queue for managing delivery and dropping
    private let frameQueue: FrameQueue

    /// Permission helper for authorization UX
    private let permissionHelper: PermissionHelperProtocol

    /// Factory for creating SCStream instances (injectable for testing)
    private let streamFactory: (SCContentFilterProtocol) -> SCStreamProtocol

    /// Serial queue for frame processing to avoid blocking SCK callback
    private let processingQueue = DispatchQueue(
        label: "com.glance.capture-engine.processing",
        qos: .userInteractive
    )

    /// Current capture configuration
    private var currentFPS: Int = 10

    // MARK: - Initialization

    /// Creates a capture engine.
    /// - Parameters:
    ///   - streamFactory: Factory closure for creating SCStreamProtocol instances.
    ///     Defaults to the real SCStream adapter. Inject mock for testing.
    ///   - permissionHelper: Permission UX handler.
    ///   - queueDepth: Maximum frames to buffer (default 3 per SCK best practices).
    init(
        streamFactory: @escaping (SCContentFilterProtocol) -> SCStreamProtocol = { filter in
            SCStreamAdapter(filter: filter)
        },
        permissionHelper: PermissionHelperProtocol = PermissionHelper(),
        queueDepth: Int = 3
    ) {
        self.streamFactory = streamFactory
        self.permissionHelper = permissionHelper
        self.frameQueue = FrameQueue(maxDepth: queueDepth)
    }

    // MARK: - Permission

    func canCapture() -> Bool {
        permissionHelper.isAuthorized
    }

    // MARK: - Shareable Content

    func listShareableContent() async throws -> ShareableContentProtocol {
        let content = try await SCShareableContent.current

        let displays = content.displays.map { display in
            ConcreteDisplay(
                displayID: display.displayID,
                width: Int(display.width),
                height: Int(display.height)
            )
        }

        let applications = content.applications.map { app in
            ConcreteApplication(
                bundleIdentifier: app.bundleIdentifier,
                applicationName: app.applicationName
            )
        }

        let windows = content.windows.map { window in
            ConcreteWindow(
                windowID: window.windowID,
                title: window.title,
                applicationName: window.owningApplication?.applicationName ?? ""
            )
        }

        return ShareableContent(
            displays: displays,
            applications: applications,
            windows: windows
        )
    }

    // MARK: - Capture Lifecycle

    func startCapture(filter: SCContentFilterProtocol, fps: Int) {
        if isCapturing {
            // Stop existing stream before starting new one
            stopCapture()
        }

        let clampedFPS = max(1, min(fps, 60))
        currentFPS = clampedFPS

        do {
            // Create stream via factory (real or mock)
            let stream = streamFactory(filter)
            self.stream = stream

            // Wire frame delivery via protocol — works for both mock and real streams
            stream.outputHandler = { [weak self] frame in
                self?.handleFrame(frame)
            }

            // Configure stream
            let config = makeConfiguration(fps: clampedFPS)

            // Start capture
            try stream.startCapture(configuration: config, filter: filter)
            isCapturing = true

        } catch {
            delegate?.captureEngine(self, didEncounterError: error)
        }
    }

    func stopCapture() {
        guard let stream = stream else {
            isCapturing = false
            return
        }

        do {
            try stream.stopCapture()
        } catch {
            delegate?.captureEngine(self, didEncounterError: error)
        }

        self.stream = nil
        isCapturing = false
        frameQueue.clear()
        delegate?.captureEngineDidStop(self)
    }

    // MARK: - Frame Handling

    /// Called by SCStreamOutput handler. Processes frames and dispatches to delegate.
    /// - Parameter frame: The captured frame with pixel buffer and metadata.
    private func handleFrame(_ frame: CapturedFrame) {
        // Enqueue frame — drops oldest if queue is full
        _ = frameQueue.enqueue(frame)

        // Process frames on the dedicated queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            while let nextFrame = self.frameQueue.dequeue() {
                let metadata = FrameMetadata(
                    timestamp: nextFrame.timestamp,
                    contentRect: nextFrame.contentRect,
                    scaleFactor: nextFrame.scaleFactor,
                    status: .complete
                )

                DispatchQueue.main.async {
                    self.delegate?.captureEngine(
                        self,
                        didReceiveFrame: nextFrame.pixelBuffer,
                        metadata: metadata
                    )
                }
            }
        }
    }

    // MARK: - Configuration

    /// Creates an SCStreamConfiguration for the given FPS.
    /// - Parameter fps: Target frames per second (1-60).
    /// - Returns: Configured SCStreamConfiguration.
    private func makeConfiguration(fps: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()

        // Resolution: 1080p target for AI processing
        config.width = 1920
        config.height = 1080

        // Pixel format: BGRA8 (IOSurface-backed) — stays on GPU
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // Queue depth: 3 frames (SCK best practice)
        config.queueDepth = 3

        // Frame interval: CMTime based on fps
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.minimumFrameInterval = frameDuration

        // Color space: sRGB for consistent AI processing
        config.colorSpaceName = CGColorSpace.sRGB

        return config
    }
}

// MARK: - SCK Adapter (Production)

/// Production adapter that wraps the real ScreenCaptureKit SCStream.
/// Implements SCStreamProtocol for testability.
final class SCStreamAdapter: NSObject, SCStreamProtocol {

    private var stream: SCStream?
    private var filter: SCContentFilterProtocol
    private let outputQueue: DispatchQueue

    /// Callback invoked when a new frame is received from SCK
    var outputHandler: ((CapturedFrame) -> Void)?

    init(filter: SCContentFilterProtocol) {
        self.filter = filter
        self.outputQueue = DispatchQueue(label: "com.glance.scstream.output", qos: .userInteractive)
        super.init()
    }

    func startCapture(configuration: SCStreamConfigurationProtocol,
                      filter: SCContentFilterProtocol) throws {
        guard let realConfig = configuration as? SCStreamConfiguration else {
            throw CaptureEngineError.invalidConfiguration
        }

        guard let realFilter = filter as? SCContentFilter else {
            // Test path — mock filter, no real SCStream needed
            return
        }

        self.filter = filter
        let stream = SCStream(filter: realFilter,
                              configuration: realConfig,
                              delegate: nil)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try stream.startCapture()
    }

    func stopCapture() throws {
        if let stream = stream {
            try stream.stopCapture()
            try stream.removeStreamOutput(self, type: .screen)
            self.stream = nil
        }
    }
}

// MARK: - SCStreamOutput

extension SCStreamAdapter: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Extract CVPixelBuffer from CMSampleBuffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let frame = CapturedFrame(
            pixelBuffer: imageBuffer,
            timestamp: timestamp,
            contentRect: .zero,
            scaleFactor: 1.0
        )

        outputHandler?(frame)
    }
}

// MARK: - Concrete Types

// MARK: - SCK Protocol Conformances (Production Bridge)

extension SCStreamConfiguration: SCStreamConfigurationProtocol {}
extension SCContentFilter: SCContentFilterProtocol {}
extension SCDisplay: DisplayProtocol {}
extension SCRunningApplication: ApplicationProtocol {}
extension SCWindow: WindowProtocol {
    var applicationName: String {
        owningApplication?.applicationName ?? ""
    }
}

// MARK: - Concrete Types (Testing)

struct ConcreteDisplay: DisplayProtocol {
    let displayID: UInt32
    let width: Int
    let height: Int
}

struct ConcreteApplication: ApplicationProtocol {
    let bundleIdentifier: String
    let applicationName: String
}

struct ConcreteWindow: WindowProtocol {
    let windowID: UInt32
    let title: String?
    let applicationName: String
}
