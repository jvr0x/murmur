import Foundation

/// Known OpenAI-compatible LLM backends, used to prefill the cleanup endpoint in Settings.
///
/// This is a presentation-layer convenience only: the persisted source of truth remains
/// ``AppConfig/llmBaseURL``. The selected provider is *derived* from that URL via
/// ``detect(from:)``, so there is no separate stored state to keep in sync.
public enum LLMProvider: String, CaseIterable, Identifiable, Sendable {
    /// Ollama's local OpenAI-compatible server.
    case ollama
    /// LM Studio's local OpenAI-compatible server.
    case lmStudio
    /// Any other endpoint; the user edits the URL directly.
    case custom

    /// Stable identity for SwiftUI pickers.
    public var id: String { rawValue }

    /// Human-readable name shown in the picker.
    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .custom: return "Custom"
        }
    }

    /// The default base URL for this provider, or `nil` for ``custom``.
    public var defaultBaseURL: String? {
        switch self {
        case .ollama: return "http://localhost:11434/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .custom: return nil
        }
    }

    /// Detects the provider implied by a base URL, falling back to ``custom``.
    /// - Parameter baseURL: The currently configured LLM base URL.
    /// - Returns: The matching known provider, or ``custom`` if none matches.
    public static func detect(from baseURL: String) -> LLMProvider {
        let normalized = baseURL.trimmingCharacters(in: .whitespaces)
        for provider in LLMProvider.allCases {
            if let url = provider.defaultBaseURL, url == normalized { return provider }
        }
        return .custom
    }
}
