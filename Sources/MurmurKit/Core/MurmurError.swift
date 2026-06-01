import Foundation

/// Errors surfaced by Murmur's subsystems.
///
/// Cases are intentionally coarse-grained: the UI only needs a human-readable
/// message, while logs capture the associated detail string.
public enum MurmurError: Error, LocalizedError, Equatable {
    /// The audio engine could not start or configure capture.
    case audioEngineFailed(String)
    /// Recording produced too little audio to transcribe (e.g. an accidental tap).
    case emptyAudio
    /// A backend returned a response that could not be parsed.
    case badResponse(String)
    /// A network/transport-level failure talking to a backend.
    case transportFailed(String)
    /// The local STT server did not become ready within the timeout.
    case serverNotReady
    /// A required macOS permission is missing.
    case permissionDenied(String)
    /// The configured backend or model is invalid.
    case invalidConfiguration(String)

    /// A user-facing description of the error.
    public var errorDescription: String? {
        switch self {
        case .audioEngineFailed(let detail):
            return "Audio capture failed: \(detail)"
        case .emptyAudio:
            return "No speech was captured."
        case .badResponse(let detail):
            return "The transcription server returned an unexpected response: \(detail)"
        case .transportFailed(let detail):
            return "Could not reach the server: \(detail)"
        case .serverNotReady:
            return "The local transcription server is not ready yet."
        case .permissionDenied(let which):
            return "Missing permission: \(which)."
        case .invalidConfiguration(let detail):
            return "Invalid configuration: \(detail)"
        }
    }
}
