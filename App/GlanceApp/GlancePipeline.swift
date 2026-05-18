import Foundation
import Combine
import CoreMedia
import ScreenCaptureKit
import CaptureEngine
import FrameProcessor
import GlanceUI

// MARK: - Protocol

/// GlancePipeline orchestrates the full screen-to-AI pipeline.
///
/// Flow: ScreenCaptureKit → FrameProcessor (Metal+JPEG) → AIClient → StateMachineViewModel
///
/// This is the central coordinator that wires Phase 1 modules together:
/// - CaptureEngine (Phase 1.1) for screen capture
/// - FrameProcessor (Phase 1.2) for Metal preprocessing + JPEG encoding
/// - AIClient for AI API calls
/// - GlanceUI (Phase 1.4) for UX state management
@available(macOS 14.0, *)
protocol GlancePipelineProtocol: AnyObject {
    /// The engine used for screen capture.
    var captureEngine: CaptureEngineProtocol { get }

    /// The frame processor for Metal preprocessing + JPEG encoding.
    var frameProcessor: FrameProcessor { get }

    /// The AI client for API calls.
    var aiClient: AIClientProtocol { get }

    /// The ViewModel driving the UX state machine.
    var viewModel: StateMachineViewModel { get }

    /// Start a screen capture flow.
    /// - Parameters:
    ///   - mode: The capture mode (window, region, full-screen).
    ///   - apiKey: The AI provider's API key.
    ///   - provider: Which AI provider to use.
    func startCapture(mode: CaptureMode, apiKey: String, provider: AIProvider) async

    /// Stop the current capture flow.
    func stopCapture()
}

// MARK: - Errors

/// Errors thrown by the Glance pipeline.
enum GlancePipelineError: LocalizedError, Equatable {
    /// Screen recording permission denied.
    case permissionDenied
    /// No display available for capture.
    case noDisplayAvailable
    /// Capture engine is already running.
    case alreadyCapturing
    /// AI client failed.
    case aiClientError(String)
    /// Frame processing failed.
    case frameProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission denied. Grant access in System Preferences > Privacy & Security > Screen Recording."
        case .noDisplayAvailable:
            return "No display available for capture."
        case .alreadyCapturing:
            return "A capture flow is already in progress."
        case .aiClientError(let msg):
            return "AI error: \(msg)"
        case .frameProcessingFailed(let msg):
            return "Frame processing error: \(msg)"
        }
    }
}

// MARK: - Configuration

/// Configuration for the Glance pipeline.
struct GlancePipelineConfig {
    /// Capture frames per second (1–60, default 10 per research).
    let captureFPS: Int

    /// JPEG quality 0–100 (default 80 per RESEARCH.md).
    let jpegQuality: Float

    /// Maximum output dimensions (default 1920×1080 per research).
    let targetSize: CGSize

    /// How long to wait after AI response before auto-dismiss (seconds).
    let responseDismissTimeout: TimeInterval

    /// Default configuration matching research recommendations.
    static let `default` = GlancePipelineConfig(
        captureFPS: 10,
        jpegQuality: 80.0,
        targetSize: CGSize(width: 1920, height: 1080),
        responseDismissTimeout: 30.0
    )
}

// MARK: - Implementation

/// Concrete pipeline orchestrator.
///
/// Thread safety: capture callbacks arrive on SCK's queue, processing
/// happens on a dedicated serial queue, UI updates are dispatched to main.
@available(macOS 14.0, *)
final class GlancePipeline: NSObject, GlancePipelineProtocol {

    // MARK: - Public Properties

    let captureEngine: CaptureEngineProtocol
    let frameProcessor: FrameProcessor
    let aiClient: AIClientProtocol
    let viewModel: StateMachineViewModel

    // MARK: - Configuration

    private let config: GlancePipelineConfig

    // MARK: - Private State

    /// Serial queue for frame processing (avoids blocking SCK).
    private let processingQueue = DispatchQueue(
        label: "com.glance.pipeline.processing",
        qos: .userInteractive
    )

    /// Whether a capture flow is active.
    private var isActive = false

    /// Lock for isActive.
    private let stateLock = NSLock()

    /// Combine cancellables for state observation subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Current AI provider API key (not persisted here — from Keychain).
    private var currentAPIKey: String?
    private var currentProvider: AIProvider?

    // MARK: - Initialization

    /// Creates a Glance pipeline.
    /// - Parameters:
    ///   - captureEngine: Screen capture engine (default: real CaptureEngine).
    ///   - frameProcessor: Metal frame processor (default: real FrameProcessor).
    ///   - aiClient: AI HTTP client (default: real AIClient).
    ///   - viewModel: UX state machine wrapper.
    ///   - config: Pipeline configuration.
    init(
        captureEngine: CaptureEngineProtocol = CaptureEngine(),
        frameProcessor: FrameProcessor = FrameProcessor(),
        aiClient: AIClientProtocol = AIClient(),
        viewModel: StateMachineViewModel = StateMachineViewModel(),
        config: GlancePipelineConfig = .default
    ) {
        self.captureEngine = captureEngine
        self.frameProcessor = frameProcessor
        self.aiClient = aiClient
        self.viewModel = viewModel
        self.config = config
        super.init()

        // Wire capture engine delegate.
        captureEngine.delegate = self
    }

    // MARK: - Public API

    func startCapture(mode: CaptureMode, apiKey: String, provider: AIProvider) async {
        stateLock.lock()
        guard !isActive else {
            stateLock.unlock()
            return
        }
        isActive = true
        stateLock.unlock()

        currentAPIKey = apiKey
        currentProvider = provider

        // Begin UX flow.
        await MainActor.run {
            viewModel.startCaptureFlow(mode: mode)
        }

        // Check permission.
        guard captureEngine.canCapture() else {
            await handleError(GlancePipelineError.permissionDenied)
            return
        }

        // List shareable content and start capture.
        do {
            let content = try await captureEngine.listShareableContent()

            guard let display = content.displays.first else {
                await handleError(GlancePipelineError.noDisplayAvailable)
                return
            }

            // Create SCContentFilter for the primary display.
            let filter: SCContentFilter
            if let scDisplay = display as? SCDisplay {
                filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            } else {
                // SCK always provides SCDisplay on real hardware.
                // If this branch executes (e.g., mock in test), the capture
                // would fail — propagate as a structured error.
                throw GlancePipelineError.noDisplayAvailable
            }

            captureEngine.startCapture(filter: filter, fps: config.captureFPS)

        } catch {
            await handleError(error)
        }
    }

    func stopCapture() {
        captureEngine.stopCapture()
        stateLock.lock()
        isActive = false
        stateLock.unlock()

        Task { @MainActor in
            viewModel.reset()
        }
    }

    // MARK: - Frame Processing

    /// Process a captured frame: Metal preprocessing → JPEG → AI → display.
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let apiKey = currentAPIKey, let provider = currentProvider else {
            return
        }

        // Capture the values needed for async work outside the pipeline.
        let jpegQuality = config.jpegQuality
        let targetSize = config.targetSize
        let client = aiClient
        let vm = viewModel

        processingQueue.async {
            do {
                // Step 1: Metal preprocessing + JPEG encoding.
                let result = try self.frameProcessor.process(
                    frame: pixelBuffer,
                    targetSize: targetSize,
                    quality: jpegQuality
                )

                // Step 2: Update ViewModel with captured image.
                Task { @MainActor in
                    vm.capturedImageData = result.jpegData
                    vm.completeCapture()
                    // After preview (auto or manual), confirm send.
                    // The ViewModel handles the timer — we observe the state change.
                }

                // Step 3: Wait for THINKING transition via Combine.
                // Replaces fragile Task.sleep (which could race with user
                // cancel during preview) with proper state observation.
                // If state transitions to .idle (user cancelled), abort
                // without sending data to the AI.
                let newState = await withCheckedContinuation { continuation in
                    var sub: AnyCancellable?
                    sub = vm.$state
                        .sink { state in
                            if state == .thinking || state == .idle {
                                continuation.resume(returning: state)
                                sub?.cancel()
                            }
                        }
                }

                // If the user cancelled during preview, don't proceed.
                guard newState == .thinking else { return }

                // Step 4: Send to AI.
                let response = try await client.analyze(
                    image: result.jpegData,
                    provider: provider,
                    apiKey: apiKey,
                    question: await MainActor.run { vm.userQuestion }
                )

                // Step 5: Display response.
                Task { @MainActor in
                    vm.receiveResponse(text: response)
                }

            } catch let error as AIClientError {
                Task { @MainActor in
                    vm.receiveError(message: error.localizedDescription)
                }
            } catch let error as FrameProcessorError {
                Task { @MainActor in
                    vm.receiveError(message: "Frame processing: \(error.localizedDescription)")
                }
            } catch {
                Task { @MainActor in
                    vm.receiveError(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) async {
        stateLock.lock()
        isActive = false
        stateLock.unlock()

        let message: String
        if let pipelineError = error as? GlancePipelineError {
            // Use structured error descriptions for known pipeline errors.
            message = pipelineError.errorDescription ?? "Pipeline error"
        } else {
            message = error.localizedDescription
        }

        await MainActor.run {
            // Only .thinking state accepts .aiError transition.
            // For errors before AI processing (permission, display, etc.),
            // reset to idle to avoid stuck state machine.
            if viewModel.state == .thinking {
                viewModel.receiveError(message: message)
            } else {
                viewModel.errorMessage = message
                viewModel.reset()
            }
        }
    }
}

// MARK: - CaptureEngineDelegate

extension GlancePipeline: CaptureEngineDelegate {
    func captureEngine(_ engine: CaptureEngineProtocol,
                       didReceiveFrame buffer: CVPixelBuffer,
                       metadata: FrameMetadata) {
        processFrame(buffer)
    }

    func captureEngineDidStop(_ engine: CaptureEngineProtocol) {
        stateLock.lock()
        isActive = false
        stateLock.unlock()
    }

    func captureEngine(_ engine: CaptureEngineProtocol,
                       didEncounterError error: Error) {
        Task {
            await handleError(error)
        }
    }
}
