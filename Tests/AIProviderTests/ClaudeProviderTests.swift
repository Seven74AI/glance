import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AIProvider

final class ClaudeProviderTests: XCTestCase {
    var mockSession: URLSession!
    var testPNGData: Data!

    override func setUp() {
        super.setUp()
        testPNGData = createMinimalPNG()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        mockSession = nil
        super.tearDown()
    }

    func testSuccessfulAnalysis() async throws {
        let expectedText = "I can see a terminal window with some code."
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return MockURLProtocol.makeResponse(
                url: request.url!, statusCode: 200,
                body: [
                    "id": "msg_123", "type": "message", "role": "assistant",
                    "content": [["type": "text", "text": expectedText]],
                    "model": "claude-sonnet-4-20250514", "stop_reason": "end_turn"
                ]
            )
        }

        let provider = ClaudeProvider(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", session: mockSession)
        let response = try await provider.analyze(screenshot: testPNGData, prompt: nil)
        XCTAssertEqual(response.text, expectedText)
    }

    func testCustomPrompt() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.makeResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!, statusCode: 200,
                body: ["content": [["type": "text", "text": "Swift"]], "model": "claude-sonnet-4-20250514"])
        }
        let provider = ClaudeProvider(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", session: mockSession)
        let response = try await provider.analyze(screenshot: testPNGData, prompt: "What language?")
        XCTAssertEqual(response.text, "Swift")
    }

    func testMultipleContentBlocksResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.makeResponse(url: URL(string: "https://api.anthropic.com/v1/messages")!, statusCode: 200,
                body: ["content": [["type": "text", "text": "Part 1."], ["type": "text", "text": "Part 2."]], "model": "x"])
        }
        let provider = ClaudeProvider(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", session: mockSession)
        let response = try await provider.analyze(screenshot: testPNGData, prompt: nil)
        XCTAssertEqual(response.text, "Part 1.\nPart 2.")
    }

    func testUnauthorizedError() async {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 401,
                body: ["error": ["type": "authentication_error", "message": "Invalid API key"]])
        }
        let provider = ClaudeProvider(apiKey: "bad-key", model: "claude-sonnet-4-20250514", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testPNGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .unauthorized(let msg) = error { XCTAssertTrue(msg.contains("Invalid API key")) }
            else { XCTFail("Expected unauthorized, got \(error)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRateLimitedWithRetryAfter() async {
        MockURLProtocol.requestHandler = { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "30"])!
            return (response, Data())
        }
        let provider = ClaudeProvider(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testPNGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .rateLimited(let seconds) = error { XCTAssertEqual(seconds, 30) }
            else { XCTFail("Expected rateLimited, got \(error)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testServerError() async {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 500,
                body: ["error": ["message": "Internal server error"]])
        }
        let provider = ClaudeProvider(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testPNGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .serverError(let code, let msg) = error {
                XCTAssertEqual(code, 500); XCTAssertEqual(msg, "Internal server error")
            } else { XCTFail("Expected serverError, got \(error)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func createMinimalPNG() -> Data {
        Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 104, 0, 0, 0, 130, 0, 129, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130])
    }
}
