import Foundation

// MARK: - GlanceConfig

/// Glance application configuration, persisted as JSON at `~/.glance/config.json`.
///
/// Manages:
/// - AI provider configurations (API keys, models)
/// - Default provider selection
/// - Default capture mode
/// - Keyboard shortcut
///
/// Auto-creates a default config file on first load if none exists.
public struct GlanceConfig: Sendable, Codable {
    /// AI provider configurations keyed by provider ID (claude, openai, gemini).
    public var providers: [String: ProviderConfig]

    /// The default provider ID (must exist in `providers`).
    public var defaultProvider: String

    /// The default capture mode: "fullScreen", "windowUnderCursor", or "region".
    public var defaultCaptureMode: String

    /// Keyboard shortcut string (e.g., "ctrl+option+cmd+G").
    public var keyboardShortcut: String

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case providers
        case defaultProvider
        case defaultCaptureMode
        case keyboardShortcut
    }

    // MARK: - Default Configuration

    /// The factory default configuration (safe to commit — uses placeholder keys).
    public static let defaultConfig = GlanceConfig(
        providers: [
            "claude": ProviderConfig(apiKey: "sk-...", model: "claude-sonnet-4-20250514"),
            "openai": ProviderConfig(apiKey: "sk-...", model: "gpt-4o"),
            "gemini": ProviderConfig(apiKey: "sk-...", model: "gemini-2.5-flash")
        ],
        defaultProvider: "claude",
        defaultCaptureMode: "windowUnderCursor",
        keyboardShortcut: "ctrl+option+cmd+G"
    )

    // MARK: - Default Path

    /// The default config file path: `~/.glance/config.json`.
    public static func defaultPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let glanceDir = home.appendingPathComponent(".glance", isDirectory: true)
        return glanceDir.appendingPathComponent("config.json")
    }

    // MARK: - File I/O

    /// Loads the config from a file URL. Creates a default config if the file doesn't exist.
    /// - Parameter url: File URL to load from.
    /// - Returns: The loaded or default config.
    /// - Throws: If the file exists but cannot be parsed.
    public static func load(from url: URL) throws -> GlanceConfig {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            // Auto-create default config.
            let config = defaultConfig
            try config.save(to: url)
            return config
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let config = try decoder.decode(GlanceConfig.self, from: data)
        return config
    }

    /// Saves the config to a file URL.
    /// - Parameter url: File URL to save to.
    /// - Throws: If the directory cannot be created or write fails.
    public func save(to url: URL) throws {
        let fileManager = FileManager.default

        // Ensure parent directory exists.
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - API Key Masking

    /// Masks an API key for display, showing only the first 6 and last 4 characters.
    /// - Parameter key: The full API key.
    /// - Returns: A masked string suitable for display in preferences UI.
    public static func maskedAPIKey(_ key: String) -> String {
        guard !key.isEmpty else { return "" }
        guard key.count > 8 else {
            // Keys shorter than 8 characters are fully masked.
            return String(repeating: "•", count: key.count)
        }

        let prefix = String(key.prefix(6))
        let suffix = String(key.suffix(4))
        let maskCount = max(key.count - 10, 4)
        let mask = String(repeating: "•", count: maskCount)
        return "\(prefix)\(mask)\(suffix)"
    }

    // MARK: - Provider Utilities

    /// Checks whether a provider ID is configured.
    public func hasProvider(_ id: String) -> Bool {
        providers[id] != nil
    }

    /// Returns the ProviderConfig for a given provider ID, if configured.
    public func providerConfig(for id: String) -> ProviderConfig? {
        providers[id]
    }

    // MARK: - AIProviderConfiguration Bridge

    /// Converts this GlanceConfig to an AIProviderConfiguration for use with the ProviderRegistry.
    /// - Returns: An AIProviderConfiguration suitable for ProviderRegistry initialization.
    /// - Throws: `ConfigError` if the default provider is missing.
    public func toAIProviderConfiguration() throws -> AIProviderConfiguration {
        guard providers[defaultProvider] != nil else {
            throw ConfigError.defaultProviderMissing(defaultProvider)
        }
        return AIProviderConfiguration(
            providers: providers,
            defaultProvider: defaultProvider
        )
    }
}

// MARK: - Config Errors

/// Errors that can occur during config operations.
public enum ConfigError: Error, LocalizedError, Equatable {
    /// The default provider is not in the providers dictionary.
    case defaultProviderMissing(String)
    /// A provider referenced in the config is unknown.
    case unknownProvider(String)
    /// The config file is malformed.
    case malformedConfig(String)

    public var errorDescription: String? {
        switch self {
        case .defaultProviderMissing(let id):
            return "Default provider '\(id)' not found in configured providers."
        case .unknownProvider(let id):
            return "Unknown provider '\(id)'. Supported: claude, openai, gemini."
        case .malformedConfig(let detail):
            return "Config file is malformed: \(detail)"
        }
    }
}
