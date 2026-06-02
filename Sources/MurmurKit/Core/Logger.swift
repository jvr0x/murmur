import os

/// Centralized `os.Logger` instances, grouped by subsystem category.
///
/// Using a single subsystem identifier keeps all Murmur logs filterable in
/// Console.app with `subsystem:io.github.jvr0x.murmur`.
public enum Log {
    /// The unified-logging subsystem identifier for the app.
    public static let subsystem = "io.github.jvr0x.murmur"

    /// General app lifecycle and coordination logs.
    public static let app = Logger(subsystem: subsystem, category: "app")
    /// Audio capture and conversion logs.
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Hotkey / event-tap logs.
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    /// Transcription backend logs.
    public static let transcription = Logger(subsystem: subsystem, category: "transcription")
    /// LLM cleanup logs.
    public static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    /// Text-insertion logs.
    public static let insertion = Logger(subsystem: subsystem, category: "insertion")
    /// whisper.cpp server supervision logs.
    public static let server = Logger(subsystem: subsystem, category: "server")
}
