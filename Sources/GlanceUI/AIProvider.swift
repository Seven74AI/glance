import Foundation

/// Supported AI providers for screen analysis.
public enum AIProvider: String, CaseIterable, Sendable {
    /// Claude Computer Use (Anthropic) — primary provider.
    case claude
    /// GPT-4V / GPT-4o (OpenAI).
    case openAI
    /// Gemini Vision (Google).
    case gemini

    /// Human-readable provider name for the preferences UI.
    public var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openAI: return "GPT-4V (OpenAI)"
        case .gemini:  return "Gemini (Google)"
        }
    }

    /// Keychain service key for this provider's API key.
    public var keychainKey: String {
        "com.glance.apikey.\(rawValue)"
    }
}
