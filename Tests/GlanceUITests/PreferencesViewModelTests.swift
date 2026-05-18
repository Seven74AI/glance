import XCTest
@testable import GlanceUI

/// TDD: PreferencesViewModel tests — provider selection, API key storage, privacy toggles
final class PreferencesViewModelTests: XCTestCase {

    var viewModel: PreferencesViewModel!

    override func setUp() {
        super.setUp()
        viewModel = PreferencesViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func test_default_ai_provider_is_claude() {
        XCTAssertEqual(viewModel.selectedProvider, .claude)
    }

    func test_default_capture_mode_is_window_under_cursor() {
        XCTAssertEqual(viewModel.defaultCaptureMode, .windowUnderCursor)
    }

    func test_preview_before_send_is_enabled_by_default() {
        XCTAssertTrue(viewModel.previewBeforeSend)
    }

    func test_auto_send_is_disabled_by_default() {
        XCTAssertFalse(viewModel.autoSend)
    }

    // MARK: - Provider Selection

    func test_selecting_gpt_updates_provider() {
        viewModel.selectedProvider = .openAI
        XCTAssertEqual(viewModel.selectedProvider, .openAI)
    }

    func test_selecting_gemini_updates_provider() {
        viewModel.selectedProvider = .gemini
        XCTAssertEqual(viewModel.selectedProvider, .gemini)
    }

    func test_selecting_claude_updates_provider() {
        viewModel.selectedProvider = .openAI
        viewModel.selectedProvider = .claude
        XCTAssertEqual(viewModel.selectedProvider, .claude)
    }

    func test_all_providers_are_available() {
        let providers = AIProvider.allCases
        XCTAssertEqual(providers.count, 3)
        XCTAssertTrue(providers.contains(.claude))
        XCTAssertTrue(providers.contains(.openAI))
        XCTAssertTrue(providers.contains(.gemini))
    }

    // MARK: - Provider Labels

    func test_claude_label() {
        viewModel.selectedProvider = .claude
        XCTAssertEqual(viewModel.selectedProvider.displayName, "Claude (Anthropic)")
    }

    func test_openai_label() {
        viewModel.selectedProvider = .openAI
        XCTAssertEqual(viewModel.selectedProvider.displayName, "GPT-4V (OpenAI)")
    }

    func test_gemini_label() {
        viewModel.selectedProvider = .gemini
        XCTAssertEqual(viewModel.selectedProvider.displayName, "Gemini (Google)")
    }

    // MARK: - API Key Management

    func test_api_key_starts_empty() {
        XCTAssertEqual(viewModel.apiKey, "")
    }

    func test_api_key_can_be_set() {
        viewModel.apiKey = "sk-ant-api03-test-key"
        XCTAssertEqual(viewModel.apiKey, "sk-ant-api03-test-key")
    }

    func test_api_key_changes_when_provider_changes() {
        // Set key for Claude
        viewModel.selectedProvider = .claude
        viewModel.apiKey = "claude-key-123"

        // Switch to OpenAI — key should reload (empty if not set)
        viewModel.selectedProvider = .openAI
        XCTAssertEqual(viewModel.apiKey, "", "API key should reload for new provider")
    }

    func test_has_api_key_returns_false_when_empty() {
        viewModel.apiKey = ""
        XCTAssertFalse(viewModel.hasAPIKey)
    }

    func test_has_api_key_returns_true_when_set() {
        viewModel.apiKey = "sk-valid-key"
        XCTAssertTrue(viewModel.hasAPIKey)
    }

    // MARK: - Capture Mode Default

    func test_default_capture_mode_can_be_window() {
        viewModel.defaultCaptureMode = .windowUnderCursor
        XCTAssertEqual(viewModel.defaultCaptureMode, .windowUnderCursor)
    }

    func test_default_capture_mode_can_be_region() {
        viewModel.defaultCaptureMode = .drawRegion
        XCTAssertEqual(viewModel.defaultCaptureMode, .drawRegion)
    }

    func test_default_capture_mode_can_be_full_screen() {
        viewModel.defaultCaptureMode = .fullScreen
        XCTAssertEqual(viewModel.defaultCaptureMode, .fullScreen)
    }

    // MARK: - Privacy Toggles

    func test_preview_before_send_can_be_disabled() {
        viewModel.previewBeforeSend = false
        XCTAssertFalse(viewModel.previewBeforeSend)
    }

    func test_auto_send_can_be_enabled() {
        viewModel.autoSend = true
        XCTAssertTrue(viewModel.autoSend)
    }

    func test_preview_before_send_can_be_toggled() {
        viewModel.previewBeforeSend = false
        XCTAssertFalse(viewModel.previewBeforeSend)
        viewModel.previewBeforeSend = true
        XCTAssertTrue(viewModel.previewBeforeSend)
    }

    // MARK: - Validation

    func test_is_valid_returns_false_when_no_api_key() {
        viewModel.apiKey = ""
        XCTAssertFalse(viewModel.isValid)
    }

    func test_is_valid_returns_true_when_api_key_set() {
        viewModel.apiKey = "sk-anything"
        XCTAssertTrue(viewModel.isValid)
    }

    // MARK: - Keychain Persistence (mock)

    func test_save_credentials_does_not_throw() {
        viewModel.apiKey = "sk-test-key"
        // In test mode, saveCredentials should not crash
        viewModel.saveCredentials()
        // No assertion needed — just verifying no crash
    }

    func test_load_credentials_does_not_throw_on_first_load() {
        // First load should not crash even if nothing saved
        viewModel.loadCredentials()
        // Defaults should remain
        XCTAssertEqual(viewModel.selectedProvider, .claude)
    }
}
