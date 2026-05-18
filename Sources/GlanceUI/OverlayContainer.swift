import SwiftUI

/// Root SwiftUI container for the overlay panel.
///
/// Switches between the five UX states:
///   IDLE → (hidden)
///   SELECTING → CaptureModePicker
///   PREVIEW → ScreenshotPreview
///   THINKING → AIThinkingView
///   SHOWING → ResponseDisplayView
///
/// Uses the StateMachineViewModel to drive state transitions.
public struct OverlayContainer: View {
    @ObservedObject var viewModel: StateMachineViewModel

    /// Callback when user wants to dismiss the overlay.
    var onDismiss: () -> Void

    /// Callback when user triggers a capture with a specific mode.
    var onCaptureModeSelected: (CaptureMode) -> Void

    /// Standard overlay width (fixed for consistent UX).
    private let overlayWidth: CGFloat = 420

    public init(
        viewModel: StateMachineViewModel,
        onDismiss: @escaping () -> Void = {},
        onCaptureModeSelected: @escaping (CaptureMode) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onCaptureModeSelected = onCaptureModeSelected
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                // Hidden — overlay should not be visible when idle.
                EmptyView()

            case .selecting:
                CaptureModePicker(
                    onSelect: { mode in
                        viewModel.selectedCaptureMode = mode
                        onCaptureModeSelected(mode)
                    },
                    onCancel: {
                        viewModel.cancelCapture()
                        onDismiss()
                    }
                )

            case .preview:
                ScreenshotPreview(
                    imageData: viewModel.capturedImageData,
                    userQuestion: $viewModel.userQuestion,
                    previewDuration: viewModel.previewDuration,
                    autoContinue: viewModel.previewAutoContinue,
                    onConfirm: {
                        viewModel.confirmSend()
                    },
                    onCancel: {
                        viewModel.cancelPreview()
                        onDismiss()
                    }
                )

            case .thinking:
                AIThinkingView()

            case .showing:
                ResponseDisplayView(
                    responseText: viewModel.aiResponseText ?? "",
                    onShareAgain: {
                        viewModel.shareAgain()
                    },
                    onDismiss: {
                        viewModel.dismiss()
                        onDismiss()
                    }
                )
            }
        }
        .frame(width: overlayWidth)
        .fixedSize(horizontal: true, vertical: false)
    }
}
