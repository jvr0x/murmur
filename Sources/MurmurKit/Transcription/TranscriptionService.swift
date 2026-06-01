import Foundation

/// Builds the active ``TranscriptionBackend`` from the current configuration.
public enum TranscriptionService {
    /// Creates the backend selected in `config`.
    ///
    /// Falls back to sensible local/remote defaults if the configured base URL is
    /// malformed, so a typo in settings never crashes the pipeline.
    ///
    /// - Parameter config: The current app configuration.
    /// - Returns: A ready-to-use transcription backend.
    public static func makeBackend(from config: AppConfig) -> TranscriptionBackend {
        switch config.sttBackend {
        case .whisperCpp:
            let url = URL(string: config.sttBaseURL) ?? URL(string: "http://127.0.0.1:8126")!
            return WhisperCppBackend(baseURL: url)
        case .openAICompatible:
            let url = URL(string: config.sttBaseURL) ?? URL(string: "http://127.0.0.1:8000/v1")!
            return OpenAIAudioBackend(baseURL: url, model: config.sttModel)
        }
    }
}
