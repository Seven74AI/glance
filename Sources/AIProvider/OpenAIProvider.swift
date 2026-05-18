import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AI provider using OpenAI's Chat Completions API with vision support (GPT-4V / GPT-4o).
///
/// Sends screenshots as `image_url` content blocks in the chat messages.
/// Supports JPEG and PNG formats (max 20MB per image).
///
/// API docs: https://platform.openai.com/docs/guides/vision
public final class OpenAIProvider: AIProvider, @unchecked Sendable {
    public let name = "OpenAI"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/chat/completions"
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userPrompt = prompt ?? defaultPrompt
        let base64Image = screenshot.base64EncodedString()
        let mediaType = detectImageFormat(screenshot) == .png ? "image/png" : "image/jpeg"
        let dataURL = "data:\(mediaType);base64,\(base64Image)"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": dataURL,
                                "detail": "auto"
                            ]
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw ProviderError.invalidResponse("Could not parse OpenAI response text")
        }

        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        return AIResponse(text: text, modelUsed: model, latencyMs: elapsed)
    }

    // MARK: - Private Helpers

    private enum ImageFormat { case png, jpeg }

    private func detectImageFormat(_ data: Data) -> ImageFormat {
        guard data.count >= 4 else { return .jpeg }
        if data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
            return .png
        }
        return .jpeg
    }

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
