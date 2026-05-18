import Foundation
import Security

/// ViewModel for the Preferences window.
///
/// Manages:
/// - AI provider selection (Claude/OpenAI/Gemini)
/// - API key entry with Keychain storage
/// - Default capture mode
/// - Privacy settings (preview toggle, auto-send toggle)
@MainActor
public final class PreferencesViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Currently selected AI provider.
    @Published public var selectedProvider: AIProvider = .claude {
        didSet {
            if oldValue != selectedProvider {
                loadAPIKeyForCurrentProvider()
            }
        }
    }

    /// API key for the current provider (cleared on provider switch).
    @Published public var apiKey: String = ""

    /// Default capture mode for new capture flows.
    @Published public var defaultCaptureMode: CaptureMode = .windowUnderCursor

    /// When enabled, shows a 2-second preview before sending to AI.
    @Published public var previewBeforeSend: Bool = true

    /// When enabled, skips preview entirely and sends immediately.
    @Published public var autoSend: Bool = false

    // MARK: - Initialization

    public init() {
        loadCredentials()
    }

    // MARK: - Computed Properties

    /// Whether an API key has been entered.
    public var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the preferences are in a valid state (API key set).
    public var isValid: Bool {
        hasAPIKey
    }

    // MARK: - Keychain Operations

    /// Save the current API key to the Keychain.
    public func saveCredentials() {
        guard hasAPIKey else {
            deleteAPIKey()
            return
        }
        storeInKeychain(key: selectedProvider.keychainKey, value: apiKey)
    }

    /// Load saved credentials from the Keychain.
    public func loadCredentials() {
        loadAPIKeyForCurrentProvider()
    }

    private func loadAPIKeyForCurrentProvider() {
        apiKey = readFromKeychain(key: selectedProvider.keychainKey) ?? ""
    }

    // MARK: - Keychain Helpers

    private func storeInKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: selectedProvider.keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
