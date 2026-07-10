import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

/// A coarse, tri-state authorization reading for a macOS permission.
///
/// macOS exposes a genuine tri-state only for capture devices (microphone/camera). Modeling
/// those three outcomes lets the UI decide — purely, without touching TCC — whether a "Grant"
/// click should show the system prompt or send the user to System Settings.
public enum PermissionStatus: Equatable {
    /// Access is authorized.
    case granted
    /// The user has not been asked yet; the system prompt can still be shown.
    case notDetermined
    /// Access was refused or restricted; macOS will not present the prompt again.
    case denied
}

/// What the microphone "Grant" button should do, decided purely from the current status.
///
/// macOS shows its microphone prompt only while the status is `notDetermined`; once the user
/// has answered (or the choice is restricted by policy), the only remaining path is the
/// Microphone privacy pane in System Settings.
public enum MicrophoneGrantAction: Equatable {
    /// Show the macOS microphone permission prompt (valid only when undetermined).
    case requestSystemPrompt
    /// Open the Microphone privacy pane, since macOS will not prompt again.
    case openSystemSettings
}

/// Queries and requests the three macOS permissions Murmur needs.
@MainActor
public enum Permissions {
    /// Whether microphone access is authorized.
    public static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// The current microphone authorization as a tri-state `PermissionStatus`.
    public static var microphoneStatus: PermissionStatus {
        permissionStatus(for: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    /// Maps an `AVAuthorizationStatus` to Murmur's tri-state `PermissionStatus`.
    ///
    /// Pure and `nonisolated` so it is unit-testable without live TCC state: `.authorized`
    /// becomes `.granted`, `.notDetermined` stays `.notDetermined`, and `.denied`,
    /// `.restricted`, and any future case collapse to `.denied`.
    /// - Parameter status: The capture-device authorization status to translate.
    /// - Returns: The matching `PermissionStatus`.
    nonisolated public static func permissionStatus(for status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Decides what the microphone "Grant" button should do for a given status.
    ///
    /// Pure and `nonisolated` for testability. `.notDetermined` yields a system prompt; every
    /// other state opens System Settings, because macOS never re-prompts once the user has
    /// decided.
    /// - Parameter status: The current microphone permission status.
    /// - Returns: The action the Grant button should perform.
    nonisolated public static func microphoneGrantAction(for status: PermissionStatus) -> MicrophoneGrantAction {
        status == .notDetermined ? .requestSystemPrompt : .openSystemSettings
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

    /// The System Settings URL for the Microphone privacy pane.
    public static let microphonePane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    /// The System Settings URL for the Accessibility privacy pane.
    public static let accessibilityPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// The System Settings URL for the Input Monitoring privacy pane.
    public static let inputMonitoringPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    /// Opens a System Settings privacy pane by URL.
    /// - Parameter pane: An `x-apple.systempreferences:` URL string.
    public static func openSettings(_ pane: String) {
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}
