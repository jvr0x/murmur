import Foundation

/// The speech-to-text backend kind.
public enum STTBackendKind: String, Codable, CaseIterable, Sendable {
    /// Local whisper.cpp HTTP server (`POST /inference`).
    case whisperCpp
    /// Any OpenAI-compatible server (`POST /v1/audio/transcriptions`), e.g. a remote Spark.
    case openAICompatible
}

/// How transcribed text is inserted into the frontmost app.
public enum InsertionMethod: String, Codable, CaseIterable, Sendable {
    /// Write to the pasteboard and synthesize ⌘V (fast, reliable).
    case paste
    /// Synthesize the text as Unicode keystrokes (fallback for paste-hostile apps).
    case keystroke
}

/// User-configurable application settings.
///
/// Decoding tolerates missing keys (an older or partial `config.json` still loads), with
/// any absent field falling back to ``AppConfig/default``.
public struct AppConfig: Codable, Equatable, Sendable {
    /// Which transcription backend to use.
    public var sttBackend: STTBackendKind
    /// Base URL of the STT server. For `whisperCpp` this is the server root; for
    /// `openAICompatible` it should include the API root (e.g. ending in `/v1`).
    public var sttBaseURL: String
    /// Model name sent to OpenAI-compatible STT servers (ignored by whisper.cpp).
    public var sttModel: String
    /// Spoken language: `"auto"` for detection, or an ISO code like `"en"`.
    public var language: String
    /// Whether to run the optional LLM cleanup pass.
    public var cleanupEnabled: Bool
    /// Base URL of the OpenAI-compatible chat endpoint (default: local Ollama).
    public var llmBaseURL: String
    /// Chat model name for cleanup.
    public var llmModel: String
    /// System prompt used for cleanup.
    public var cleanupPrompt: String
    /// Hard timeout (seconds) for the cleanup request; on expiry the raw transcript is used.
    public var cleanupTimeout: Double
    /// Virtual key code of the hold-to-talk hotkey (default 61 = Right Option).
    public var hotkeyKeyCode: UInt16
    /// Text-insertion strategy.
    public var insertionMethod: InsertionMethod
    /// Whether to restore the previous clipboard contents after a paste.
    public var restoreClipboard: Bool
    /// Localhost port the bundled whisper.cpp server listens on.
    public var whisperServerPort: Int

    /// The built-in defaults used on first launch and for any missing config key.
    public static let `default` = AppConfig(
        sttBackend: .whisperCpp,
        sttBaseURL: "http://127.0.0.1:8126",
        sttModel: "whisper-large-v3-turbo",
        language: "auto",
        cleanupEnabled: false,
        llmBaseURL: "http://localhost:11434/v1",
        llmModel: "qwen2.5:7b",
        cleanupPrompt: Prompts.defaultCleanup,
        cleanupTimeout: 8.0,
        hotkeyKeyCode: 61,
        insertionMethod: .paste,
        restoreClipboard: true,
        whisperServerPort: 8126
    )

    /// Memberwise initializer.
    public init(
        sttBackend: STTBackendKind,
        sttBaseURL: String,
        sttModel: String,
        language: String,
        cleanupEnabled: Bool,
        llmBaseURL: String,
        llmModel: String,
        cleanupPrompt: String,
        cleanupTimeout: Double,
        hotkeyKeyCode: UInt16,
        insertionMethod: InsertionMethod,
        restoreClipboard: Bool,
        whisperServerPort: Int
    ) {
        self.sttBackend = sttBackend
        self.sttBaseURL = sttBaseURL
        self.sttModel = sttModel
        self.language = language
        self.cleanupEnabled = cleanupEnabled
        self.llmBaseURL = llmBaseURL
        self.llmModel = llmModel
        self.cleanupPrompt = cleanupPrompt
        self.cleanupTimeout = cleanupTimeout
        self.hotkeyKeyCode = hotkeyKeyCode
        self.insertionMethod = insertionMethod
        self.restoreClipboard = restoreClipboard
        self.whisperServerPort = whisperServerPort
    }

    /// Coding keys for tolerant decoding.
    private enum CodingKeys: String, CodingKey {
        case sttBackend, sttBaseURL, sttModel, language
        case cleanupEnabled, llmBaseURL, llmModel, cleanupPrompt, cleanupTimeout
        case hotkeyKeyCode, insertionMethod, restoreClipboard, whisperServerPort
    }

    /// Decodes a config, substituting defaults for any missing field.
    /// - Parameter decoder: The decoder to read from.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        sttBackend = try c.decodeIfPresent(STTBackendKind.self, forKey: .sttBackend) ?? d.sttBackend
        sttBaseURL = try c.decodeIfPresent(String.self, forKey: .sttBaseURL) ?? d.sttBaseURL
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel) ?? d.sttModel
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? d.cleanupEnabled
        llmBaseURL = try c.decodeIfPresent(String.self, forKey: .llmBaseURL) ?? d.llmBaseURL
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? d.llmModel
        cleanupPrompt = try c.decodeIfPresent(String.self, forKey: .cleanupPrompt) ?? d.cleanupPrompt
        cleanupTimeout = try c.decodeIfPresent(Double.self, forKey: .cleanupTimeout) ?? d.cleanupTimeout
        hotkeyKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .hotkeyKeyCode) ?? d.hotkeyKeyCode
        insertionMethod = try c.decodeIfPresent(InsertionMethod.self, forKey: .insertionMethod) ?? d.insertionMethod
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
        whisperServerPort = try c.decodeIfPresent(Int.self, forKey: .whisperServerPort) ?? d.whisperServerPort
    }
}
