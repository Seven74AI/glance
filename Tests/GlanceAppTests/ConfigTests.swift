import XCTest
import Foundation
@testable import GlanceApp

// MARK: - GlanceConfig Tests (TDD: RED phase)

/// Tests for the GlanceConfig system — JSON load/save, defaults, masking, validation.
final class ConfigTests: XCTestCase {

    // MARK: - Properties

    private var tempDir: URL!
    private var configPath: URL!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glance-config-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configPath = tempDir.appendingPathComponent("config.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 1. Default config creation

    func test_config_defaultHasClaudeAsDefaultProvider() {
        let config = GlanceConfig.defaultConfig
        XCTAssertEqual(config.defaultProvider, "claude", "Default provider should be claude")
    }

    func test_config_defaultHasThreeProviders() {
        let config = GlanceConfig.defaultConfig
        XCTAssertEqual(config.providers.count, 3, "Should have 3 default providers")
        XCTAssertNotNil(config.providers["claude"])
        XCTAssertNotNil(config.providers["openai"])
        XCTAssertNotNil(config.providers["gemini"])
    }

    func test_config_defaultProvidersHavePlaceholderKeys() {
        let config = GlanceConfig.defaultConfig
        for (_, providerCfg) in config.providers {
            XCTAssertEqual(providerCfg.apiKey, "sk-...",
                           "Default config should use placeholder keys (safe to commit)")
        }
    }

    func test_config_defaultCaptureMode_isWindowUnderCursor() {
        let config = GlanceConfig.defaultConfig
        XCTAssertEqual(config.defaultCaptureMode, "windowUnderCursor")
    }

    func test_config_defaultShortcut_isCtrlOptionCmdG() {
        let config = GlanceConfig.defaultConfig
        XCTAssertEqual(config.keyboardShortcut, "ctrl+option+cmd+G")
    }

    // MARK: - 2. JSON serialization

    func test_config_encodeDecode_roundTrips() throws {
        // Create a config with non-default values.
        var config = GlanceConfig(
            providers: [
                "claude": ProviderConfig(apiKey: "sk-ant-real-key", model: "claude-sonnet-4-20250514"),
                "openai": ProviderConfig(apiKey: "sk-real-openai", model: "gpt-4o"),
            ],
            defaultProvider: "openai",
            defaultCaptureMode: "fullScreen",
            keyboardShortcut: "cmd+shift+G"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GlanceConfig.self, from: data)

        XCTAssertEqual(decoded.defaultProvider, "openai")
        XCTAssertEqual(decoded.defaultCaptureMode, "fullScreen")
        XCTAssertEqual(decoded.keyboardShortcut, "cmd+shift+G")
        XCTAssertEqual(decoded.providers.count, 2)
        XCTAssertEqual(decoded.providers["claude"]?.apiKey, "sk-ant-real-key")
    }

    // MARK: - 3. File load/save

    func test_config_saveToDisk_canBeLoadedBack() throws {
        var config = GlanceConfig.defaultConfig
        config.defaultProvider = "gemini"
        config.defaultCaptureMode = "region"

        try config.save(to: configPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))

        let loaded = try GlanceConfig.load(from: configPath)
        XCTAssertEqual(loaded.defaultProvider, "gemini")
        XCTAssertEqual(loaded.defaultCaptureMode, "region")
    }

    func test_config_loadFromMissingFile_createsDefault() throws {
        // Config file does not exist yet.
        let nonExistentPath = tempDir.appendingPathComponent("nonexistent.json")

        let config = try GlanceConfig.load(from: nonExistentPath)
        XCTAssertEqual(config.defaultProvider, "claude")
        // It should have created the file.
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonExistentPath.path))
    }

    // MARK: - 4. Masked API key display

    func test_config_maskedAPIKey_hidesMiddle() {
        let key = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz123456"
        let masked = GlanceConfig.maskedAPIKey(key)
        // Should show first 6 and last 4 characters, rest masked.
        XCTAssertTrue(masked.contains("sk-ant"), "Should preserve prefix")
        XCTAssertTrue(masked.contains("3456"), "Should preserve suffix")
        XCTAssertTrue(masked.contains("•"), "Should mask middle")
        XCTAssertFalse(masked.contains("abcdefghij"), "Should NOT contain middle chars")
    }

    func test_config_maskedAPIKey_shortKeys_maskedEntirely() {
        let key = "short"
        let masked = GlanceConfig.maskedAPIKey(key)
        // Keys under 8 chars get fully masked.
        XCTAssertTrue(masked.allSatisfy { $0 == "•" || $0 == "*" },
                      "Short keys should be fully masked: \(masked)")
    }

    func test_config_maskedAPIKey_emptyKey_returnsEmpty() {
        let masked = GlanceConfig.maskedAPIKey("")
        XCTAssertEqual(masked, "")
    }

    // MARK: - 5. Provider validation

    func test_config_validateProvider_knownProvider_returnsTrue() {
        let config = GlanceConfig.defaultConfig
        XCTAssertTrue(config.hasProvider("claude"))
        XCTAssertTrue(config.hasProvider("openai"))
        XCTAssertFalse(config.hasProvider("unknown-provider"))
    }

    // MARK: - 6. AIProviderConfiguration bridge

    func test_config_toAIProviderConfiguration_convertsCorrectly() throws {
        var config = GlanceConfig.defaultConfig
        config.defaultProvider = "gemini"

        let aiConfig = try config.toAIProviderConfiguration()
        XCTAssertEqual(aiConfig.defaultProvider, "gemini")
        XCTAssertEqual(aiConfig.providers.count, 3)
        XCTAssertNotNil(aiConfig.providers["claude"])
        XCTAssertEqual(aiConfig.providers["claude"]?.apiKey, "sk-...")
    }

    func test_config_toAIProviderConfiguration_throwsWhenDefaultProviderMissing() {
        var config = GlanceConfig.defaultConfig
        // Set a default provider that doesn't exist in providers.
        config.defaultProvider = "nonexistent"

        XCTAssertThrowsError(try config.toAIProviderConfiguration()) { error in
            guard case ConfigError.defaultProviderMissing(let id) = error else {
                XCTFail("Expected ConfigError.defaultProviderMissing, got \(error)")
                return
            }
            XCTAssertEqual(id, "nonexistent")
        }
    }
}
