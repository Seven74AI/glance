import SwiftUI

/// Preferences window for Glance.
///
/// Sections:
/// - AI Provider selection (Claude/GPT/Gemini)
/// - API key entry (secure field)
/// - Default capture mode
/// - Privacy settings (preview toggle, auto-send toggle)
public struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            aiTab
                .tabItem {
                    Label("AI Provider", systemImage: "brain")
                }
            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .frame(width: 480, height: 380)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker("Default capture mode:", selection: $viewModel.defaultCaptureMode) {
                    ForEach([CaptureMode.windowUnderCursor, .drawRegion, .fullScreen], id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("The capture mode used when you press ⌃⌥⌘G or click \"Share Screen\".")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Capture")
            }

            Section {
                Toggle("Show preview before sending", isOn: $viewModel.previewBeforeSend)
                Text("When enabled, you'll see a 2-second preview before the screenshot is sent to the AI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - AI Provider Tab

    private var aiTab: some View {
        Form {
            Section {
                Picker("Provider:", selection: $viewModel.selectedProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("AI Provider")
            }

            Section {
                SecureField("API Key", text: $viewModel.apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if viewModel.hasAPIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("API key set")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("API key required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Save to Keychain") {
                        viewModel.saveCredentials()
                    }
                    .disabled(!viewModel.hasAPIKey)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Privacy Tab

    private var privacyTab: some View {
        Form {
            Section {
                Toggle("Preview before sending", isOn: $viewModel.previewBeforeSend)
                Text("Always review your screenshot before it leaves your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Auto-send (skip preview)", isOn: $viewModel.autoSend)
                    .disabled(viewModel.previewBeforeSend)
                Text("When enabled, screenshots are sent immediately without preview. Not recommended.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Screenshot Privacy")
            }

            Section {
                Text("Glance sends screenshots to your chosen AI provider for analysis. Screenshots are transmitted over HTTPS and are subject to the AI provider's data usage policies.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Data Handling")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preferences Window Controller

/// NSWindowController wrapping the Preferences SwiftUI view.
public final class PreferencesWindowController: NSWindowController {
    public convenience init(viewModel: PreferencesViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Glance Preferences"
        window.contentView = NSHostingView(rootView: PreferencesView(viewModel: viewModel))
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
    }

    /// Show the preferences window, bringing it to front if already open.
    public func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
