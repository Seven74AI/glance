import XCTest
import Foundation
import GlanceUI
import AIProvider
@testable import GlanceApp

// MARK: - SessionCoordinator Tests (TDD: RED phase)

/// Tests for the SessionCoordinator — state machine orchestration, provider bridging, flow control.
final class SessionCoordinatorTests: XCTestCase {

    // MARK: - Initialization

    func test_coordinator_initialState_isIdle() {
        let config = GlanceConfig.defaultConfig
        let coordinator = SessionCoordinator(config: config)
        XCTAssertEqual(coordinator.currentState, .idle)
        XCTAssertFalse(coordinator.isActive)
    }

    func test_coordinator_requiresNonEmptyConfig() {
        // Empty providers should fail gracefully.
        var config = GlanceConfig.defaultConfig
        config.providers = [:]
        let coordinator = SessionCoordinator(config: config)
        // Should still initialize — validation happens at capture time.
        XCTAssertEqual(coordinator.currentState, .idle)
    }

    // MARK: - Provider Resolution

    func test_coordinator_resolvesClaudeProvider() {
        var config = GlanceConfig.defaultConfig
        config.defaultProvider = "claude"
        config.providers["claude"] = ProviderConfig(apiKey: "sk-ant-real", model: "claude-sonnet-4-20250514")
        let coordinator = SessionCoordinator(config: config)

        // Map GlanceUI.AIProvider to AIProvider module provider ID.
        let providerID = coordinator.resolveProviderID(for: .claude)
        XCTAssertEqual(providerID, "claude")
    }

    func test_coordinator_resolvesOpenAIProvider() {
        var config = GlanceConfig.defaultConfig
        config.defaultProvider = "openai"
        config.providers["openai"] = ProviderConfig(apiKey: "sk-real", model: "gpt-4o")
        let coordinator = SessionCoordinator(config: config)

        let providerID = coordinator.resolveProviderID(for: .openAI)
        XCTAssertEqual(providerID, "openai")
    }

    func test_coordinator_resolvesGeminiProvider() {
        var config = GlanceConfig.defaultConfig
        config.defaultProvider = "gemini"
        config.providers["gemini"] = ProviderConfig(apiKey: "gem-real", model: "gemini-2.5-flash")
        let coordinator = SessionCoordinator(config: config)

        let providerID = coordinator.resolveProviderID(for: .gemini)
        XCTAssertEqual(providerID, "gemini")
    }

    // MARK: - Config Change Handling

    func test_coordinator_switchProvider_updatesResolution() {
        var config = GlanceConfig.defaultConfig
        config.defaultProvider = "claude"
        config.providers["claude"] = ProviderConfig(apiKey: "sk-ant-key", model: "claude-sonnet-4-20250514")
        config.providers["openai"] = ProviderConfig(apiKey: "sk-oai-key", model: "gpt-4o")
        let coordinator = SessionCoordinator(config: config)

        XCTAssertEqual(coordinator.resolveProviderID(for: .claude), "claude")
        XCTAssertEqual(coordinator.resolveProviderID(for: .openAI), "openai")
    }
}
