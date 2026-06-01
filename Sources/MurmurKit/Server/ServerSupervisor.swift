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
    /// - Parameter port: The localhost port to bind.
    public func startBundledServer(port: Int) {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let binary = resources.appendingPathComponent("whisper-server")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            Log.server.error("whisper-server not found at \(binary.path, privacy: .public) — run Scripts/build-whisper.sh")
            return
        }
        guard let model = ServerSupervisor.findModel(in: resources) else {
            Log.server.error("no ggml-*.bin model in resources — run Scripts/fetch-model.sh")
            return
        }
        shouldRun = true
        restarts = 0
        launch(binary: binary, model: model, port: port)
    }

    /// Stops the server and prevents further restarts.
    public func stop() {
        shouldRun = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// Finds the first bundled `ggml-*.bin` model.
    /// - Parameter directory: The resources directory to search.
    /// - Returns: The model URL, or `nil` if none is present.
    private static func findModel(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents.first {
            $0.lastPathComponent.hasPrefix("ggml-") && $0.pathExtension == "bin"
        }
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
