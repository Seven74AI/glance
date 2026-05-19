import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AI provider using Anthropic's Claude Messages API with Computer Use capabilities.
///
/// Sends screenshots using the Computer Use tool format for best screen understanding.
/// PNG format required (lossless for pixel-accurate analysis).
/// Beta header: `computer-use-2025-11-24`.
///
/// Display dimensions default to 1920×1080 but can be configured for
/// multi-monitor or non-standard resolutions.
///
/// API docs: https://docs.anthropic.com/en/docs/agents-and-tools/computer-use
public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    public let name = "Claude"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let baseURLString = "https://api.anthropic.com/v1/messages"
    private let anthropicVersion = "2023-06-01"
    private let computerUseBeta = "computer-use-2025-11-24"
    private let timeout: TimeInterval = 30
    private let displayWidth: Int
    private let displayHeight: Int
    private let displayNumber: Int

    private let defaultPrompt = "Analyze this screenshot. Describe what you see on the screen. Be concise and helpful."

    /// - Parameters:
    ///   - apiKey: Anthropic API key (starts with `sk-ant-`).
    ///   - model: Claude model identifier (e.g., "claude-sonnet-4-20250514").
    ///   - session: URLSession to use for network requests.
    ///   - displayWidth: Display width in pixels for computer-use tool (default: 1920).
    ///   - displayHeight: Display height in pixels for computer-use tool (default: 1080).
    ///   - displayNumber: Display number for computer-use tool (default: 0).
    public init(
        apiKey: String,
        model: String,
        session: URLSession,
        displayWidth: Int = 1920,
        displayHeight: Int = 1080,
        displayNumber: Int = 0
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.displayNumber = displayNumber
    }

    public func analyze(screenshot: Data, prompt: String?) async throws -> AIResponse {
        let startTime = Date()

        guard let url = URL(string: baseURLString) else {
            throw ProviderError.configurationError("Invalid Claude base URL: \(baseURLString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(computerUseBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userPrompt = prompt ?? defaultPrompt
        let base64Image = screenshot.base64EncodedString()
        let mediaType = "image/png"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "tools": [
                [
                    "type": "computer_20250124",
                    "name": "computer",
                    "display_width_px": displayWidth,
                    "display_height_px": displayHeight,
                    "display_number": displayNumber
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": mediaType,
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": userPrompt
                        ]
                    ]
                ]
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let finalRequest = request

        let (data, response) = try await withTimeout(seconds: timeout) {
            try await self.session.data(for: finalRequest)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Not an HTTP response")
        }

        try validateResponse(httpResponse, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Could not parse Claude response as JSON")
        }

        guard let content = json["content"] as? [[String: Any]] else {
            throw ProviderError.invalidResponse("Missing 'content' array in Claude response")
        }

        let text = content.compactMap { block -> String? in
            if block["type"] as? String == "text" {
                return block["text"] as? String
            }
            return nil
        }.joined(separator: "\n")

        guard !text.isEmpty else {
            throw ProviderError.invalidResponse("No text content in Claude response")
        }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        return AIResponse(text: text, modelUsed: model, latencyMs: elapsed)
    }
}
