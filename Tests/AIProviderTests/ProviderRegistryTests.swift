import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AIProvider

final class ProviderRegistryTests: XCTestCase {
    var config: AIProviderConfiguration!
    var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        config = AIProviderConfiguration(
            providers: [
                "claude": ProviderConfig(apiKey: "sk-ant-test123", model: "claude-sonnet-4-20250514"),
                "openai": ProviderConfig(apiKey: "sk-test456", model: "gpt-4o"),
                "gemini": ProviderConfig(apiKey: "gemini-key789", model: "gemini-2.5-flash")
            ],
            defaultProvider: "claude"
        )
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: cfg)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        mockSession = nil
        config = nil
        super.tearDown()
    }

    func testRegistryLoadsAllProviders() throws {
        let registry = try ProviderRegistry(config: config, session: mockSession)
        XCTAssertEqual(registry.availableProviderIDs.sorted(), ["claude", "gemini", "openai"])
        XCTAssertEqual(registry.defaultProviderID, "claude")
    }

    func testDefaultProviderAccessible() throws {
        let registry = try ProviderRegistry(config: config, session: mockSession)
        XCTAssertEqual(registry.defaultProvider?.name, "Claude")
    }

    func testProviderById() throws {
        let registry = try ProviderRegistry(config: config, session: mockSession)
        XCTAssertEqual(registry.provider(id: "claude")?.name, "Claude")
        XCTAssertEqual(registry.provider(id: "openai")?.name, "OpenAI")
        XCTAssertEqual(registry.provider(id: "gemini")?.name, "Gemini")
        XCTAssertNil(registry.provider(id: "azure"))
    }

    func testInvalidApiKeyRejected() {
        let badConfig = AIProviderConfiguration(
            providers: ["claude": ProviderConfig(apiKey: "sk-...", model: "x")],
            defaultProvider: "claude"
        )
        XCTAssertThrowsError(try ProviderRegistry(config: badConfig, session: mockSession)) { error in
            if case ProviderError.configurationError(let msg) = error {
                XCTAssertTrue(msg.contains("placeholder"))
            } else { XCTFail("Expected configurationError") }
        }
    }

    func testEmptyApiKeyRejected() {
        let badConfig = AIProviderConfiguration(
            providers: ["openai": ProviderConfig(apiKey: "", model: "gpt-4o")],
            defaultProvider: "openai"
        )
        XCTAssertThrowsError(try ProviderRegistry(config: badConfig, session: mockSession))
    }

    func testMissingDefaultProvider() {
        let badConfig = AIProviderConfiguration(
            providers: ["claude": ProviderConfig(apiKey: "sk-ant-real", model: "x")],
            defaultProvider: "openai"
        )
        XCTAssertThrowsError(try ProviderRegistry(config: badConfig, session: mockSession)) { error in
            if case ProviderError.configurationError(let msg) = error {
                XCTAssertTrue(msg.contains("not found"))
            } else { XCTFail("Expected configurationError") }
        }
    }

    func testUnknownProviderType() {
        let badConfig = AIProviderConfiguration(
            providers: ["azure": ProviderConfig(apiKey: "key123", model: "gpt-4")],
            defaultProvider: "azure"
        )
        XCTAssertThrowsError(try ProviderRegistry(config: badConfig, session: mockSession)) { error in
            if case ProviderError.configurationError(let msg) = error {
                XCTAssertTrue(msg.contains("Unknown provider"))
            } else { XCTFail("Expected configurationError") }
        }
    }

    func testConfigDecodingFromJSON() throws {
        let json = """
        {"providers":{"claude":{"apiKey":"sk-ant-key","model":"claude-sonnet-4-20250514"},"openai":{"apiKey":"sk-key","model":"gpt-4o"}},"defaultProvider":"claude"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIProviderConfiguration.self, from: json)
        XCTAssertEqual(decoded.providers.count, 2)
        XCTAssertEqual(decoded.providers["claude"]?.apiKey, "sk-ant-key")
        XCTAssertEqual(decoded.defaultProvider, "claude")
    }

    func testFromConfigFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configURL = tempDir.appendingPathComponent("ai-providers-test.json")
        let json = """
        {"providers":{"claude":{"apiKey":"sk-ant-key","model":"claude-sonnet-4-20250514"}},"defaultProvider":"claude"}
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let registry = try ProviderRegistry.fromConfigFile(at: configURL, session: mockSession)
        XCTAssertEqual(registry.defaultProviderID, "claude")
    }
}
