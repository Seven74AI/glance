import SwiftUI

/// PREVIEW state: shows the captured screenshot for 2 seconds.
///
/// Features:
/// - Displays the captured frame
/// - Cancel button to abort
/// - Optional text input: "Ask a question about this screen..."
/// - Auto-continues after previewDuration if autoContinue is enabled
/// - Countdown display driven by ViewModel (timer ownership in ViewModel)
public struct ScreenshotPreview: View {
    /// Raw JPEG data of the captured screenshot.
    let imageData: Data?

    /// User's optional question about the screen.
    @Binding var userQuestion: String?

    /// Duration of the preview in seconds.
    let previewDuration: TimeInterval

    /// Remaining seconds in the preview countdown (driven by ViewModel).
    let remainingSeconds: TimeInterval

    /// Whether to auto-continue after previewDuration.
    let autoContinue: Bool

    /// Called when user confirms (or auto-continue fires).
    let onConfirm: () -> Void

    /// Called when user cancels.
    let onCancel: () -> Void

    public init(
        imageData: Data?,
        userQuestion: Binding<String?>,
        previewDuration: TimeInterval = 2.0,
        remainingSeconds: TimeInterval = 2.0,
        autoContinue: Bool = true,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.imageData = imageData
        self._userQuestion = userQuestion
        self.previewDuration = previewDuration
        self.remainingSeconds = remainingSeconds
        self.autoContinue = autoContinue
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .padding(.horizontal, 20)

            // Screenshot thumbnail
            screenshotView

            // Question input field
            questionField

            // Action buttons
            actionButtons
        }
        .padding(.vertical, 12)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "eye")
                .font(.title3)
                .foregroundColor(.accentColor)
            Text("Preview")
                .font(.headline)
            if autoContinue {
                Spacer()
                Text("Sending in \(Int(ceil(remainingSeconds)))s...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var screenshotView: some View {
        if let data = imageData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        } else {
            // Placeholder when no image data (e.g., during dev)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
                .frame(height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private var questionField: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.bubble")
                .foregroundColor(.secondary)
                .font(.caption)

            TextField(
                "Ask a question about this screen...",
                text: Binding(
                    get: { userQuestion ?? "" },
                    set: { userQuestion = $0.isEmpty ? nil : $0 }
                )
            )
            .textFieldStyle(.plain)
            .font(.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.escape, modifiers: [])

            Button(action: onConfirm) {
                Text("Send")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

}

// MARK: - Button Styles

/// Primary (accent) button style for confirm/send actions.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
    }
}

/// Secondary (subtle) button style for cancel/dismiss actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.05))
            )
    }
}
