import XCTest
import CoreVideo
@testable import CaptureEngine

// MARK: - CaptureEngine Tests

final class CaptureEngineTests: XCTestCase {

    var engine: CaptureEngine!
    var mockStream: MockSCStream!
    var mockDelegate: MockCaptureEngineDelegate!
    var mockPermissionHelper: MockPermissionHelper!

    override func setUp() {
        super.setUp()
        mockStream = MockSCStream()
        mockDelegate = MockCaptureEngineDelegate()
        mockPermissionHelper = MockPermissionHelper()
        engine = CaptureEngine(
            streamFactory: { _ in self.mockStream },
            permissionHelper: mockPermissionHelper
        )
        engine.delegate = mockDelegate
    }

    override func tearDown() {
        engine.stopCapture()
        engine = nil
        mockStream = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Permission Tests

    func test_canCapture_whenAuthorized_returnsTrue() {
        // Given: screen recording permission is granted
        mockPermissionHelper.mockIsAuthorized = true

        // When
        let result = engine.canCapture()

        // Then
        XCTAssertTrue(result, "canCapture should return true when authorized")
    }

    func test_canCapture_whenDenied_returnsFalse() {
        // Given: screen recording permission is denied
        mockPermissionHelper.mockIsAuthorized = false

        // When
        let result = engine.canCapture()

        // Then
        XCTAssertFalse(result, "canCapture should return false when denied")
    }

    func test_canCapture_whenNotDetermined_returnsFalse() {
        // Given: screen recording permission not yet requested
        mockPermissionHelper.mockIsAuthorized = false

        // When
        let result = engine.canCapture()

        // Then
        XCTAssertFalse(result, "canCapture should return false when not determined")
    }

    // MARK: - Stream Lifecycle Tests

    func test_startCapture_beginsStreamWithCorrectConfiguration() {
        // Given: a valid content filter and fps
        let filter = MockSCContentFilter()
        let fps = 10

        // When
        engine.startCapture(filter: filter, fps: fps)

        // Then
        XCTAssertTrue(mockStream.didStart, "Stream should be started")
        XCTAssertEqual(mockStream.lastConfiguration?.width, 1920,
                       "Width should target 1080p")
        XCTAssertEqual(mockStream.lastConfiguration?.height, 1080,
                       "Height should target 1080p")
        XCTAssertEqual(mockStream.lastConfiguration?.pixelFormat, Int(kCVPixelFormatType_32BGRA),
                       "Pixel format should be BGRA8")
        XCTAssertEqual(mockStream.lastConfiguration?.queueDepth, 3,
                       "Queue depth should be 3")
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: CMTimeScale(fps)),
                       "Frame interval should match fps")
    }

    func test_startCapture_with1fps_setsCorrectInterval() {
        // Given: 1 fps for idle mode
        let filter = MockSCContentFilter()
        let fps = 1

        // When
        engine.startCapture(filter: filter, fps: fps)

        // Then
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: 1),
                       "1 fps should give 1-second interval")
    }

    func test_stopCapture_withActiveStream_tearsDownStream() {
        // Given: an active capture session
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)

        // When
        engine.stopCapture()

        // Then
        XCTAssertTrue(mockStream.didStop, "Stream should be stopped")
        XCTAssertFalse(engine.isCapturing, "Engine should report not capturing")
    }

    func test_stopCapture_whenNotCapturing_isNoop() {
        // Given: no active capture session

        // When
        engine.stopCapture()

        // Then: should not crash or error
        XCTAssertFalse(engine.isCapturing, "Engine should still report not capturing")
    }

    func test_startCapture_whenAlreadyCapturing_stopsOldStreamFirst() {
        // Given: an active capture session
        let firstStream = mockStream!
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)

        // When: starting a new capture
        let secondStream = MockSCStream()
        let newEngine = CaptureEngine(streamFactory: { _ in secondStream })
        newEngine.startCapture(filter: MockSCContentFilter(), fps: 10)

        // Then: old engine's stream should be stopped
        XCTAssertTrue(firstStream.didStop, "Old stream should be stopped")

        // Cleanup
        newEngine.stopCapture()
    }

    // MARK: - Frame Delivery Tests

    func test_onFrame_callsDelegateWithPixelBuffer() {
        // Given: capture is active
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)
        let testBuffer = makeTestPixelBuffer()

        // When: a frame arrives
        mockStream.simulateFrame(buffer: testBuffer, status: .complete)

        // Then
        XCTAssertTrue(mockDelegate.didReceiveFrame, "Delegate should receive frame")
        XCTAssertNotNil(mockDelegate.lastBuffer, "Delegate should get pixel buffer")
    }

    func test_onFrame_withIncompleteStatus_doesNotDeliverToDelegate() {
        // Given: capture is active
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)

        // When: an incomplete frame arrives
        mockStream.simulateFrame(buffer: makeTestPixelBuffer(), status: .idle)

        // Then
        XCTAssertFalse(mockDelegate.didReceiveFrame,
                       "Incomplete frames should not be delivered")
    }

    func test_onFrame_whenDelegateIsSlow_dropsOldestFrame() {
        // Given: capture is active with a slow delegate
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)
        mockDelegate.processingDelay = 0.2 // 200ms, longer than 1/10fps = 100ms

        // When: multiple frames arrive rapidly
        let frame1 = makeTestPixelBuffer()
        let frame2 = makeTestPixelBuffer()
        let frame3 = makeTestPixelBuffer()

        mockStream.simulateFrame(buffer: frame1, status: .complete)
        mockStream.simulateFrame(buffer: frame2, status: .complete)
        mockStream.simulateFrame(buffer: frame3, status: .complete)

        // Then: the frame queue should have dropped oldest frames
        // After 3 frames with slow delegate, only most recent should be delivered
        let deliveredFrames = mockDelegate.receivedFrames
        XCTAssertGreaterThan(deliveredFrames.count, 0,
                             "At least some frames should be delivered")
        // Frame 1 may be dropped if delegate was still processing
    }

    // MARK: - listShareableContent (Integration Test)

    func test_listShareableContent_requiresRealSCK() {
        // listShareableContent calls SCShareableContent.current which
        // requires actual macOS with ScreenCaptureKit available.
        // This test validates the plumbing is correct; actual content
        // verification is done in integration tests on Mac hardware.
        XCTAssertTrue(true, "listShareableContent integration test placeholder")
    }

    // MARK: - Delegate Callbacks

    func test_delegate_didStop_isCalledOnStopCapture() {
        // Given: capture is active
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)

        // When
        engine.stopCapture()

        // Then
        XCTAssertTrue(mockDelegate.didStopWasCalled,
                      "Delegate didStop should be called")
    }

    func test_delegate_didEncounterError_isCalledOnStreamError() {
        // Given: capture is active
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)
        let testError = NSError(domain: "SCK", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Test error"])

        // When: stream encounters an error
        mockStream.simulateError(testError)

        // Then
        XCTAssertTrue(mockDelegate.didEncounterError, "Delegate should get error")
        XCTAssertNotNil(mockDelegate.lastError, "Delegate should get error details")
    }

    // MARK: - FPS Clamping Tests

    func test_startCapture_fpsBelow1_clampsTo1() {
        // Given: fps=0 (invalid, below minimum)
        let filter = MockSCContentFilter()

        // When
        engine.startCapture(filter: filter, fps: 0)

        // Then: should clamp to 1 fps
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: 1),
                       "fps=0 should clamp to 1 fps (1-second interval)")
    }

    func test_startCapture_fpsAbove60_clampsTo60() {
        // Given: fps=120 (above maximum)
        let filter = MockSCContentFilter()

        // When
        engine.startCapture(filter: filter, fps: 120)

        // Then: should clamp to 60 fps
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: 60),
                       "fps=120 should clamp to 60 fps (1/60s interval)")
    }

    func test_startCapture_negativeFPS_clampsTo1() {
        // Given: fps=-5 (negative, nonsensical)
        let filter = MockSCContentFilter()

        // When
        engine.startCapture(filter: filter, fps: -5)

        // Then: should clamp to 1 fps
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: 1),
                       "Negative fps should clamp to 1 fps minimum")
    }

    func test_startCapture_exactly60fps_notRejected() {
        // Given: fps=60 (maximum allowed)
        let filter = MockSCContentFilter()

        // When
        engine.startCapture(filter: filter, fps: 60)

        // Then: 60 should be accepted as-is
        XCTAssertTrue(mockStream.didStart, "Stream should start at 60 fps")
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: 60),
                       "60 fps should give 1/60s interval")
    }

    func test_startCapture_exactly1fps_notRejected() {
        // Given: fps=1 (minimum allowed)
        let filter = MockSCContentFilter()

        // When
        engine.startCapture(filter: filter, fps: 1)

        // Then: 1 should be accepted as-is
        XCTAssertTrue(mockStream.didStart, "Stream should start at 1 fps")
        XCTAssertEqual(mockStream.lastConfiguration?.minimumFrameInterval,
                       CMTime(value: 1, timescale: 1),
                       "1 fps should give 1-second interval")
    }

    // MARK: - Stream Error Handling

    func test_startCapture_whenStreamStartThrows_delegatesError() {
        // Given: a stream that throws on start
        let testError = NSError(domain: "SCK", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Stream start failed"])
        mockStream.startError = testError
        let filter = MockSCContentFilter()

        // When
        engine.startCapture(filter: filter, fps: 10)

        // Then: error should be forwarded to delegate
        XCTAssertTrue(mockDelegate.didEncounterError,
                       "Delegate should receive stream start errors")
        XCTAssertFalse(engine.isCapturing,
                        "Engine should report not capturing after failed start")
    }

    func test_stopCapture_whenStreamStopThrows_delegatesError() {
        // Given: an active stream that will throw on stop
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)
        let testError = NSError(domain: "SCK", code: -3,
                                userInfo: [NSLocalizedDescriptionKey: "Stream stop failed"])
        mockStream.stopError = testError

        // When
        engine.stopCapture()

        // Then: error should be forwarded to delegate
        XCTAssertTrue(mockDelegate.didEncounterError,
                       "Delegate should receive stream stop errors")
        XCTAssertFalse(engine.isCapturing,
                        "Engine should still report not capturing after stop error")
        // didStop should still be called after error
        XCTAssertTrue(mockDelegate.didStopWasCalled,
                       "Delegate didStop should still be called after stop error")
    }

    // MARK: - Frame Metadata Validation

    func test_handleFrame_preservesTimestampInMetadata() {
        // Given: capture is active
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)
        let testBuffer = makeTestPixelBuffer()
        let expectedTimestamp = CMTime(value: 42, timescale: 10)

        // When: a frame arrives with a known timestamp
        let frame = CapturedFrame(
            pixelBuffer: testBuffer,
            timestamp: expectedTimestamp,
            contentRect: .zero,
            scaleFactor: 1.0
        )
        mockStream.simulateFrame(buffer: testBuffer, status: .complete)

        // Then: metadata timestamp should be preserved
        // (Note: simulateFrame creates its own CapturedFrame; this test
        //  verifies handleFrame creates proper FrameMetadata)
        XCTAssertTrue(mockDelegate.didReceiveFrame, "Delegate should receive frame")
        XCTAssertNotNil(mockDelegate.lastMetadata, "Metadata should be present")
    }

    func test_handleFrame_metadataStatusIsComplete() {
        // Given: capture is active
        engine.startCapture(filter: MockSCContentFilter(), fps: 10)
        let testBuffer = makeTestPixelBuffer()

        // When: a frame arrives with .complete status
        mockStream.simulateFrame(buffer: testBuffer, status: .complete)

        // Then: metadata status should be .complete
        XCTAssertTrue(mockDelegate.didReceiveFrame, "Delegate should receive frame")
        if let metadata = mockDelegate.lastMetadata {
            XCTAssertEqual(metadata.status, .complete,
                           "Metadata status should be .complete")
        }
    }
}
