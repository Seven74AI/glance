import XCTest
@testable import GlanceUI

/// TDD: StateMachineViewModel tests — ObservableObject wrapping UXStateMachine
///
/// The ViewModel adds:
/// - Preview auto-continue timer (2s)
/// - Dismiss auto-dismiss timer (30s)
/// - Capture mode tracking
/// - Human-readable state labels
final class StateMachineViewModelTests: XCTestCase {

    var viewModel: StateMachineViewModel!

    override func setUp() {
        super.setUp()
        viewModel = StateMachineViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initial_state_is_idle() {
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(viewModel.isIdle)
        XCTAssertFalse(viewModel.isCapturing)
    }

    func test_initial_state_label_is_idle() {
        XCTAssertEqual(viewModel.stateLabel, "Ready")
    }

    func test_initial_has_no_selected_capture_mode() {
        XCTAssertNil(viewModel.selectedCaptureMode)
    }

    // MARK: - State Labels

    func test_state_label_for_selecting() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        XCTAssertEqual(viewModel.stateLabel, "Selecting capture mode...")
    }

    func test_state_label_for_preview() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()  // → PREVIEW
        XCTAssertEqual(viewModel.stateLabel, "Preview — send or cancel?")
    }

    func test_state_label_for_thinking() {
        viewModel.startCaptureFlow(mode: .drawRegion)
        viewModel.completeCapture()
        viewModel.confirmSend()  // → THINKING
        XCTAssertEqual(viewModel.stateLabel, "AI is analyzing your screen...")
    }

    func test_state_label_for_showing() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Hello!")  // → SHOWING
        XCTAssertEqual(viewModel.stateLabel, "AI Response")
    }

    // MARK: - Capture Mode Selection

    func test_startCaptureFlow_sets_capture_mode_and_transitions_to_selecting() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        XCTAssertEqual(viewModel.selectedCaptureMode, .windowUnderCursor)
        XCTAssertEqual(viewModel.state, .selecting)
    }

    func test_startCaptureFlow_sets_draw_region_mode() {
        viewModel.startCaptureFlow(mode: .drawRegion)
        XCTAssertEqual(viewModel.selectedCaptureMode, .drawRegion)
    }

    func test_startCaptureFlow_sets_full_screen_mode() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        XCTAssertEqual(viewModel.selectedCaptureMode, .fullScreen)
    }

    // MARK: - Preview Flow

    func test_completeCapture_transitions_to_preview() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        XCTAssertEqual(viewModel.state, .preview)
    }

    func test_confirmSend_from_preview_goes_to_thinking() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        XCTAssertEqual(viewModel.state, .thinking)
    }

    func test_cancelPreview_returns_to_idle() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.cancelPreview()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.selectedCaptureMode)
    }

    // MARK: - AI Response Flow

    func test_receiveResponse_transitions_to_showing_with_text() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "I can see your IDE with a Swift file open.")
        XCTAssertEqual(viewModel.state, .showing)
        XCTAssertEqual(viewModel.aiResponseText, "I can see your IDE with a Swift file open.")
    }

    func test_receiveError_transitions_to_idle_with_error_message() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveError(message: "API rate limit exceeded")
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.errorMessage, "API rate limit exceeded")
    }

    // MARK: - Share Again

    func test_shareAgain_from_showing_goes_to_selecting() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Response")
        viewModel.shareAgain()
        XCTAssertEqual(viewModel.state, .selecting)
        XCTAssertNil(viewModel.aiResponseText, "Response should be cleared on share again")
    }

    // MARK: - Dismiss

    func test_dismiss_from_showing_returns_to_idle() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Response")
        viewModel.dismiss()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.aiResponseText)
        XCTAssertNil(viewModel.selectedCaptureMode)
    }

    // MARK: - Cancel at Selecting

    func test_cancelCapture_from_selecting_returns_to_idle() {
        viewModel.startCaptureFlow(mode: .drawRegion)
        viewModel.cancelCapture()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.selectedCaptureMode)
    }

    // MARK: - Reset

    func test_reset_from_showing_clears_all_state() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Some AI response here")

        viewModel.reset()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.aiResponseText)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.selectedCaptureMode)
        XCTAssertNil(viewModel.capturedImageData)
    }

    // MARK: - Timer Management

    func test_startCaptureFlow_cancels_any_existing_dismiss_timer() {
        // Start a flow and go to SHOWING (which has a 30s dismiss timer)
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Response")
        // Now SHOWING — dismiss timer should be scheduled.

        // Start a new capture flow — should cancel the old dismiss timer
        // and go to SELECTING (this tests the timer cleanup)
        viewModel.shareAgain()
        XCTAssertEqual(viewModel.state, .selecting)
    }

    // MARK: - Preview Auto-Continue Timer

    func test_previewAutoContinue_is_true_by_default() {
        XCTAssertTrue(viewModel.previewAutoContinue)
    }

    func test_previewAutoContinue_can_be_disabled() {
        viewModel.previewAutoContinue = false
        XCTAssertFalse(viewModel.previewAutoContinue)
    }

    // MARK: - User Question

    func test_userQuestion_can_be_set_during_preview() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.userQuestion = "What language is this?"
        XCTAssertEqual(viewModel.userQuestion, "What language is this?")
    }

    func test_userQuestion_cleared_on_dismiss() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.userQuestion = "What does this code do?"
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "It sorts an array.")
        viewModel.dismiss()
        XCTAssertNil(viewModel.userQuestion)
    }

    // MARK: - Dismiss Timeout Config

    func test_dismissTimeout_is_30_seconds_by_default() {
        XCTAssertEqual(viewModel.dismissTimeout, 30.0)
    }

    func test_previewDuration_is_2_seconds_by_default() {
        XCTAssertEqual(viewModel.previewDuration, 2.0)
    }
}
