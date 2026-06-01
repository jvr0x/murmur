import Foundation

/// The lifecycle of a single dictation cycle.
///
/// The pipeline advances `idle → recording → transcribing → (cleaning) →
/// inserting → idle`. Any active state may also drop back to `idle` to reset
/// after an error or an empty capture. Re-entrant transitions (e.g. a second
/// `recording` while already recording) are rejected so a held-then-retriggered
/// hotkey cannot corrupt the pipeline.
public enum DictationState: Equatable, Sendable {
    /// Nothing in progress; ready to start a new cycle.
    case idle
    /// Capturing microphone audio while the hotkey is held.
    case recording
    /// Sending captured audio to the transcription backend.
    case transcribing
    /// Running the optional LLM cleanup pass.
    case cleaning
    /// Inserting the final text at the cursor.
    case inserting

    /// Indicates whether a transition to `target` is permitted from `self`.
    ///
    /// - Parameter target: The desired next state.
    /// - Returns: `true` if the transition is part of the legal graph.
    public func canTransition(to target: DictationState) -> Bool {
        switch (self, target) {
        case (.idle, .recording),
             (.recording, .transcribing),
             (.recording, .idle),
             (.transcribing, .cleaning),
             (.transcribing, .inserting),
             (.transcribing, .idle),
             (.cleaning, .inserting),
             (.cleaning, .idle),
             (.inserting, .idle):
            return true
        default:
            return false
        }
    }

    /// Returns `target` if the transition is legal, otherwise `nil`.
    ///
    /// - Parameter target: The desired next state.
    /// - Returns: The new state, or `nil` if the transition is rejected.
    public func next(_ target: DictationState) -> DictationState? {
        canTransition(to: target) ? target : nil
    }
}
