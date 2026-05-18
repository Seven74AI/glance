import XCTest
import CoreVideo
import CoreMedia
import ScreenCaptureKit
@testable import GlanceApp
import CaptureEngine
import FrameProcessor
import GlanceUI

/// TDD: GlancePipeline integration tests.
///
/// Tests the full pipeline orchestration with mock dependencies:
/// - MockCaptureEngine for screen capture
/// - MockAIClient for AI API calls
/// - Real FrameProcessor (Metal available on test runner)
/// - Real StateMachineViewModel for UX state transitions
@available(macOS 14.0, *)
final class GlancePipelineTests: XCTestCase {

    // MARK: - Properties

    private var mockCaptureEngine: MockCaptureEngine!
    private var mockAIClient: MockAIClient!
    private var viewModel: StateMachineViewModel!
    private var pipeline: GlancePipeline!

    // MARK: - Setup / Teardown

    @MainActor
    override func setUp() {
        super.setUp()
        mockCaptureEngine = MockCaptureEngine()
        mockAIClient = MockAIClient()
        viewModel = StateMachineViewModel()
        pipeline = GlancePipeline(
            captureEngine: mockCaptureEngine,
            aiClient: mockAIClient,
            viewModel: viewModel
        )
    }

    override func tearDown() {
        pipeline = nil
        viewModel = nil
        mockAIClient = nil
        mockCaptureEngine = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func test_pipeline_initialState_isIdle() {
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.isIdle)
        XCTAssertNil(viewModel.capturedImageData)
        XCTAssertNil(viewModel.aiResponseText)
    }

    func test_pipeline_wiresCaptureEngineDelegate() {
        XCTAssertTrue(mockCaptureEngine.delegate === pipeline,
                       "Pipeline should be the capture engine delegate")
    }

    // MARK: - Permission Denied

    @MainActor
    func test_startCapture_withoutPermission_reportsError() async {
        mockCaptureEngine.canCaptureResult = false

        await pipeline.startCapture(
            mode: .fullScreen,
            apiKey: "sk-test",
            provider: .claude
        )

        // Wait for async error handling.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(
            viewModel.errorMessage?.contains("permission") ?? false,
            "Error should mention permission"
        )
    }

    // MARK: - Successful Capture Flow

    @MainActor
    func test_startCapture_withPermission_startsUXFlow() async {
        mockCaptureEngine.canCaptureResult = true

        await pipeline.startCapture(
            mode: .fullScreen,
            apiKey: "sk-test",
            provider: .claude
        )

        // The pipeline should have started the UX flow.
        // State should be .selecting at this point.
        XCTAssertEqual(viewModel.state, .selecting,
                       "Should transition to SELECTING on capture start")
    }

    // MARK: - Frame Processing → AI Pipeline

    @MainActor
    func test_frameArrival_triggersProcessingAndAIResponse() async throws {
        // Setup: successful capture
        mockCaptureEngine.canCaptureResult = true

        // Stub AI response.
        mockAIClient.stubResponse = "This screen shows Finder with a Documents folder open."

        await pipeline.startCapture(
            mode: .fullScreen,
            apiKey: "sk-test",
            provider: .claude
        )

        XCTAssertEqual(viewModel.state, .selecting)

        // Simulate first frame arriving from ScreenCaptureKit.
        // Create a 1×1 test pixel buffer (valid BGRA8).
        let pixelBuffer = try createTestPixelBuffer(width: 1920, height: 1080)
        let metadata = FrameMetadata(
            timestamp: CMTime(value: 1, timescale: 10),
            contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scaleFactor: 2.0,
            status: .complete
        )

        mockCaptureEngine.simulateFrame(buffer: pixelBuffer, metadata: metadata)

        // Give the processing queue time to work.
        try? await Task.sleep(nanoseconds: 200_000_000)

        // After frame arrives, it should transition to PREVIEW.
        XCTAssertEqual(viewModel.state, .preview,
                       "Should transition to PREVIEW after frame arrives")

        // The captured image data should be populated.
        XCTAssertNotNil(viewModel.capturedImageData,
                        "Captured image should be available in preview")

        // Confirm send (simulate the preview auto-continue).
        viewModel.confirmSend()
        XCTAssertEqual(viewModel.state, .thinking,
                       "Should transition to THINKING after confirm")

        // Wait for AI response to be processed.
        // The pipeline waits `previewDuration + 500ms` before sending to AI.
        try? await Task.sleep(nanoseconds: UInt64(viewModel.previewDuration * 1_000_000_000) + 1_000_000_000)

        // After AI responds, state should be .showing.
        XCTAssertEqual(viewModel.state, .showing,
                       "Should transition to SHOWING after AI response")
        XCTAssertEqual(viewModel.aiResponseText, mockAIClient.stubResponse)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - AI Error Handling

    @MainActor
    func test_aiError_transitionsToErrorState() async throws {
        mockCaptureEngine.canCaptureResult = true
        mockAIClient.stubError = AIClientError.httpError(statusCode: 503, body: "Service unavailable")

        await pipeline.startCapture(
            mode: .fullScreen,
            apiKey: "sk-test",
            provider: .claude
        )

        let pixelBuffer = try createTestPixelBuffer(width: 1920, height: 1080)
        let metadata = FrameMetadata()

        mockCaptureEngine.simulateFrame(buffer: pixelBuffer, metadata: metadata)

        try? await Task.sleep(nanoseconds: 200_000_000)

        // Confirm send.
        viewModel.confirmSend()
        XCTAssertEqual(viewModel.state, .thinking)

        // Wait for AI error processing.
        try? await Task.sleep(nanoseconds: UInt64(viewModel.previewDuration * 1_000_000_000) + 1_000_000_000)

        // After AI error, the state should reset to idle with error message.
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("503") ?? false)
    }

    // MARK: - Pipeline Stop

    @MainActor
    func test_stopCapture_resetsState() async {
        mockCaptureEngine.canCaptureResult = true

        await pipeline.startCapture(
            mode: .windowUnderCursor,
            apiKey: "sk-test",
            provider: .gemini
        )

        XCTAssertEqual(viewModel.state, .selecting)

        pipeline.stopCapture()

        // After stop, state should be idle.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(mockCaptureEngine.didStop)
    }

    // MARK: - Provider Routing

    @MainActor
    func test_usesCorrectAIProvider() async throws {
        mockCaptureEngine.canCaptureResult = true
        mockAIClient.stubResponse = "Response from Gemini"

        await pipeline.startCapture(
            mode: .fullScreen,
            apiKey: "gemini-key",
            provider: .gemini
        )

        let pixelBuffer = try createTestPixelBuffer(width: 1920, height: 1080)
        mockCaptureEngine.simulateFrame(buffer: pixelBuffer, metadata: FrameMetadata())

        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.confirmSend()

        try? await Task.sleep(nanoseconds: UInt64(viewModel.previewDuration * 1_000_000_000) + 1_000_000_000)

        // Verify the mock was called with Gemini.
        XCTAssertEqual(mockAIClient.lastProvider, .gemini)
        XCTAssertEqual(mockAIClient.lastAPIKey, "gemini-key")
        XCTAssertEqual(viewModel.aiResponseText, "Response from Gemini")
    }

    @MainActor
    func test_routesToOpenAI() async throws {
        mockCaptureEngine.canCaptureResult = true
        mockAIClient.stubResponse = "Response from OpenAI"

        await pipeline.startCapture(
            mode: .fullScreen,
            apiKey: "sk-openai",
            provider: .openAI
        )

        let pixelBuffer = try createTestPixelBuffer(width: 1920, height: 1080)
        mockCaptureEngine.simulateFrame(buffer: pixelBuffer, metadata: FrameMetadata())

        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.confirmSend()

        try? await Task.sleep(nanoseconds: UInt64(viewModel.previewDuration * 1_000_000_000) + 1_000_000_000)

        XCTAssertEqual(mockAIClient.lastProvider, .openAI)
        XCTAssertEqual(mockAIClient.lastAPIKey, "sk-openai")
    }

    // MARK: - Helper: Test Pixel Buffer

    /// Creates a CVPixelBuffer suitable for testing the frame processing pipeline.
    private func createTestPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "TestError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create test pixel buffer"])
        }

        // Lock and fill with test pattern (solid gray).
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<height {
                let rowPtr = baseAddress.advanced(by: row * bytesPerRow)
                memset(rowPtr, 128, bytesPerRow) // 50% gray
            }
        }

        return buffer
    }
}

// MARK: - MockCaptureEngine

/// Mock capture engine for integration testing.
/// Allows tests to simulate frame delivery without real ScreenCaptureKit.
final class MockCaptureEngine: CaptureEngineProtocol {
    weak var delegate: CaptureEngineDelegate?

    var isCapturing: Bool = false
    var didStop: Bool = false

    /// Whether canCapture() returns true.
    var canCaptureResult: Bool = true
    /// Whether listShareableContent throws.
    var listContentError: Error?

    func canCapture() -> Bool {
        return canCaptureResult
    }

    func listShareableContent() async throws -> ShareableContentProtocol {
        if let error = listContentError {
            throw error
        }
        return ShareableContent(
            displays: [MockDisplay()],
            applications: [],
            windows: []
        )
    }

    func startCapture(filter: SCContentFilterProtocol, fps: Int) {
        isCapturing = true
    }

    func stopCapture() {
        isCapturing = false
        didStop = true
        delegate?.captureEngineDidStop(self)
    }

    /// Simulate a frame arriving from the capture engine.
    func simulateFrame(buffer: CVPixelBuffer, metadata: FrameMetadata) {
        delegate?.captureEngine(self, didReceiveFrame: buffer, metadata: metadata)
    }

    /// Simulate a capture error.
    func simulateError(_ error: Error) {
        delegate?.captureEngine(self, didEncounterError: error)
    }
}

// MARK: - MockDisplay

struct MockDisplay: DisplayProtocol {
    let displayID: UInt32 = 1
    let width: Int = 1920
    let height: Int = 1080
}

// MARK: - MockAIClient

/// Mock AI client for integration testing.
/// Records calls and returns stubbed responses.
final class MockAIClient: AIClientProtocol {
    /// Stub response text to return.
    var stubResponse: String = "Mock AI response"
    /// Stub error to throw.
    var stubError: Error?

    /// Last provider used (for assertion).
    var lastProvider: AIProvider?
    /// Last API key used (for assertion).
    var lastAPIKey: String?
    /// Last question text (for assertion).
    var lastQuestion: String?
    /// Last image data (for assertion).
    var lastImage: Data?
    /// Number of times analyze was called.
    var callCount: Int = 0

    func analyze(
        image: Data,
        provider: AIProvider,
        apiKey: String,
        question: String?
    ) async throws -> String {
        lastProvider = provider
        lastAPIKey = apiKey
        lastQuestion = question
        lastImage = image
        callCount += 1

        if let error = stubError {
            throw error
        }
        return stubResponse
    }
}
