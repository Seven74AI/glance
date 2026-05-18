import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Registry that loads AI providers from configuration and provides runtime switching.
///
/// Loads provider configurations from a JSON file, instantiates the appropriate
/// provider implementations, and provides the default provider for quick access.
public final class ProviderRegistry: @unchecked Sendable {
    /// All loaded providers, keyed by provider ID (e.g., "claude", "openai", "gemini").
    public private(set) var providers: [String: AIProvider] = [:]

    /// The default provider as specified in the configuration.
    public let defaultProviderID: String

    /// The default provider instance. Returns nil if no providers are configured.
    public var defaultProvider: AIProvider? {
        providers[defaultProviderID]
    }

    /// Creates a registry from a configuration, instantiating all providers.
    /// - Parameter config: The AI provider configuration loaded from JSON.
    /// - Parameter session: URLSession to use for all providers.
    public init(config: AIProviderConfiguration, session: URLSession) throws {
        self.defaultProviderID = config.defaultProvider

        for (providerID, providerConfig) in config.providers {
            let provider = try Self.createProvider(
                id: providerID,
                config: providerConfig,
                session: session
            )
            providers[providerID] = provider
        }

        // Validate that the default provider exists
        guard providers[defaultProviderID] != nil else {
            throw ProviderError.configurationError(
                "Default provider '\(defaultProviderID)' not found in configured providers. Available: \(providers.keys.sorted().joined(separator: ", "))"
            )
        }
    }

    /// Creates a registry from a JSON config file on disk.
    /// - Parameter url: File URL to the JSON configuration file.
    /// - Parameter session: URLSession to use for all providers.
    /// - Returns: An initialized ProviderRegistry.
    public static func fromConfigFile(at url: URL, session: URLSession) throws -> ProviderRegistry {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let config = try decoder.decode(AIProviderConfiguration.self, from: data)
        return try ProviderRegistry(config: config, session: session)
    }

    /// Retrieves a provider by its ID.
    /// - Parameter id: The provider identifier (e.g., "claude", "openai", "gemini").
    /// - Returns: The provider instance, or nil if not configured.
    public func provider(id: String) -> AIProvider? {
        providers[id]
    }

    /// All available provider IDs.
    public var availableProviderIDs: [String] {
        Array(providers.keys).sorted()
    }

    // MARK: - Private Factory

    private static func createProvider(
        id: String,
        config: ProviderConfig,
        session: URLSession
    ) throws -> AIProvider {
        guard !config.apiKey.isEmpty, config.apiKey != "sk-..." else {
            throw ProviderError.configurationError(
                "Invalid or placeholder API key for provider '\(id)'"
            )
        }

        switch id.lowercased() {
        case "claude":
            return ClaudeProvider(apiKey: config.apiKey, model: config.model, session: session)
        case "openai":
            return OpenAIProvider(apiKey: config.apiKey, model: config.model, session: session)
        case "gemini":
            return GeminiProvider(apiKey: config.apiKey, model: config.model, session: session)
        default:
            throw ProviderError.configurationError(
                "Unknown provider type '\(id)'. Supported: claude, openai, gemini"
            )
        }
    }
}
