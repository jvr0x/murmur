import Combine
import Foundation

/// Loads, holds, and persists the live ``AppConfig``.
///
/// Changes to `config` are written back to
/// `~/Library/Application Support/Murmur/config.json` automatically. The store is an
/// `ObservableObject` so SwiftUI settings views bind directly to its fields.
@MainActor
public final class SettingsStore: ObservableObject {
    /// The live configuration. Mutating it persists to disk.
    @Published public var config: AppConfig {
        didSet { save() }
    }

    /// On-disk location of the persisted config.
    private let fileURL: URL

    /// Creates the store, loading an existing config or falling back to defaults.
    public init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("config.json")
        // Assigning in init does not trigger `didSet`, so the initial load never re-saves.
        self.config = SettingsStore.load(from: fileURL) ?? .default
    }

    /// Loads a config from disk if present and decodable.
    /// - Parameter url: The config file URL.
    /// - Returns: The decoded config, or `nil` if missing/corrupt.
    private static func load(from url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Writes the current config to disk atomically.
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else {
            Log.app.error("failed to encode config")
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("failed to write config: \(error.localizedDescription, privacy: .public)")
        }
    }
}
