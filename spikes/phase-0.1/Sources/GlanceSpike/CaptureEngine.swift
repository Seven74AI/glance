// GlanceSpike — Capture Engine
// ScreenCaptureKit integration: stream setup, frame delivery, latency measurement.

import ScreenCaptureKit
import AVFoundation
import CoreVideo

/// Manages SCK stream lifecycle and delivers frames with timing data.
final class CaptureEngine: NSObject, SCStreamOutput {
    
    /// Configuration for the capture stream.
    struct CaptureConfig {
        let fps: Int
        let captureDisplay: Bool  // true = full display, false = window (requires SCContentSharingPicker)
        let durationSeconds: Int
    }
    
    /// A frame delivered by SCK with capture timing.
    struct CapturedFrame {
        let pixelBuffer: CVPixelBuffer
        let captureTimeMs: Double   // Time from stream start to frame delivery
        let frameIndex: Int
        let status: SCFrameStatus
        let contentRect: CGRect
        let contentScale: CGFloat
    }
    
    // MARK: - State
    
    private let config: CaptureConfig
    private let metrics: PerformanceMetrics
    
    private var stream: SCStream?
    private var streamStartTime: DispatchTime?
    private var frameIndex: Int = 0
    private var targetFrameCount: Int = 0
    
    /// Called on each frame (from the sample handler queue).
    var onFrame: ((CapturedFrame) -> Void)?
    
    /// Called when capture completes.
    var onComplete: (() -> Void)?
    
    // MARK: - Init
    
    init(config: CaptureConfig, metrics: PerformanceMetrics) {
        self.config = config
        self.metrics = metrics
        super.init()
        self.targetFrameCount = config.fps * config.durationSeconds
    }
    
    // MARK: - Start Capture
    
    /// Start capturing the main display.
    /// - Note: Requires Screen Recording permission. On first launch,
    ///         macOS will prompt the user. Use SCContentSharingPicker in production.
    func startCapture() async throws {
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }
        
        print("  Display: \(display.width)×\(display.height)")
        
        // Create content filter for the main display
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        
        // Stream configuration
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = display.width
        streamConfig.height = display.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.queueDepth = 5  // Balance latency vs memory
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.scalesToFit = false
        streamConfig.showsCursor = true
        
        // Create and start stream
        let stream = SCStream(filter: filter, streamConfig: streamConfig, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        
        self.stream = stream
        self.streamStartTime = DispatchTime.now()
        
        print("  Starting capture at \(config.fps) fps for \(config.durationSeconds)s...")
        print("  Expecting \(targetFrameCount) frames\n")
        
        try await stream.startCapture()
        
        // Run for configured duration, then stop
        try await Task.sleep(nanoseconds: UInt64(config.durationSeconds) * 1_000_000_000)
        
        try await stream.stopCapture()
        
        print("  Capture complete. Received \(frameIndex) of \(targetFrameCount) expected frames.")
        
        onComplete?()
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        
        guard type == .screen else { return }
        
        let now = DispatchTime.now()
        let elapsed = streamStartTime.map { start in
            Double(now.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        } ?? 0
        
        frameIndex += 1
        
        // Check frame status
        guard let statusRaw = sampleBuffer.sampleBufferAttachments?[.frameStatus] as? Int64,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return  // Skip incomplete frames
        }
        
        // Extract pixel buffer
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }
        
        // Extract metadata
        let contentRect: CGRect = {
            if let dict = sampleBuffer.sampleBufferAttachments?[.contentRect] as? NSDictionary {
                return CGRect(
                    x: (dict["X"] as? CGFloat) ?? 0,
                    y: (dict["Y"] as? CGFloat) ?? 0,
                    width: (dict["Width"] as? CGFloat) ?? 0,
                    height: (dict["Height"] as? CGFloat) ?? 0
                )
            }
            return .zero
        }()
        
        let contentScale: CGFloat = {
            if let dict = sampleBuffer.sampleBufferAttachments?[.contentScale] as? NSDictionary {
                return (dict["ScaleFactor"] as? CGFloat) ?? 1.0
            }
            return 1.0
        }()
        
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            captureTimeMs: elapsed,
            frameIndex: frameIndex,
            status: status,
            contentRect: contentRect,
            contentScale: contentScale
        )
        
        // Record capture latency
        let captureLatency = elapsed - (Double(frameIndex - 1) * (1000.0 / Double(config.fps)))
        var frameMetrics = PerformanceMetrics.FrameMetrics(
            frameIndex: frameIndex,
            stages: [
                PerformanceMetrics.StageTiming(
                    stage: "capture",
                    durationMs: max(0, captureLatency),
                    timestamp: Date()
                )
            ]
        )
        
        onFrame?(frame)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplayAvailable
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available for capture"
        case .permissionDenied: return "Screen Recording permission denied"
        }
    }
}
