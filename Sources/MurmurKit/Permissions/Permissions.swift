import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

/// Queries and requests the three macOS permissions Murmur needs.
@MainActor
public enum Permissions {
    /// Whether microphone access is authorized.
    public static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Requests microphone access, prompting the user if undetermined.
    /// - Returns: `true` if access is granted.
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Whether the process is trusted for Accessibility (needed to insert text).
    public static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility access, opening the system prompt if not yet trusted.
    public static func promptAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Whether Input Monitoring (event-tap listening) is authorized.
    public static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    /// Requests Input Monitoring access, prompting the user if undetermined.
    public static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    /// A snapshot of all three permission states at this moment.
    /// - Returns: The current microphone / accessibility / input-monitoring grants.
    public static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: hasMicrophone,
            accessibility: hasAccessibility,
            inputMonitoring: hasInputMonitoring
        )
    }

    /// Opens a System Settings privacy pane by URL.
    /// - Parameter pane: An `x-apple.systempreferences:` URL string.
    public static func openSettings(_ pane: String) {
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}
