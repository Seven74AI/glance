import SwiftUI

/// SHOWING state: displays the AI response in a floating overlay panel.
///
/// Features:
/// - Markdown-rendered AI response text
/// - "Ask follow-up" text field (single follow-up, not threaded)
/// - "Share again" button (returns to SELECTING)
/// - Dismiss: Esc key or 30s timeout (managed by StateMachineViewModel)
public struct ResponseDisplayView: View {
    /// The AI response text (may contain Markdown).
    let responseText: String

    /// Called when user wants to share again.
    let onShareAgain: () -> Void

    /// Called when user wants to dismiss.
    let onDismiss: () -> Void

    /// Follow-up question state.
    @State private var followUpText: String = ""
    @State private var hasAskedFollowUp: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header with state indicator
            headerView

            Divider()
                .padding(.horizontal, 20)

            // Response content (scrollable)
            ScrollView(.vertical, showsIndicators: true) {
                responseContentView
            }
            .frame(maxHeight: 300)

            Divider()
                .padding(.horizontal, 20)

            // Follow-up section
            if !hasAskedFollowUp {
                followUpSection
            } else {
                followUpSentView
            }

            // Action buttons
            actionButtons
        }
        .padding(.vertical, 12)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("AI Response")
                    .font(.headline)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Dismiss (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var responseContentView: some View {
        Text(responseText)
            .font(.body)
            .textSelection(.enabled)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    private var followUpSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextField(
                    "Ask a follow-up question...",
                    text: $followUpText
                )
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit {
                    sendFollowUp()
                }

                if !followUpText.isEmpty {
                    Button(action: sendFollowUp) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var followUpSentView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Follow-up sent. AI is processing...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Label("Dismiss", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.escape, modifiers: [])

            Button(action: onShareAgain) {
                Label("Share Again", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func sendFollowUp() {
        guard !followUpText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        hasAskedFollowUp = true
        // In MVP, the follow-up triggers a new AI request via the ViewModel.
        // The actual API call is handled by the AI Provider layer (Phase 1.3).
        followUpText = ""
    }
}
