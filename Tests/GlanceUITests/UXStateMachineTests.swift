import XCTest
@testable import GlanceUI

/// TDD: UXStateMachine tests — 5-state machine per research-ux-design.md §3.4
///
/// States: IDLE → SELECTING → PREVIEW → THINKING → SHOWING → IDLE
///
/// These tests are written BEFORE implementation (RED phase).
/// They MUST fail because UXStateMachine doesn't exist yet.
final class UXStateMachineTests: XCTestCase {

    // MARK: - Initial State

    func test_initial_state_is_idle() {
        let machine = UXStateMachine()
        XCTAssertEqual(machine.currentState, .idle)
    }

    func test_idle_has_no_active_capture() {
        let machine = UXStateMachine()
        XCTAssertFalse(machine.isCapturing)
        XCTAssertTrue(machine.isIdle)
    }

    // MARK: - Valid Transitions: IDLE → SELECTING

    func test_startCapture_transitions_from_idle_to_selecting() {
        let machine = UXStateMachine()
        let result = machine.transition(.startCapture)
        XCTAssertTrue(result, "IDLE → SELECTING should succeed")
        XCTAssertEqual(machine.currentState, .selecting)
        XCTAssertTrue(machine.isCapturing)
    }

    // MARK: - Valid Transitions: SELECTING → PREVIEW

    func test_captureComplete_transitions_from_selecting_to_preview() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)  // IDLE → SELECTING
        let result = machine.transition(.captureComplete)
        XCTAssertTrue(result, "SELECTING → PREVIEW should succeed")
        XCTAssertEqual(machine.currentState, .preview)
    }

    // MARK: - Valid Transitions: SELECTING → IDLE (cancel)

    func test_cancelCapture_transitions_from_selecting_to_idle() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        let result = machine.transition(.cancelCapture)
        XCTAssertTrue(result, "SELECTING → IDLE should succeed")
        XCTAssertEqual(machine.currentState, .idle)
        XCTAssertFalse(machine.isCapturing)
    }

    // MARK: - Valid Transitions: PREVIEW → THINKING

    func test_confirmPreview_transitions_from_preview_to_thinking() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)  // IDLE → SELECTING → PREVIEW
        let result = machine.transition(.confirmSend)
        XCTAssertTrue(result, "PREVIEW → THINKING should succeed")
        XCTAssertEqual(machine.currentState, .thinking)
    }

    // MARK: - Valid Transitions: PREVIEW → IDLE (cancel)

    func test_cancelPreview_transitions_from_preview_to_idle() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        let result = machine.transition(.cancelPreview)
        XCTAssertTrue(result, "PREVIEW → IDLE should succeed")
        XCTAssertEqual(machine.currentState, .idle)
    }

    // MARK: - Valid Transitions: THINKING → SHOWING

    func test_responseReceived_transitions_from_thinking_to_showing() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        machine.transition(.confirmSend)  // IDLE → SELECTING → PREVIEW → THINKING
        let result = machine.transition(.responseReceived)
        XCTAssertTrue(result, "THINKING → SHOWING should succeed")
        XCTAssertEqual(machine.currentState, .showing)
    }

    // MARK: - Valid Transitions: THINKING → IDLE (error)

    func test_aiError_transitions_from_thinking_to_idle() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        machine.transition(.confirmSend)
        let result = machine.transition(.aiError)
        XCTAssertTrue(result, "THINKING → IDLE should succeed on error")
        XCTAssertEqual(machine.currentState, .idle)
    }

    // MARK: - Valid Transitions: SHOWING → SELECTING (share again)

    func test_shareAgain_transitions_from_showing_to_selecting() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        machine.transition(.confirmSend)
        machine.transition(.responseReceived)  // → SHOWING
        let result = machine.transition(.shareAgain)
        XCTAssertTrue(result, "SHOWING → SELECTING should succeed")
        XCTAssertEqual(machine.currentState, .selecting)
    }

    // MARK: - Valid Transitions: SHOWING → IDLE (dismiss)

    func test_dismiss_transitions_from_showing_to_idle() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        machine.transition(.confirmSend)
        machine.transition(.responseReceived)  // → SHOWING
        let result = machine.transition(.dismiss)
        XCTAssertTrue(result, "SHOWING → IDLE should succeed")
        XCTAssertEqual(machine.currentState, .idle)
    }

    // MARK: - Invalid Transitions (should be rejected)

    func test_captureComplete_from_idle_is_invalid() {
        let machine = UXStateMachine()
        let result = machine.transition(.captureComplete)
        XCTAssertFalse(result, "Cannot captureComplete from IDLE")
        XCTAssertEqual(machine.currentState, .idle, "State should not change on invalid transition")
    }

    func test_confirmSend_from_idle_is_invalid() {
        let machine = UXStateMachine()
        let result = machine.transition(.confirmSend)
        XCTAssertFalse(result, "Cannot confirmSend from IDLE")
        XCTAssertEqual(machine.currentState, .idle)
    }

    func test_responseReceived_from_idle_is_invalid() {
        let machine = UXStateMachine()
        let result = machine.transition(.responseReceived)
        XCTAssertFalse(result)
        XCTAssertEqual(machine.currentState, .idle)
    }

    func test_dismiss_from_idle_is_invalid() {
        let machine = UXStateMachine()
        let result = machine.transition(.dismiss)
        XCTAssertFalse(result)
        XCTAssertEqual(machine.currentState, .idle)
    }

    func test_dismiss_from_selecting_is_invalid() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)  // → SELECTING
        let result = machine.transition(.dismiss)
        XCTAssertFalse(result, "SELECTING should use cancelCapture, not dismiss")
        XCTAssertEqual(machine.currentState, .selecting)
    }

    func test_startCapture_from_selecting_is_invalid() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        let result = machine.transition(.startCapture)  // Already in SELECTING
        XCTAssertFalse(result, "Cannot startCapture while already selecting")
        XCTAssertEqual(machine.currentState, .selecting)
    }

    func test_startCapture_from_thinking_is_invalid() {
        let machine = UXStateMachine()
        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        machine.transition(.confirmSend)  // → THINKING
        let result = machine.transition(.startCapture)
        XCTAssertFalse(result, "Cannot startCapture while thinking")
        XCTAssertEqual(machine.currentState, .thinking)
    }

    func test_confirmSend_from_idle_is_invalid() {
        let machine = UXStateMachine()
        let result = machine.transition(.confirmSend)
        XCTAssertFalse(result)
        XCTAssertEqual(machine.currentState, .idle)
    }

    func test_shareAgain_from_idle_is_invalid() {
        let machine = UXStateMachine()
        let result = machine.transition(.shareAgain)
        XCTAssertFalse(result)
        XCTAssertEqual(machine.currentState, .idle)
    }

    // MARK: - Complete Flow: Full Cycle IDLE → SHOWING → IDLE

    func test_full_cycle_idle_to_showing_to_idle() {
        let machine = UXStateMachine()

        // IDLE → SELECTING
        XCTAssertTrue(machine.transition(.startCapture))
        XCTAssertEqual(machine.currentState, .selecting)

        // SELECTING → PREVIEW
        XCTAssertTrue(machine.transition(.captureComplete))
        XCTAssertEqual(machine.currentState, .preview)

        // PREVIEW → THINKING
        XCTAssertTrue(machine.transition(.confirmSend))
        XCTAssertEqual(machine.currentState, .thinking)

        // THINKING → SHOWING
        XCTAssertTrue(machine.transition(.responseReceived))
        XCTAssertEqual(machine.currentState, .showing)

        // SHOWING → IDLE
        XCTAssertTrue(machine.transition(.dismiss))
        XCTAssertEqual(machine.currentState, .idle)
    }

    // MARK: - Full Cycle with Cancel at PREVIEW

    func test_full_cycle_with_cancel_at_preview() {
        let machine = UXStateMachine()

        XCTAssertTrue(machine.transition(.startCapture))      // → SELECTING
        XCTAssertTrue(machine.transition(.captureComplete))   // → PREVIEW
        XCTAssertTrue(machine.transition(.cancelPreview))     // → IDLE
        XCTAssertEqual(machine.currentState, .idle)
        XCTAssertFalse(machine.isCapturing)
    }

    // MARK: - Full Cycle with Cancel at SELECTING

    func test_full_cycle_with_cancel_at_selecting() {
        let machine = UXStateMachine()

        XCTAssertTrue(machine.transition(.startCapture))      // → SELECTING
        XCTAssertTrue(machine.transition(.cancelCapture))     // → IDLE
        XCTAssertEqual(machine.currentState, .idle)
    }

    // MARK: - Error Path

    func test_error_path_thinking_to_idle() {
        let machine = UXStateMachine()

        machine.transition(.startCapture)
        machine.transition(.captureComplete)
        machine.transition(.confirmSend)  // → THINKING
        XCTAssertTrue(machine.transition(.aiError))
        XCTAssertEqual(machine.currentState, .idle)
        XCTAssertFalse(machine.isCapturing)
    }

    // MARK: - State Properties

    func test_isIdle_only_true_when_idle() {
        let machine = UXStateMachine()
        XCTAssertTrue(machine.isIdle)

        machine.transition(.startCapture)
        XCTAssertFalse(machine.isIdle)
    }

    func test_isCapturing_true_in_selecting_preview_thinking_showing() {
        let machine = UXStateMachine()
        XCTAssertFalse(machine.isCapturing)

        machine.transition(.startCapture)  // → SELECTING
        XCTAssertTrue(machine.isCapturing)

        machine.transition(.captureComplete)  // → PREVIEW
        XCTAssertTrue(machine.isCapturing)

        machine.transition(.confirmSend)  // → THINKING
        XCTAssertTrue(machine.isCapturing)

        machine.transition(.responseReceived)  // → SHOWING
        XCTAssertTrue(machine.isCapturing)

        machine.transition(.dismiss)  // → IDLE
        XCTAssertFalse(machine.isCapturing)
    }

    func test_isThinking_only_true_when_thinking() {
        let machine = UXStateMachine()
        XCTAssertFalse(machine.isThinking)

        machine.transition(.startCapture)
        XCTAssertFalse(machine.isThinking)

        machine.transition(.captureComplete)
        XCTAssertFalse(machine.isThinking)

        machine.transition(.confirmSend)  // → THINKING
        XCTAssertTrue(machine.isThinking)

        machine.transition(.responseReceived)  // → SHOWING
        XCTAssertFalse(machine.isThinking)
    }

    // MARK: - Transition Event Callbacks

    func test_transition_callback_is_invoked_on_valid_transition() {
        let machine = UXStateMachine()
        var callbackCount = 0
        var lastFrom: UXState?
        var lastTo: UXState?

        machine.onTransition = { from, to in
            callbackCount += 1
            lastFrom = from
            lastTo = to
        }

        machine.transition(.startCapture)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(lastFrom, .idle)
        XCTAssertEqual(lastTo, .selecting)
    }

    func test_transition_callback_not_invoked_on_invalid_transition() {
        let machine = UXStateMachine()
        var callbackCount = 0

        machine.onTransition = { _, _ in
            callbackCount += 1
        }

        machine.transition(.dismiss)  // Invalid from IDLE
        XCTAssertEqual(callbackCount, 0, "Callback should not fire on invalid transition")
    }

    // MARK: - Reset

    func test_reset_returns_to_idle_from_any_state() {
        let statesToTest: [(UXState, [UXTransition])] = [
            (.selecting, [.startCapture]),
            (.preview, [.startCapture, .captureComplete]),
            (.thinking, [.startCapture, .captureComplete, .confirmSend]),
            (.showing, [.startCapture, .captureComplete, .confirmSend, .responseReceived]),
        ]

        for (expectedState, transitions) in statesToTest {
            let machine = UXStateMachine()
            for t in transitions {
                machine.transition(t)
            }
            XCTAssertEqual(machine.currentState, expectedState, "Should be in \(expectedState) before reset")

            machine.reset()
            XCTAssertEqual(machine.currentState, .idle, "Reset should return to IDLE from \(expectedState)")
            XCTAssertFalse(machine.isCapturing)
        }
    }
}
