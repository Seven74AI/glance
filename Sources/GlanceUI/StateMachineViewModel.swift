import Foundation
import Combine

/// ViewModel wrapping UXStateMachine with timer logic and capture flow management.
///
/// Handles:
/// - 2-second preview auto-continue timer
/// - 30-second dismiss timeout
/// - Capture mode tracking
/// - AI response text storage
/// - Human-readable state labels
@MainActor
public final class StateMachineViewModel: ObservableObject {
    // MARK: - Published State

    /// The underlying UX state machine.
    @Published public private(set) var state: UXState = .idle

    /// Human-readable label for the current state.
    @Published public private(set) var stateLabel: String = "Ready"

    /// AI response text (populated when THINKING → SHOWING).
    @Published public var aiResponseText: String?

    /// Error message from AI provider.
    @Published public var errorMessage: String?

    /// Currently selected capture mode (set at flow start).
    @Published public private(set) var selectedCaptureMode: CaptureMode?

    /// User's optional question during preview.
    @Published public var userQuestion: String?

    /// Raw screenshot data (JPEG).
    @Published public var capturedImageData: Data?

    /// Remaining preview seconds (countdown from previewDuration to 0).
    @Published public var remainingPreviewSeconds: TimeInterval = 0

    // MARK: - Timer Configuration

    /// Duration to show preview before auto-continue (seconds).
    public var previewDuration: TimeInterval = 2.0

    /// Duration to show AI response before auto-dismiss (seconds).
    public var dismissTimeout: TimeInterval = 30.0

    /// When true, preview auto-continues after `previewDuration`.
    public var previewAutoContinue: Bool = true

    // MARK: - Private State

    /// The state machine enforcing valid transitions.
    private let stateMachine: UXStateMachine

    /// Timer for preview auto-continue.
    private var previewTimer: Timer?

    /// Timer for response auto-dismiss.
    private var dismissTimer: Timer?

    /// Combine cancellables.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init() {
        stateMachine = UXStateMachine()
        setupStateMachineBinding()
    }

    /// Wire the state machine's @Published currentState to our published state.
    private func setupStateMachineBinding() {
        stateMachine.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
                self?.stateLabel = self?.label(for: newState) ?? "Unknown"
            }
            .store(in: &cancellables)
    }

    // MARK: - Human-Readable Labels

    private func label(for state: UXState) -> String {
        switch state {
        case .idle:     return "Ready"
        case .selecting: return "Selecting capture mode..."
        case .preview:  return "Preview — send or cancel?"
        case .thinking:  return "AI is analyzing your screen..."
        case .showing:  return "AI Response"
        }
    }

    // MARK: - Public Actions

    /// Begin the capture flow with the chosen mode.
    public func startCaptureFlow(mode: CaptureMode) {
        cancelAllTimers()
        clearTransientState()
        selectedCaptureMode = mode
        stateMachine.transition(.startCapture)
    }

    /// Called when the capture engine finished capturing a frame.
    public func completeCapture() {
        guard stateMachine.transition(.captureComplete) else { return }
        startPreviewTimer()
    }

    /// User cancelled during capture mode selection.
    public func cancelCapture() {
        stateMachine.transition(.cancelCapture)
        cleanupAfterDismiss()
    }

    /// User confirmed the preview (or auto-continue fired).
    public func confirmSend() {
        cancelPreviewTimer()
        stateMachine.transition(.confirmSend)
    }

    /// User cancelled during preview.
    public func cancelPreview() {
        cancelPreviewTimer()
        stateMachine.transition(.cancelPreview)
        cleanupAfterDismiss()
    }

    /// AI provider returned a response.
    public func receiveResponse(text: String) {
        cancelPreviewTimer()
        aiResponseText = text
        errorMessage = nil
        stateMachine.transition(.responseReceived)
        startDismissTimer()
    }

    /// AI provider returned an error.
    public func receiveError(message: String) {
        cancelAllTimers()
        errorMessage = message
        stateMachine.transition(.aiError)
        cleanupAfterDismiss(keepError: true)
    }

    /// Share again from the response view.
    public func shareAgain() {
        cancelDismissTimer()
        clearTransientState()
        stateMachine.transition(.shareAgain)
    }

    /// Dismiss the overlay from SHOWING state.
    public func dismiss() {
        stateMachine.transition(.dismiss)
        cleanupAfterDismiss()
    }

    /// Reset everything to IDLE.
    public func reset() {
        stateMachine.reset()
        cleanupAfterDismiss()
    }

    // MARK: - Convenience Properties

    public var isIdle: Bool { state == .idle }
    public var isCapturing: Bool { state != .idle }
    public var isThinking: Bool { state == .thinking }
    public var isShowing: Bool { state == .showing }

    // MARK: - Timer Management

    private func startPreviewTimer() {
        guard previewAutoContinue else { return }
        remainingPreviewSeconds = previewDuration
        previewTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                self.remainingPreviewSeconds -= 0.25
                if self.remainingPreviewSeconds <= 0 {
                    timer.invalidate()
                    self.previewTimer = nil
                    self.remainingPreviewSeconds = 0
                    self.confirmSend()
                }
            }
        }
    }

    private func startDismissTimer() {
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: dismissTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func cancelPreviewTimer() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    private func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    private func cancelAllTimers() {
        cancelPreviewTimer()
        cancelDismissTimer()
    }

    // MARK: - State Cleanup

    /// Clear transient state between captures.
    private func clearTransientState() {
        aiResponseText = nil
        errorMessage = nil
        userQuestion = nil
        capturedImageData = nil
    }

    /// Full cleanup on dismiss or reset, optionally preserving error.
    private func cleanupAfterDismiss(keepError: Bool = false) {
        cancelAllTimers()
        if !keepError {
            errorMessage = nil
        }
        aiResponseText = nil
        userQuestion = nil
        capturedImageData = nil
        selectedCaptureMode = nil
    }
}
