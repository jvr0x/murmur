import Foundation

/// Runs the optional LLM cleanup pass over a raw transcript.
///
/// Cleanup is best-effort and never blocks the dictation result: if disabled, slow, or
/// failing, the raw transcript is returned unchanged. It calls an OpenAI-compatible
/// `/chat/completions` endpoint (Ollama by default).
public struct CleanupService {
    /// The session used for requests (injectable for testing).
    private let session: URLSession

    /// Creates the service.
    /// - Parameter session: The URL session to use.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Cleans `text` using the configured LLM, or returns it unchanged on any problem.
    /// - Parameters:
    ///   - text: The raw transcript.
    ///   - config: The current configuration.
    /// - Returns: The cleaned text, or the original `text` if cleanup is disabled/fails.
    public func clean(text: String, config: AppConfig) async -> String {
        guard config.cleanupEnabled, !text.isEmpty else { return text }
        guard let base = URL(string: config.llmBaseURL) else { return text }
        let url = base.appendingPathComponent("chat/completions")

        let payload: [String: Any] = [
            "model": config.llmModel,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": config.cleanupPrompt],
                ["role": "user", "content": text],
            ],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return text }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = config.cleanupTimeout

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return text
            }
            return (try? CleanupService.parse(data)) ?? text
        } catch {
            Log.cleanup.error("cleanup failed, using raw transcript: \(error.localizedDescription, privacy: .public)")
            return text
        }
    }

    /// Extracts `choices[0].message.content` from an OpenAI-compatible chat response.
    /// - Parameter data: The raw response body.
    /// - Returns: The trimmed cleaned text.
    /// - Throws: ``MurmurError/badResponse(_:)`` if the structure is missing.
    static func parse(_ data: Data) throws -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw MurmurError.badResponse("missing choices/message/content")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
