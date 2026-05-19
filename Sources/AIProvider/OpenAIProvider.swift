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
    private let baseURLString = "https://api.openai.com/v1/chat/completions"
    private let timeout: TimeInterval = 30

    private let defaultPrompt = "Analyze this screenshot. Describe what you see on the screen. Be concise and helpful."

    public init(apiKey: String, model: String, session: URLSession) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func analyze(screenshot: Data, prompt: String?) async throws -> AIResponse {
        let startTime = Date()

        guard let url = URL(string: baseURLString) else {
            throw ProviderError.configurationError("Invalid OpenAI base URL: \(baseURLString)")
        }

        var request = URLRequest(url: url)
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
}
