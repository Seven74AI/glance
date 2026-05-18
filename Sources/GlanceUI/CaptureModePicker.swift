import SwiftUI

/// SELECTING state: user picks capture mode.
///
/// Three modes:
/// 1. "Window under cursor" — default, fastest
/// 2. "Draw region" — crosshair cursor, drag rectangle
/// 3. "Full screen" — captures current display
public struct CaptureModePicker: View {
    let onSelect: (CaptureMode) -> Void
    let onCancel: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .padding(.horizontal, 20)

            // Mode buttons
            VStack(spacing: 8) {
                modeButton(
                    title: "Window under cursor",
                    subtitle: "Click any window to capture it",
                    icon: "macwindow",
                    action: { onSelect(.windowUnderCursor) }
                )

                modeButton(
                    title: "Draw region",
                    subtitle: "Drag to select an area of the screen",
                    icon: "rectangle.dashed",
                    action: { onSelect(.drawRegion) }
                )

                modeButton(
                    title: "Full screen",
                    subtitle: "Capture the entire current display",
                    icon: "display",
                    action: { onSelect(.fullScreen) }
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Cancel
            Divider()
                .padding(.horizontal, 20)

            Button(action: onCancel) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.vertical, 12)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "camera.viewfinder")
                .font(.title3)
                .foregroundColor(.accentColor)
            Text("Capture Screen")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func modeButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
