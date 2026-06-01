import Foundation

/// The result of a transcription request.
public struct Transcript: Equatable, Sendable {
    /// The transcribed text, trimmed of surrounding whitespace.
    public let text: String

    /// Creates a transcript.
    /// - Parameter text: The transcribed text.
    public init(text: String) { self.text = text }
}

/// A speech-to-text backend that turns WAV audio into text.
///
/// Implementations are selected at runtime from ``AppConfig`` by
/// ``TranscriptionService``. Both local (whisper.cpp) and remote (OpenAI-compatible)
/// servers conform, so changing the active backend is a configuration change.
public protocol TranscriptionBackend: Sendable {
    /// Transcribes WAV audio.
    /// - Parameters:
    ///   - wav: 16-bit PCM WAV data.
    ///   - language: `"auto"` or an ISO language code.
    /// - Returns: The transcript.
    /// - Throws: ``MurmurError`` on empty input, transport failure, or a bad response.
    func transcribe(wav: Data, language: String) async throws -> Transcript
}

/// Builds `multipart/form-data` request bodies shared by the HTTP backends.
enum MultipartBody {
    /// Assembles a multipart body with simple text fields plus one file part.
    /// - Parameters:
    ///   - boundary: The multipart boundary token.
    ///   - fields: Text form fields.
    ///   - fileField: The form field name for the file.
    ///   - fileName: The file's reported name.
    ///   - fileData: The file bytes.
    ///   - contentType: The file's MIME type.
    /// - Returns: The encoded request body.
    static func build(
        boundary: String,
        fields: [String: String],
        fileField: String,
        fileName: String,
        fileData: Data,
        contentType: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(contentsOf: string.utf8) }

        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
