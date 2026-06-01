import Foundation

/// Drives one dictation cycle: record → transcribe → (clean) → insert.
///
/// All state lives on the main actor. The network/transcription work runs in a `Task`
/// that hops back to the main actor for state changes and text insertion. The
/// ``DictationState`` machine guards against re-entrant triggers.
@MainActor
public final class DictationController {
    /// Notified on every state change (for the menu-bar glyph / HUD).
    public var onStateChange: ((DictationState) -> Void)?
    /// Notified when a cycle fails.
    public var onError: ((Error) -> Void)?

    /// The shared settings.
    private let settings: SettingsStore
    /// The microphone recorder.
    private let recorder = AudioRecorder()
    /// The optional LLM cleanup service.
    private let cleanup = CleanupService()
    /// The current pipeline state; assignment notifies ``onStateChange``.
    private var state: DictationState = .idle {
        didSet { onStateChange?(state) }
    }

    /// Creates the controller.
    /// - Parameter settings: The shared settings store.
    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Starts recording (hotkey down). Ignored unless idle.
    public func begin() {
        guard let next = state.next(.recording) else {
            Log.app.debug("begin ignored in state \(String(describing: self.state), privacy: .public)")
            return
        }
        do {
            try recorder.start()
            state = next
        } catch {
            reset(with: error)
        }
    }

    /// Stops recording and runs the pipeline (hotkey up). Ignored unless recording.
    public func end() {
        guard state == .recording else { return }
        let wav = recorder.stop()
        guard !wav.isEmpty else { reset(with: nil); return }
        guard let next = state.next(.transcribing) else { reset(with: nil); return }
        state = next

        let config = settings.config
        let backend = TranscriptionService.makeBackend(from: config)
        Task { [weak self] in
            await self?.process(wav: wav, backend: backend, config: config)
        }
    }

    /// Runs transcription, optional cleanup, and insertion.
    /// - Parameters:
    ///   - wav: The recorded WAV data.
    ///   - backend: The transcription backend.
    ///   - config: The configuration snapshot for this cycle.
    private func process(wav: Data, backend: TranscriptionBackend, config: AppConfig) async {
        do {
            let transcript = try await backend.transcribe(wav: wav, language: config.language)
            var text = transcript.text

            if config.cleanupEnabled {
                if let next = state.next(.cleaning) { state = next }
                text = await cleanup.clean(text: text, config: config)
            }

            guard !text.isEmpty else { reset(with: nil); return }
            if let next = state.next(.inserting) { state = next }
            TextInserter.insert(text, method: config.insertionMethod, restoreClipboard: config.restoreClipboard)
            reset(with: nil)
        } catch {
            reset(with: error)
        }
    }

    /// Resets to idle, surfacing an error if provided.
    /// - Parameter error: The error to report, or `nil` for a clean reset.
    private func reset(with error: Error?) {
        state = .idle
        if let error {
            Log.app.error("dictation failed: \(error.localizedDescription, privacy: .public)")
            onError?(error)
        }
    }
}
