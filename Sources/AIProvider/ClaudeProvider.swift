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
/// API docs: https://docs.anthropic.com/en/docs/agents-and-tools/computer-use
public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    public let name = "Claude"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let anthropicVersion = "2023-06-01"
    private let computerUseBeta = "computer-use-2025-11-24"
    private let timeout: TimeInterval = 30

    private let defaultPrompt = "Analyze this screenshot. Describe what you see on the screen. Be concise and helpful."

    public init(apiKey: String, model: String, session: URLSession) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyze(screenshot: Data, prompt: String?) async throws -> AIResponse {
        let startTime = Date()

        var request = URLRequest(url: URL(string: baseURL)!)
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
                    "display_width_px": 1920,
                    "display_height_px": 1080,
                    "display_number": 0
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

    // MARK: - Private Helpers

    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200:
            return
        case 401, 403:
            let message = parseErrorMessage(data)
            throw ProviderError.unauthorized(message ?? "Authentication failed (HTTP \(response.statusCode))")
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ProviderError.rateLimited(retryAfterSeconds: retryAfter)
        case 400..<500:
            let message = parseErrorMessage(data)
            throw ProviderError.serverError(statusCode: response.statusCode, message: message)
        default:
            let message = parseErrorMessage(data)
            throw ProviderError.serverError(statusCode: response.statusCode, message: message)
        }
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ProviderError.networkTimeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
