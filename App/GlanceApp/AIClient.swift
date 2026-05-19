import Foundation
import GlanceUI

// MARK: - Protocol

/// Protocol for AI vision analysis — pluggable per provider.
///
/// Conforming types wrap the HTTP calls to Claude, GPT, Gemini APIs
/// for screen image analysis. Injected into GlancePipeline for testability.
protocol AIClientProtocol {
    /// Analyzes a JPEG image using the specified AI provider.
    ///
    /// - Parameters:
    ///   - image: JPEG image data (typically from FrameProcessor).
    ///   - provider: Which AI provider to use (.claude, .openAI, .gemini).
    ///   - apiKey: Provider API key (loaded from Keychain).
    ///   - question: Optional user question about the screenshot.
    /// - Returns: The AI's text response.
    /// - Throws: ``AIClientError`` on network, auth, or API failures.
    func analyze(
        image: Data,
        provider: AIProvider,
        apiKey: String,
        question: String?
    ) async throws -> String
}

// MARK: - Errors

/// Errors thrown by the AI client layer.
enum AIClientError: LocalizedError, Equatable {
    /// API key is empty or missing.
    case missingAPIKey(AIProvider)
    /// Image data is empty or invalid.
    case invalidImageData
    /// HTTP error with status code.
    case httpError(statusCode: Int, body: String)
    /// Network connectivity failure.
    case networkError(underlying: String)
    /// API returned an unexpected response shape.
    case unexpectedResponse(String)
    /// Rate limit exceeded.
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider.displayName). Add your key in Preferences."
        case .invalidImageData:
            return "Invalid image data — cannot send to AI."
        case .httpError(let code, let body):
            return "API error \(code): \(body)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .unexpectedResponse(let detail):
            return "Unexpected API response: \(detail)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds))s."
            }
            return "Rate limited. Please wait before retrying."
        }
    }
}

// NOTE: AIClient intentionally duplicates AIProvider module (Sources/AIProvider/).
// The AIProvider module defines an `AIProvider` protocol that conflicts with
// GlanceUI's `AIProvider` enum. Both are deeply embedded in their respective
// module APIs. Post-MVP resolution plan:
//   1. Rename GlanceUI.AIProvider enum → AIProviderID
//   2. Add `import AIProvider` to AIClient.swift
//   3. Replace callClaude/callOpenAI/callGemini with delegation to
//      ClaudeProvider/OpenAIProvider/GeminiProvider, mapping ProviderError → AIClientError
//   4. Retain the simpler AIClientProtocol (apiKey-per-call, String return)
//
// Until then, the AIClient directly implements the same HTTP endpoints with
// the same auth patterns and response parsing. The duplication is ~300 lines
// of well-tested code — functionally equivalent but independently maintained.
// See: AIProvider module already added as GlanceApp dependency in Package.swift.

/// Concrete AI client using URLSession for HTTP calls.
///
/// Supports three providers:
/// - Claude (Anthropic Messages API)
/// - GPT-4V (OpenAI Chat Completions API)
/// - Gemini (Google Generative Language API)
@available(macOS 14.0, *)
final class AIClient: AIClientProtocol {

    // MARK: - Configuration

    /// Default request timeout in seconds.
    private let timeout: TimeInterval

    /// URLSession for all HTTP requests.
    private let session: URLSession

    // MARK: - Initialization

    /// Creates an AI client.
    /// - Parameters:
    ///   - timeout: Request timeout in seconds (default 30).
    ///   - session: URLSession to use (injectable for testing).
    init(timeout: TimeInterval = 30, session: URLSession = .shared) {
        self.timeout = timeout
        self.session = session
    }

    // MARK: - Public API

    func analyze(
        image: Data,
        provider: AIProvider,
        apiKey: String,
        question: String?
    ) async throws -> String {
        // Validate inputs.
        guard !image.isEmpty else {
            throw AIClientError.invalidImageData
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.missingAPIKey(provider)
        }

        // Base64-encode the image for transport.
        let base64Image = image.base64EncodedString()

        // Route to the correct provider.
        switch provider {
        case .claude:
            return try await callClaude(apiKey: apiKey, base64Image: base64Image, question: question)
        case .openAI:
            return try await callOpenAI(apiKey: apiKey, base64Image: base64Image, question: question)
        case .gemini:
            return try await callGemini(apiKey: apiKey, base64Image: base64Image, question: question)
        }
    }

    // MARK: - Claude (Anthropic Messages API)

    private func callClaude(
        apiKey: String,
        base64Image: String,
        question: String?
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Build the user message with image + optional question.
        var content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ]
        ]

        let promptText = question ?? "Describe what you see on this screen. Be concise and helpful."
        content.append([
            "type": "text",
            "text": promptText
        ])

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        // Parse Claude's response.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else {
            throw AIClientError.unexpectedResponse("Claude response missing content[0].text")
        }

        return text
    }

    // MARK: - OpenAI (GPT-4V Chat Completions)

    private func callOpenAI(
        apiKey: String,
        base64Image: String,
        question: String?
    ) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let promptText = question ?? "Describe what you see on this screen. Be concise and helpful."

        let userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": promptText
            ],
            [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64Image)",
                    "detail": "auto"
                ]
            ]
        ]

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIClientError.unexpectedResponse("GPT response missing choices[0].message.content")
        }

        return text
    }

    // MARK: - Gemini (Google Generative Language)

    private func callGemini(
        apiKey: String,
        base64Image: String,
        question: String?
    ) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/"
            + "gemini-2.5-flash:generateContent?key=***")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let promptText = question ?? "Describe what you see on this screen. Be concise and helpful."

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": promptText],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIClientError.unexpectedResponse("Gemini response missing candidates[0].content.parts[0].text")
        }

        return text
    }

    // MARK: - HTTP Validation

    /// Validates the HTTP response, throwing on non-2xx or rate limit.
    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.networkError(underlying: "Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return // OK
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw AIClientError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AIClientError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}
