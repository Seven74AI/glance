import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AIProvider

final class AIResponseTests: XCTestCase {
    func testAIResponseInitialization() {
        let response = AIResponse(text: "I can see a code editor.", modelUsed: "claude-sonnet-4-20250514", latencyMs: 1250)
        XCTAssertEqual(response.text, "I can see a code editor.")
        XCTAssertEqual(response.modelUsed, "claude-sonnet-4-20250514")
        XCTAssertEqual(response.latencyMs, 1250)
    }

    func testEmptyText() {
        let response = AIResponse(text: "", modelUsed: "gpt-4o", latencyMs: 500)
        XCTAssertEqual(response.text, "")
    }

    func testZeroLatency() {
        let response = AIResponse(text: "fast", modelUsed: "gemini-2.5-flash", latencyMs: 0)
        XCTAssertEqual(response.latencyMs, 0)
    }
}

final class ProviderErrorTests: XCTestCase {
    func testUnauthorizedEquality() {
        XCTAssertEqual(ProviderError.unauthorized("bad"), ProviderError.unauthorized("bad"))
        XCTAssertNotEqual(ProviderError.unauthorized("bad"), ProviderError.unauthorized("diff"))
    }

    func testRateLimitedWithSeconds() {
        if case .rateLimited(let s) = ProviderError.rateLimited(retryAfterSeconds: 60) {
            XCTAssertEqual(s, 60)
        } else { XCTFail() }
    }

    func testRateLimitedWithoutSeconds() {
        if case .rateLimited(let s) = ProviderError.rateLimited(retryAfterSeconds: nil) {
            XCTAssertNil(s)
        } else { XCTFail() }
    }

    func testNetworkTimeoutEquality() {
        XCTAssertEqual(ProviderError.networkTimeout, .networkTimeout)
    }

    func testServerErrorFields() {
        if case .serverError(let code, let msg) = ProviderError.serverError(statusCode: 500, message: "boom") {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(msg, "boom")
        } else { XCTFail() }
    }

    func testInvalidResponse() {
        if case .invalidResponse(let msg) = ProviderError.invalidResponse("missing") {
            XCTAssertEqual(msg, "missing")
        } else { XCTFail() }
    }

    func testConfigurationError() {
        if case .configurationError(let msg) = ProviderError.configurationError("unknown provider") {
            XCTAssertEqual(msg, "unknown provider")
        } else { XCTFail() }
    }
}
