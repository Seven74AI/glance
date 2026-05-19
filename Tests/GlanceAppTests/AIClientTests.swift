import XCTest
@testable import GlanceApp
import GlanceUI

/// TDD: AIClient tests — input validation, URL construction, error handling, response parsing.
///
/// Uses URLProtocol mocking to intercept HTTP calls and simulate responses
/// from Claude, GPT, and Gemini APIs without network access.
final class AIClientTests: XCTestCase {

    // MARK: - Properties

    private var client: AIClient!
    private var mockSession: URLSession!
    private var mockProtocol: MockURLProtocol.Type!

    /// 1×1 pixel JPEG for valid image tests.
    private var validJPEGData: Data {
        // Minimal valid JPEG data (1×1 red pixel).
        let base64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYI5QkY2OjsrGiwtLS0yQ1RlRFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6err8/T19vf4+fr/2gAMAwEAAhEDEQA/APn+iiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAP/Z"
        return Data(base64Encoded: base64) ?? Data([0xFF, 0xD8, 0xFF, 0xE0])
    }

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        client = AIClient(session: mockSession)
    }

    override func tearDown() {
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseHeaders = nil
        MockURLProtocol.responseError = nil
        client = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Input Validation

    func test_analyze_withEmptyImageData_throwsInvalidImageData() async {
        do {
            _ = try await client.analyze(
                image: Data(),
                provider: .claude,
                apiKey: "sk-ant-test",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.invalidImageData {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_analyze_withEmptyAPIKey_throwsMissingAPIKey() async {
        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .claude,
                apiKey: "",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.missingAPIKey(let provider) {
            XCTAssertEqual(provider, .claude)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_analyze_withWhitespaceOnlyAPIKey_throwsMissingAPIKey() async {
        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .openAI,
                apiKey: "   \n  ",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.missingAPIKey(let provider) {
            XCTAssertEqual(provider, .openAI)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Claude Response Parsing

    func test_claude_parsesValidResponse() async throws {
        // Stub a successful Claude response.
        let responseJSON = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "content": [
                {
                    "type": "text",
                    "text": "This screen shows a SwiftUI Xcode project with a main app file."
                }
            ],
            "model": "claude-sonnet-4-20250514",
            "stop_reason": "end_turn"
        }
        """
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let result = try await client.analyze(
            image: validJPEGData,
            provider: .claude,
            apiKey: "sk-ant-test",
            question: "What's on this screen?"
        )

        XCTAssertTrue(result.contains("SwiftUI"), "Response should mention SwiftUI")
        XCTAssertTrue(result.contains("Xcode"), "Response should mention Xcode")
    }

    func test_claude_usesCorrectHeaders() async throws {
        let responseJSON = """
        {"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"OK"}]}
        """
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        _ = try await client.analyze(
            image: validJPEGData,
            provider: .claude,
            apiKey: "sk-ant-test-key",
            question: nil
        )

        // Verify the request was made to the correct URL.
        let request = MockURLProtocol.lastRequest
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test-key")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    // MARK: - OpenAI Response Parsing

    func test_openAI_parsesValidResponse() async throws {
        let responseJSON = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "gpt-4o",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "This appears to be a terminal window running a build command."
                    },
                    "finish_reason": "stop"
                }
            ]
        }
        """
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let result = try await client.analyze(
            image: validJPEGData,
            provider: .openAI,
            apiKey: "sk-test-key",
            question: "Describe this"
        )

        XCTAssertTrue(result.contains("terminal"), "Response should mention terminal")
        XCTAssertTrue(result.contains("build"), "Response should mention build")
    }

    func test_openAI_usesBearerAuth() async throws {
        let responseJSON = """
        {"id":"1","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}
        """
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        _ = try await client.analyze(
            image: validJPEGData,
            provider: .openAI,
            apiKey: "sk-my-openai-key",
            question: nil
        )

        let request = MockURLProtocol.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-my-openai-key")
    }

    // MARK: - Gemini Response Parsing

    func test_gemini_parsesValidResponse() async throws {
        let responseJSON = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": "This screen shows Google Chrome with a GitHub repository page."
                            }
                        ],
                        "role": "model"
                    },
                    "finishReason": "STOP"
                }
            ]
        }
        """
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let result = try await client.analyze(
            image: validJPEGData,
            provider: .gemini,
            apiKey: "gemini-test-key",
            question: "What do you see?"
        )

        XCTAssertTrue(result.contains("GitHub"), "Response should mention GitHub")
        XCTAssertTrue(result.contains("Chrome"), "Response should mention Chrome")
    }

    func test_gemini_includesAPIKeyInURL() async throws {
        let responseJSON = """
        {"candidates":[{"content":{"parts":[{"text":"OK"}],"role":"model"},"finishReason":"STOP"}]}
        """
        MockURLProtocol.responseData = responseJSON.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        _ = try await client.analyze(
            image: validJPEGData,
            provider: .gemini,
            apiKey: "gem-api-key-12345",
            question: nil
        )

        let request = MockURLProtocol.lastRequest
        XCTAssertNotNil(request)
        let urlString = request?.url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("gem-api-key-12345"), "Gemini API key should be in URL query")
        XCTAssertTrue(urlString.contains("generativelanguage.googleapis.com"), "Should hit Google API")
    }

    // MARK: - HTTP Error Handling

    func test_httpError_401_throwsUnauthorized() async throws {
        MockURLProtocol.responseData = "{\"error\":{\"message\":\"Invalid API key\"}}".data(using: .utf8)
        MockURLProtocol.responseStatusCode = 401

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .claude,
                apiKey: "bad-key",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.httpError(let statusCode, _) {
            XCTAssertEqual(statusCode, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_httpError_429_throwsRateLimited() async throws {
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseStatusCode = 429

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .openAI,
                apiKey: "sk-test",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.rateLimited {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_httpError_429_withRetryAfterHeader() async throws {
        // Verify the Retry-After header is parsed and surfaced in the error.
        MockURLProtocol.responseData = Data()
        MockURLProtocol.responseStatusCode = 429
        MockURLProtocol.responseHeaders = ["Retry-After": "30"]

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .openAI,
                apiKey: "sk-test",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 30, "Retry-After header should be parsed as 30s")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_httpError_500_throwsServerError() async throws {
        MockURLProtocol.responseData = "{}".data(using: .utf8)
        MockURLProtocol.responseStatusCode = 500

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .gemini,
                apiKey: "key",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.httpError(let statusCode, _) {
            XCTAssertEqual(statusCode, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Malformed Response Handling

    func test_claude_malformedResponse_throwsUnexpectedResponse() async {
        MockURLProtocol.responseData = "{\"id\":\"msg_1\",\"content\":[]}".data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .claude,
                apiKey: "sk-ant-test",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.unexpectedResponse {
            // Expected — content array is empty
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_openAI_malformedResponse_throwsUnexpectedResponse() async {
        MockURLProtocol.responseData = "{}".data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .openAI,
                apiKey: "sk-test",
                question: nil
            )
            XCTFail("Expected error")
        } catch AIClientError.unexpectedResponse {
            // Expected — missing choices array
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Default Prompt

    func test_usesDefaultPrompt_whenQuestionIsNil() async throws {
        // Capture the request body to verify the prompt text.
        MockURLProtocol.responseData = """
        {"id":"msg","type":"message","role":"assistant","content":[{"type":"text","text":"Got it"}]}
        """.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        _ = try await client.analyze(
            image: validJPEGData,
            provider: .claude,
            apiKey: "sk-ant-test",
            question: nil
        )

        // Verify the request body contains the default prompt.
        guard let body = MockURLProtocol.lastRequestBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let content = messages.first?["content"] as? [[String: Any]] else {
            XCTFail("Could not parse request body")
            return
        }

        // Find the text content block.
        let textBlocks = content.filter { ($0["type"] as? String) == "text" }
        XCTAssertFalse(textBlocks.isEmpty, "Should contain a text content block")

        let text = textBlocks.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("Describe"), "Default prompt should be descriptive")
    }

    // MARK: - Custom Question

    func test_customQuestion_sentInRequestBody() async throws {
        // Stub a Claude response.
        MockURLProtocol.responseData = """
        {"id":"msg","type":"message","role":"assistant","content":[{"type":"text","text":"Yes, it is a login page."}]}
        """.data(using: .utf8)
        MockURLProtocol.responseStatusCode = 200

        let customQuestion = "Is this a login page?"

        _ = try await client.analyze(
            image: validJPEGData,
            provider: .claude,
            apiKey: "sk-ant-test",
            question: customQuestion
        )

        // Verify the custom question appears in the request body.
        guard let body = MockURLProtocol.lastRequestBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let content = messages.first?["content"] as? [[String: Any]] else {
            XCTFail("Could not parse request body")
            return
        }

        let textBlocks = content.filter { ($0["type"] as? String) == "text" }
        let text = textBlocks.first?["text"] as? String ?? ""
        XCTAssertEqual(text, customQuestion,
                       "Custom question should be sent verbatim in request body")
    }

    // MARK: - Network Error

    func test_networkError_propagatesFromURLSession() async {
        // Simulate a network connectivity failure (e.g., no internet).
        // URLSession wraps URLProtocol errors as URLError.
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                              userInfo: [NSLocalizedDescriptionKey: "No internet connection"])
        MockURLProtocol.responseError = nsError

        do {
            _ = try await client.analyze(
                image: validJPEGData,
                provider: .claude,
                apiKey: "sk-ant-test",
                question: nil
            )
            XCTFail("Expected error")
        } catch {
            // URLSession wraps URLProtocol errors; the error propagates directly.
            // Verify it's a URLError with the expected code.
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.domain, NSURLErrorDomain,
                           "Error should be from URL loading system")
            XCTAssertEqual(nsErr.code, NSURLErrorNotConnectedToInternet,
                           "Error should indicate no internet connection")
        }
    }

    // MARK: - AIClientError Error Description

    func test_errorDescription_missingAPIKey_containsProviderName() {
        let error = AIClientError.missingAPIKey(.claude)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Claude"), "Error should name the provider")
        XCTAssertTrue(desc.contains("API key"), "Error should mention API key")
    }

    func test_errorDescription_missingAPIKey_geminiProvider() {
        let error = AIClientError.missingAPIKey(.gemini)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Gemini"), "Error should name Gemini")
    }

    func test_errorDescription_missingAPIKey_openAIProvider() {
        let error = AIClientError.missingAPIKey(.openAI)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("OpenAI"), "Error should name OpenAI")
    }

    func test_errorDescription_invalidImageData() {
        let error = AIClientError.invalidImageData
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Invalid image"), "Error should mention invalid image")
    }

    func test_errorDescription_httpError_containsStatusCode() {
        let error = AIClientError.httpError(statusCode: 503, body: "Service Unavailable")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("503"), "Error should include status code")
        XCTAssertTrue(desc.contains("Service Unavailable"), "Error should include body")
    }

    func test_errorDescription_httpError_404() {
        let error = AIClientError.httpError(statusCode: 404, body: "Not Found")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("404"), "Error should include 404")
    }

    func test_errorDescription_rateLimited_withoutRetryAfter() {
        let error = AIClientError.rateLimited(retryAfter: nil)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Rate limited"), "Error should mention rate limiting")
        XCTAssertTrue(desc.contains("wait"), "Error should suggest waiting")
    }

    func test_errorDescription_rateLimited_withRetryAfter() {
        let error = AIClientError.rateLimited(retryAfter: 45)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Rate limited"), "Error should mention rate limiting")
        XCTAssertTrue(desc.contains("45"), "Error should include retry-after seconds")
    }

    func test_errorDescription_unexpectedResponse() {
        let error = AIClientError.unexpectedResponse("Missing field 'choices'")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Unexpected"), "Error should mention unexpected response")
        XCTAssertTrue(desc.contains("choices"), "Error should include detail")
    }

    func test_errorDescription_networkError() {
        let error = AIClientError.networkError(underlying: "The request timed out")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("Network"), "Error should mention network")
        XCTAssertTrue(desc.contains("timed out"), "Error should include underlying message")
    }
}

// MARK: - MockURLProtocol

/// URLProtocol subclass that intercepts all HTTP requests for testing.
/// Allows tests to stub responses without network access.
final class MockURLProtocol: URLProtocol {
    /// Stub response data for the next request.
    static var responseData: Data?
    /// Stub HTTP status code.
    static var responseStatusCode: Int = 200
    /// Stub response headers (e.g., Retry-After for 429 tests).
    static var responseHeaders: [String: String]?
    /// Stub error for the next request.
    static var responseError: Error?
    /// Captured last request for assertion.
    static var lastRequest: URLRequest?
    /// Captured last request body.
    static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastRequestBody = request.httpBody

        if let error = MockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: MockURLProtocol.responseHeaders
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
