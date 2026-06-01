import Foundation

/// Transcribes audio using any OpenAI-compatible server (`POST {base}/audio/transcriptions`).
///
/// Use this to target a remote machine (e.g. an NVIDIA DGX Spark running
/// `faster-whisper` or NeMo behind an OpenAI-compatible API). The configured base URL
/// should include the API root (typically ending in `/v1`).
public struct OpenAIAudioBackend: TranscriptionBackend {
    /// The fully-resolved transcription endpoint.
    private let endpoint: URL
    /// The model name to request.
    private let model: String
    /// The session used for requests (injectable for testing).
    private let session: URLSession

    /// Creates the backend.
    /// - Parameters:
    ///   - baseURL: The API root (e.g. `http://spark.local:8000/v1`).
    ///   - model: The transcription model name.
    ///   - session: The URL session to use.
    public init(baseURL: URL, model: String, session: URLSession = .shared) {
        self.endpoint = baseURL.appendingPathComponent("audio/transcriptions")
        self.model = model
        self.session = session
    }

    /// Transcribes WAV audio via the OpenAI-compatible endpoint.
    public func transcribe(wav: Data, language: String) async throws -> Transcript {
        guard !wav.isEmpty else { throw MurmurError.emptyAudio }
        let boundary = "Boundary-\(UUID().uuidString)"
        var fields = ["model": model, "response_format": "json"]
        if language != "auto" { fields["language"] = language }
        let body = MultipartBody.build(
            boundary: boundary, fields: fields,
            fileField: "file", fileName: "audio.wav",
            fileData: wav, contentType: "audio/wav"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw MurmurError.badResponse("HTTP \(code)")
            }
            return Transcript(text: try OpenAIAudioBackend.parse(data))
        } catch let error as MurmurError {
            throw error
        } catch {
            throw MurmurError.transportFailed(error.localizedDescription)
        }
    }

    /// Extracts the `text` field from an OpenAI-compatible transcription response.
    /// - Parameter data: The raw response body.
    /// - Returns: The trimmed transcript text.
    /// - Throws: ``MurmurError/badResponse(_:)`` if `text` is absent.
    static func parse(_ data: Data) throws -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = object["text"] as? String
        else {
            throw MurmurError.badResponse(String(data: data, encoding: .utf8) ?? "non-JSON body")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
