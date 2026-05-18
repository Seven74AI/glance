import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AIProvider

final class GeminiProviderTests: XCTestCase {
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
        let expectedText = "This appears to be a macOS desktop."
        MockURLProtocol.requestHandler = { req in
            XCTAssertTrue(req.url!.absoluteString.contains("gemini-2.5-flash"))
            return MockURLProtocol.makeResponse(url: req.url!, statusCode: 200,
                body: ["candidates": [["content": ["parts": [["text": expectedText]]]]]])
        }
        let provider = GeminiProvider(apiKey: "test-gemini-key", model: "gemini-2.5-flash", session: mockSession)
        let response = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
        XCTAssertEqual(response.text, expectedText)
    }

    func testCustomPrompt() async throws {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 200,
                body: ["candidates": [["content": ["parts": [["text": "Python"]]]]]])
        }
        let provider = GeminiProvider(apiKey: "test-gemini-key", model: "gemini-2.5-flash", session: mockSession)
        let response = try await provider.analyze(screenshot: testJPEGData, prompt: "What language?")
        XCTAssertEqual(response.text, "Python")
    }

    func testMultiplePartsResponse() async throws {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 200,
                body: ["candidates": [["content": ["parts": [["text": "Line 1."], ["text": "Line 2."]]]]]])
        }
        let provider = GeminiProvider(apiKey: "test-gemini-key", model: "gemini-2.5-flash", session: mockSession)
        let response = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
        XCTAssertEqual(response.text, "Line 1.\nLine 2.")
    }

    func testUnauthorizedError() async {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 401,
                body: ["error": ["message": "API key not valid"]])
        }
        let provider = GeminiProvider(apiKey: "bad-key", model: "gemini-2.5-flash", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .unauthorized(let msg) = error { XCTAssertTrue(msg.contains("API key not valid")) }
            else { XCTFail("Expected unauthorized") }
        } catch { XCTFail("Unexpected: \(error)") }
    }

    func testRateLimitedError() async {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "45"])!
            return (resp, Data())
        }
        let provider = GeminiProvider(apiKey: "test-gemini-key", model: "gemini-2.5-flash", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .rateLimited(let seconds) = error { XCTAssertEqual(seconds, 45) }
            else { XCTFail("Expected rateLimited") }
        } catch { XCTFail("Unexpected: \(error)") }
    }

    func testServerError() async {
        MockURLProtocol.requestHandler = { req in
            MockURLProtocol.makeResponse(url: req.url!, statusCode: 500,
                body: ["error": ["message": "Internal error"]])
        }
        let provider = GeminiProvider(apiKey: "test-gemini-key", model: "gemini-2.5-flash", session: mockSession)
        do {
            _ = try await provider.analyze(screenshot: testJPEGData, prompt: nil)
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            if case .serverError(let code, let msg) = error {
                XCTAssertEqual(code, 500); XCTAssertEqual(msg, "Internal error")
            } else { XCTFail("Expected serverError") }
        } catch { XCTFail("Unexpected: \(error)") }
    }
}
