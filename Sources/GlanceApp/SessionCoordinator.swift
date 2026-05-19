import Foundation
import GlanceUI
import AIProvider

// MARK: - SessionCoordinator

/// Central coordinator that orchestrates the Glance capture→AI→response pipeline.
///
/// Responsibilities:
/// - Manages the Config → ProviderRegistry lifecycle
/// - Bridges GlanceUI.AIProvider enum ↔ AIProvider.AIProvider protocol
/// - Tracks active capture state
/// - Validates provider configuration on demand
///
/// This replaces/reduces the inline coordination in GlanceApp.swift,
/// providing a single entry point for the full capture flow.
@MainActor
public final class SessionCoordinator: ObservableObject {

    // MARK: - Published State

    /// The current UX state (mirrors the StateMachineViewModel for convenience).
    @Published public private(set) var currentState: UXState = .idle

    /// Whether a capture session is currently active.
    @Published public private(set) var isActive: Bool = false

    // MARK: - Configuration

    /// The loaded application configuration.
    public let config: GlanceConfig

    // MARK: - Provider Registry

    /// The AI provider registry, initialized from config.
    /// Nil if no valid providers are configured (no API keys set).
    public private(set) var providerRegistry: ProviderRegistry?

    // MARK: - Initialization

    /// Creates a session coordinator from a GlanceConfig.
    /// - Parameter config: The application configuration.
    public init(config: GlanceConfig) {
        self.config = config

        // Initialize ProviderRegistry from config if possible.
        do {
            let aiConfig = try config.toAIProviderConfiguration()
            self.providerRegistry = try? ProviderRegistry(
                config: aiConfig,
                session: .shared
            )
        }
    }

    // MARK: - Provider Resolution

    /// Maps a GlanceUI.AIProvider enum to the AIProvider module's provider ID string.
    /// - Parameter provider: The UI-level provider enum value.
    /// - Returns: The corresponding provider ID for the ProviderRegistry.
    public func resolveProviderID(for provider: GlanceUI.AIProvider) -> String {
        switch provider {
        case .claude: return "claude"
        case .openAI: return "openai"
        case .gemini:  return "gemini"
        }
    }

    /// Resolves a GlanceUI.AIProvider to an AIProvider.AIProvider instance.
    /// - Parameter provider: The UI-level provider enum value.
    /// - Returns: The AI provider instance, or nil if not configured.
    public func resolveProvider(for provider: GlanceUI.AIProvider) -> AIProvider.AIProvider? {
        let id = resolveProviderID(for: provider)
        return providerRegistry?.provider(id: id)
    }

    // MARK: - Session State

    /// Mark the session as active.
    public func beginSession() {
        isActive = true
        currentState = .selecting
    }

    /// Mark the session as ended.
    public func endSession() {
        isActive = false
        currentState = .idle
    }

    /// Update the current UX state (called by the pipeline as flow progresses).
    public func updateState(_ newState: UXState) {
        currentState = newState
        if newState == .idle {
            isActive = false
        }
    }
}
