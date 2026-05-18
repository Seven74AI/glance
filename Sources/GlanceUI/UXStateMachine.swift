import Foundation

// MARK: - UX State Machine (research-ux-design.md §3.4)
//
// States: IDLE → SELECTING → PREVIEW → THINKING → SHOWING → IDLE
//
// This is the core UX state machine for Glance. It enforces valid
// transitions and provides callbacks for state changes.

/// The five UX states in the Glance capture→response flow.
public enum UXState: Equatable, Sendable {
    /// App is idle, no active capture or overlay.
    case idle
    /// User is selecting a capture mode (window/region/full-screen).
    case selecting
    /// Screenshot preview shown; user can confirm or cancel.
    case preview
    /// AI is processing the screenshot.
    case thinking
    /// AI response is displayed in the floating overlay.
    case showing
}

/// Valid transitions between UX states.
public enum UXTransition: Equatable, Sendable {
    /// Trigger capture flow (shortcut or menu item).
    case startCapture
    /// Capture completed successfully.
    case captureComplete
    /// User cancelled during capture mode selection.
    case cancelCapture
    /// User confirmed the preview (or auto-continue after 2s).
    case confirmSend
    /// User cancelled during preview.
    case cancelPreview
    /// AI returned a response.
    case responseReceived
    /// AI returned an error or timed out.
    case aiError
    /// User wants to share again from the response view.
    case shareAgain
    /// Dismiss the overlay (Esc, click-away, or 30s timeout).
    case dismiss
}

/// UXStateMachine enforces the valid transition graph.
///
/// ```text
/// IDLE ──startCapture──▶ SELECTING
/// SELECTING ──captureComplete──▶ PREVIEW
/// SELECTING ──cancelCapture──▶ IDLE
/// PREVIEW ──confirmSend──▶ THINKING
/// PREVIEW ──cancelPreview──▶ IDLE
/// THINKING ──responseReceived──▶ SHOWING
/// THINKING ──aiError──▶ IDLE
/// SHOWING ──shareAgain──▶ SELECTING
/// SHOWING ──dismiss──▶ IDLE
/// ```
@MainActor
public final class UXStateMachine: ObservableObject, @unchecked Sendable {
    /// The current UX state.
    @Published public private(set) var currentState: UXState = .idle

    /// Optional callback invoked on every successful transition.
    public var onTransition: ((UXState, UXState) -> Void)?

    // MARK: - Transition Map

    /// Valid transitions keyed by source state.
    private let validTransitions: [UXState: Set<UXTransition>] = [
        .idle:      [.startCapture],
        .selecting: [.captureComplete, .cancelCapture],
        .preview:   [.confirmSend, .cancelPreview],
        .thinking:  [.responseReceived, .aiError],
        .showing:   [.shareAgain, .dismiss],
    ]

    /// Target state for each valid (source, transition) pair.
    private let transitionTargets: [UXState: [UXTransition: UXState]] = [
        .idle: [
            .startCapture: .selecting,
        ],
        .selecting: [
            .captureComplete: .preview,
            .cancelCapture: .idle,
        ],
        .preview: [
            .confirmSend: .thinking,
            .cancelPreview: .idle,
        ],
        .thinking: [
            .responseReceived: .showing,
            .aiError: .idle,
        ],
        .showing: [
            .shareAgain: .selecting,
            .dismiss: .idle,
        ],
    ]

    // MARK: - Public API

    /// Attempt a transition. Returns `true` if the transition is valid
    /// and was executed; returns `false` if the transition is invalid
    /// from the current state (state unchanged).
    @discardableResult
    public func transition(_ t: UXTransition) -> Bool {
        guard let allowed = validTransitions[currentState], allowed.contains(t) else {
            return false
        }
        guard let target = transitionTargets[currentState]?[t] else {
            return false
        }

        let from = currentState
        currentState = target
        onTransition?(from, target)
        return true
    }

    /// Reset to IDLE regardless of current state.
    public func reset() {
        let from = currentState
        currentState = .idle
        if from != .idle {
            onTransition?(from, .idle)
        }
    }

    // MARK: - Convenience Properties

    /// True when any capture flow is active (not idle).
    public var isCapturing: Bool {
        currentState != .idle
    }

    /// True when in IDLE state.
    public var isIdle: Bool {
        currentState == .idle
    }

    /// True when AI is processing.
    public var isThinking: Bool {
        currentState == .thinking
    }

    /// True when showing AI response.
    public var isShowing: Bool {
        currentState == .showing
    }
}
