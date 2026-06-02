import Foundation

/// Launches and supervises the bundled whisper.cpp server in local mode.
///
/// Locates the `whisper-server` binary and a `ggml-*.bin` model inside the app bundle's
/// Resources, starts the process bound to localhost, and restarts it (up to a cap) if it
/// crashes. In remote mode the supervisor is simply never started.
public final class ServerSupervisor {
    /// The running server process, if any.
    private var process: Process?
    /// Whether the server should be kept alive (false after an explicit stop).
    private var shouldRun = false
    /// Number of automatic restarts performed.
    private var restarts = 0
    /// Maximum automatic restarts before giving up.
    private let maxRestarts = 5

    /// Creates an idle supervisor.
    public init() {}

    /// Starts the bundled whisper.cpp server on the given port.
    ///
    /// Logs an actionable error (and does nothing else) if the binary or model is missing,
    /// pointing the user at the setup scripts.
    ///
    /// - Parameters:
    ///   - port: The localhost port to bind.
    ///   - modelName: The preferred model (from settings); selects the matching bundled
    ///     model file so e.g. "whisper-large-v3-turbo" loads the multilingual turbo model
    ///     even when an English-only model is also bundled.
    public func startBundledServer(port: Int, modelName: String) {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let binary = resources.appendingPathComponent("whisper-server")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            Log.server.error("whisper-server not found at \(binary.path, privacy: .public) — run Scripts/build-whisper.sh")
            return
        }
        guard let model = ServerSupervisor.findModel(in: resources, preferring: modelName) else {
            Log.server.error("no ggml-*.bin model in resources — run Scripts/fetch-model.sh")
            return
        }
        shouldRun = true
        restarts = 0
        Log.server.info("loading model \(model.lastPathComponent, privacy: .public)")
        launch(binary: binary, model: model, port: port)
    }

    /// Stops the server and prevents further restarts.
    public func stop() {
        shouldRun = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// Finds the bundled GGML model to load, preferring the configured one.
    /// - Parameters:
    ///   - directory: The resources directory to search.
    ///   - modelName: The preferred model name from settings.
    /// - Returns: The chosen model URL, or `nil` if none is present.
    private static func findModel(in directory: URL, preferring modelName: String) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        guard let chosen = selectModel(from: contents.map(\.lastPathComponent), preferring: modelName) else {
            return nil
        }
        return directory.appendingPathComponent(chosen)
    }

    /// Chooses which bundled GGML model file to load.
    ///
    /// Preference order: (1) a file whose name matches the requested `modelName`
    /// (e.g. "whisper-large-v3-turbo" → `ggml-large-v3-turbo-q5_0.bin`); (2) any
    /// multilingual model over an English-only (`.en`) one; (3) any model. This keeps
    /// non-English dictation working even when an English-only model is also bundled.
    ///
    /// - Parameters:
    ///   - names: Candidate file names (not full paths).
    ///   - modelName: The preferred model name from settings.
    /// - Returns: The chosen file name, or `nil` if no GGML model is present.
    static func selectModel(from names: [String], preferring modelName: String) -> String? {
        let bins = names.filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
        guard !bins.isEmpty else { return nil }
        let needle = modelName.lowercased().replacingOccurrences(of: "whisper-", with: "")
        if !needle.isEmpty, let match = bins.first(where: { $0.lowercased().contains(needle) }) {
            return match
        }
        if let multilingual = bins.first(where: { !$0.lowercased().hasSuffix(".en.bin") }) {
            return multilingual
        }
        return bins.first
    }

    /// Spawns the server process and wires logging + restart handling.
    /// - Parameters:
    ///   - binary: The `whisper-server` executable URL.
    ///   - model: The model file URL.
    ///   - port: The localhost port to bind.
    private func launch(binary: URL, model: URL, port: Int) {
        let task = Process()
        task.executableURL = binary
        task.arguments = ["-m", model.path, "--host", "127.0.0.1", "--port", String(port)]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                Log.server.debug("\(line, privacy: .public)")
            }
        }
        task.terminationHandler = { [weak self] _ in
            guard let self, self.shouldRun else { return }
            if self.restarts < self.maxRestarts {
                self.restarts += 1
                Log.server.error("whisper-server exited; restarting (attempt \(self.restarts))")
                self.launch(binary: binary, model: model, port: port)
            } else {
                Log.server.error("whisper-server exceeded restart limit; giving up")
            }
        }

        do {
            try task.run()
            process = task
            Log.server.info("whisper-server started on 127.0.0.1:\(port)")
        } catch {
            Log.server.error("failed to launch whisper-server: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit { stop() }
}
