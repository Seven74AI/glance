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
}
