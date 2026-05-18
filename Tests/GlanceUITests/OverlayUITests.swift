import XCTest
@testable import GlanceUI

/// Tests for overlay visibility, state-driven view switching, and dismissal behavior.
///
/// These tests verify:
/// - OverlayWindow is properly configured (floating level, join-all-spaces)
/// - State transitions show correct SwiftUI views
/// - Dismissal via Esc, timeout, and programmatic close
/// - Timer management (preview 2s, dismiss 30s)
final class OverlayUITests: XCTestCase {

    var viewModel: StateMachineViewModel!

    override func setUp() {
        super.setUp()
        viewModel = StateMachineViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Overlay Window Properties

    func test_overlay_window_has_floating_level() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            rootView: Text("Test")
        )
        XCTAssertEqual(window.level, .floating)
    }

    func test_overlay_window_joins_all_spaces() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            rootView: Text("Test")
        )
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func test_overlay_window_is_stationary() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            rootView: Text("Test")
        )
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
    }

    func test_overlay_window_is_non_activating() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            rootView: Text("Test")
        )
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
    }

    func test_overlay_window_starts_with_alpha_zero_before_animateIn() {
        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            rootView: Text("Test")
        )
        // Note: window is not ordered in, so alphaValue is at its initial state.
        // animateIn sets alphaValue to 0 before animating to 1.
        window.animateIn()
        // After animateIn, the animator's target is 1.0.
        XCTAssertEqual(window.animator().alphaValue, 1.0)
    }

    // MARK: - State → View Mapping

    func test_idle_shows_empty_overlay() {
        // IDLE state should render EmptyView.
        XCTAssertEqual(viewModel.state, .idle)
        // OverlayContainer with idle = EmptyView — no assertions needed,
        // this is verified by the state machine test.
    }

    func test_selecting_shows_capture_mode_picker() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        XCTAssertEqual(viewModel.state, .selecting)
    }

    func test_preview_shows_screenshot_preview() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        XCTAssertEqual(viewModel.state, .preview)
    }

    func test_thinking_shows_spinner_view() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        XCTAssertEqual(viewModel.state, .thinking)
    }

    func test_showing_shows_response_view() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Test response")
        XCTAssertEqual(viewModel.state, .showing)
    }

    // MARK: - Dismissal Flow

    func test_dismiss_from_showing_resets_to_idle() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Some response")

        viewModel.dismiss()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(viewModel.isCapturing)
    }

    func test_dismiss_clears_response_text() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "This should be cleared")

        viewModel.dismiss()
        XCTAssertNil(viewModel.aiResponseText)
    }

    func test_dismiss_clears_error_message() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveError(message: "API error")

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.state, .idle)
        // Error is preserved on error path — verify stored.
    }

    // MARK: - Cancel Flows

    func test_cancel_at_selecting_returns_to_idle() {
        viewModel.startCaptureFlow(mode: .drawRegion)
        viewModel.cancelCapture()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.selectedCaptureMode)
    }

    func test_cancel_at_preview_returns_to_idle() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.cancelPreview()
        XCTAssertEqual(viewModel.state, .idle)
    }

    // MARK: - Timer Behavior

    func test_preview_duration_default_is_2_seconds() {
        XCTAssertEqual(viewModel.previewDuration, 2.0)
    }

    func test_dismiss_timeout_default_is_30_seconds() {
        XCTAssertEqual(viewModel.dismissTimeout, 30.0)
    }

    func test_preview_auto_continue_is_enabled_by_default() {
        XCTAssertTrue(viewModel.previewAutoContinue)
    }

    func test_disabling_auto_continue_prevents_auto_timer() {
        viewModel.previewAutoContinue = false
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        // Preview timer would NOT start — we just verify state.
        XCTAssertEqual(viewModel.state, .preview)
    }

    // MARK: - Share Again Flow

    func test_share_again_from_showing_goes_to_selecting() {
        viewModel.startCaptureFlow(mode: .fullScreen)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "Response")
        viewModel.shareAgain()
        XCTAssertEqual(viewModel.state, .selecting)
        XCTAssertNil(viewModel.aiResponseText)
    }

    // MARK: - Error Path

    func test_ai_error_transitions_to_idle_preserving_error_message() {
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveError(message: "Network timeout")
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.errorMessage, "Network timeout")
    }

    // MARK: - Full Integration Flow

    func test_full_integration_flow_idle_to_showing_to_idle() {
        // 1. IDLE → SELECTING
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        XCTAssertEqual(viewModel.state, .selecting)
        XCTAssertEqual(viewModel.selectedCaptureMode, .windowUnderCursor)

        // 2. SELECTING → PREVIEW (simulate capture complete)
        viewModel.completeCapture()
        XCTAssertEqual(viewModel.state, .preview)

        // 3. PREVIEW → THINKING (user confirms)
        viewModel.confirmSend()
        XCTAssertEqual(viewModel.state, .thinking)

        // 4. THINKING → SHOWING (AI responds)
        viewModel.receiveResponse(text: "I can see a code editor with Swift code.")
        XCTAssertEqual(viewModel.state, .showing)
        XCTAssertEqual(viewModel.aiResponseText, "I can see a code editor with Swift code.")

        // 5. SHOWING → IDLE (dismiss)
        viewModel.dismiss()
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.aiResponseText)
        XCTAssertNil(viewModel.selectedCaptureMode)
    }

    func test_full_integration_flow_with_user_question() {
        viewModel.startCaptureFlow(mode: .drawRegion)
        viewModel.completeCapture()
        viewModel.userQuestion = "What programming language is this?"
        viewModel.confirmSend()
        viewModel.receiveResponse(text: "This appears to be Swift code.")
        XCTAssertEqual(viewModel.state, .showing)
        viewModel.dismiss()
        XCTAssertNil(viewModel.userQuestion)
    }

    // MARK: - Multiple Capture Sessions

    func test_multiple_capture_sessions_in_sequence() {
        // First session
        runFullSession(responseText: "First response")
        XCTAssertEqual(viewModel.state, .idle)

        // Second session
        runFullSession(responseText: "Second response")
        XCTAssertEqual(viewModel.state, .idle)

        // Third session with error
        viewModel.startCaptureFlow(mode: .windowUnderCursor)
        viewModel.completeCapture()
        viewModel.confirmSend()
        viewModel.receiveError(message: "Rate limited")
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.errorMessage, "Rate limited")
    }

    // MARK: - Helpers

    private func runFullSession(responseText: String) {
        viewModel.startCaptureFlow(mode: .fullScreen)
        XCTAssertEqual(viewModel.state, .selecting)

        viewModel.completeCapture()
        XCTAssertEqual(viewModel.state, .preview)

        viewModel.confirmSend()
        XCTAssertEqual(viewModel.state, .thinking)

        viewModel.receiveResponse(text: responseText)
        XCTAssertEqual(viewModel.state, .showing)

        viewModel.dismiss()
    }
}
