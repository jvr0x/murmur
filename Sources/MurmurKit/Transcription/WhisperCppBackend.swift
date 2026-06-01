import Foundation

/// Transcribes audio using a local whisper.cpp HTTP server (`POST /inference`).
public struct WhisperCppBackend: TranscriptionBackend {
    /// The whisper.cpp server root URL.
    private let baseURL: URL
    /// The session used for requests (injectable for testing).
    private let session: URLSession

    /// Creates the backend.
    /// - Parameters:
    ///   - baseURL: The whisper.cpp server root (e.g. `http://127.0.0.1:8126`).
    ///   - session: The URL session to use.
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Transcribes WAV audio via the whisper.cpp `/inference` endpoint.
    public func transcribe(wav: Data, language: String) async throws -> Transcript {
        guard !wav.isEmpty else { throw MurmurError.emptyAudio }
        let url = baseURL.appendingPathComponent("inference")
        let boundary = "Boundary-\(UUID().uuidString)"
        var fields = ["response_format": "json"]
        if language != "auto" { fields["language"] = language }
        let body = MultipartBody.build(
            boundary: boundary, fields: fields,
            fileField: "file", fileName: "audio.wav",
            fileData: wav, contentType: "audio/wav"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw MurmurError.badResponse("HTTP \(code)")
            }
            return Transcript(text: try WhisperCppBackend.parse(data))
        } catch let error as MurmurError {
            throw error
        } catch {
            throw MurmurError.transportFailed(error.localizedDescription)
        }
    }

    /// Extracts the `text` field from a whisper.cpp JSON response.
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
