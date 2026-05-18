import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AIProvider

final class OpenAIProviderTests: XCTestCase {
    var mockSession: URLSession!
    var testJPEGData: Data!

    override func setUp() {
        super.setUp()
        testJPEGData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01])
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
        let expectedText = "I can see an IDE with Swift code."
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 200,
                body: ["choices": [["message": ["content": expectedText]]], "model": "gpt-4o"])
        }
        let provider = OpenAIProvider(apiKey: "sk-test123", model: "gpt-4o", session: mockSession)
        let response = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
        XCTAssertEqual(response.text, expectedText)
    }

    func testCustomPrompt() async throws {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 200,
                body: ["choices": [["message": ["content": "SwiftUI"]]], "model": "gpt-4o"])
        }
        let provider = OpenAIProvider(apiKey: "sk-test123", model: "gpt-4o", session: mockSession)
        let response = try await provider.analyze(screenshot: testJPEGData, prompt: "What framework?")
        XCTAssertEqual(response.text, "SwiftUI")
    }

    func testUnauthorizedError() async {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 401,
                body: ["error": ["message": "Incorrect API key"]])
        }
        let provider = OpenAIProvider(apiKey: "bad-key", model: "gpt-4o", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .unauthorized(let msg) = error { XCTAssertTrue(msg.contains("Incorrect API key")) }
            else { XCTFail("Expected unauthorized") }
        } catch { XCTFail("Unexpected: \(error)") }
    }

    func testRateLimitedError() async {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "15"])!
            return (resp, Data())
        }
        let provider = OpenAIProvider(apiKey: "sk-test123", model: "gpt-4o", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .rateLimited(let seconds) = error { XCTAssertEqual(seconds, 15) }
            else { XCTFail("Expected rateLimited") }
        } catch { XCTFail("Unexpected: \(error)") }
    }

    func testServerError() async {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 503,
                body: ["error": ["message": "Service unavailable"]])
        }
        let provider = OpenAIProvider(apiKey: "sk-test123", model: "gpt-4o", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .serverError(let code, let msg) = error {
                XCTAssertEqual(code, 503); XCTAssertEqual(msg, "Service unavailable")
            } else { XCTFail("Expected serverError") }
        } catch { XCTFail("Unexpected: \(error)") }
    }
}
