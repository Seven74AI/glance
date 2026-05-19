import SwiftUI

/// THINKING state: spinner/progress while AI analyzes the screenshot.
///
/// Shows:
/// - Animated spinner
/// - "AI is analyzing your screen..." message
/// - Menu bar icon changes to orange dot (handled by MenuBarApp)
public struct AIThinkingView: View {
    @State private var isAnimating: Bool = false

    public var body: some View {
        VStack(spacing: 20) {
            // Spinner
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
                .padding(.top, 24)

            // Message
            VStack(spacing: 6) {
                Text("AI is analyzing your screen...")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("This usually takes 2–5 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Animated dots (staggered)
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .opacity(isAnimating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .onAppear {
            isAnimating = true
        }
    }
}
