import Foundation

// MARK: - AIResponse

/// Response from an AI provider after analyzing a screenshot.
public struct AIResponse: Sendable {
    /// The text response from the AI.
    public let text: String
    /// The model identifier used for this response (e.g., "claude-sonnet-4-20250514").
    public let modelUsed: String
    /// Round-trip latency in milliseconds (request sent → response received).
    public let latencyMs: Int

    public init(text: String, modelUsed: String, latencyMs: Int) {
        self.text = text
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
    }
}

// MARK: - AIProvider Protocol

/// Protocol for pluggable AI providers that analyze screenshots.
/// Each implementation sends image data to a cloud AI API and returns a text response.
public protocol AIProvider: Sendable {
    /// Human-readable provider name (e.g., "Claude", "OpenAI", "Gemini").
    var name: String { get }

    /// Analyze a screenshot and return the AI's response.
    /// - Parameters:
    ///   - screenshot: Image data (JPEG or PNG format).
    ///   - prompt: Optional custom prompt. If nil, a default prompt is used.
    /// - Returns: The AI's text response with metadata.
    /// - Throws: `ProviderError` on failure.
    func analyze(screenshot: Data, prompt: String?) async throws -> AIResponse
}

// MARK: - ProviderError

/// Errors that can occur during AI provider operations.
public enum ProviderError: Error, Sendable, Equatable {
    /// Invalid or missing API key.
    case unauthorized(String)
    /// Rate limit exceeded. Includes retry-after seconds if provided.
    case rateLimited(retryAfterSeconds: Int?)
    /// Network timeout or connectivity issue.
    case networkTimeout
    /// Server returned an error (includes HTTP status code).
    case serverError(statusCode: Int, message: String?)
    /// Invalid response format — couldn't parse the API response.
    case invalidResponse(String)
    /// Configuration error (missing key, invalid model, etc.).
    case configurationError(String)
    /// Unknown error.
    case unknown(String)
}

// MARK: - ProviderConfig

/// Configuration for a single AI provider, loaded from JSON config.
public struct ProviderConfig: Sendable, Decodable {
    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }
}

/// Top-level configuration for all AI providers.
public struct AIProviderConfiguration: Sendable, Decodable {
    public let providers: [String: ProviderConfig]
    public let defaultProvider: String

    public init(providers: [String: ProviderConfig], defaultProvider: String) {
        self.providers = providers
        self.defaultProvider = defaultProvider
    }

    enum CodingKeys: String, CodingKey {
        case providers
        case defaultProvider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providers = try container.decode([String: ProviderConfig].self, forKey: .providers)
        self.defaultProvider = try container.decode(String.self, forKey: .defaultProvider)
    }
}
