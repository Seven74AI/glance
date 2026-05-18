import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AI provider using Google's Gemini API (2.5 Flash/Pro).
///
/// Sends screenshots as inline image bytes via the `generateContent` endpoint.
/// Supports JPEG and PNG formats.
///
/// API docs: https://ai.google.dev/gemini-api/docs/vision
public final class GeminiProvider: AIProvider, @unchecked Sendable {
    public let name = "Gemini"

    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let timeout: TimeInterval = 30

    private let defaultPrompt = "Analyze this screenshot. Describe what you see on the screen. Be concise and helpful."

    public init(apiKey: String, model: String, session: URLSession) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyze(screenshot: Data, prompt: String?) async throws -> AIResponse {
        let startTime = Date()

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw ProviderError.configurationError("Invalid Gemini URL for model: \(model)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userPrompt = prompt ?? defaultPrompt
        let base64Image = screenshot.base64EncodedString()
        let mimeType = detectImageFormat(screenshot) == .png ? "image/png" : "image/jpeg"

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": userPrompt],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generation_config": [
                "max_output_tokens": 1024
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
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw ProviderError.invalidResponse("Could not parse Gemini response")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")

        guard !text.isEmpty else {
            throw ProviderError.invalidResponse("No text content in Gemini response")
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
