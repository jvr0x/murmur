import AppKit
import SwiftUI

/// A Settings control that records a hold-to-talk key by capturing the next key or
/// modifier the user presses — so you set the hotkey by pressing it, not by typing a code.
///
/// Captures a single key or a single modifier (Option, Command, Control, Shift, fn), which
/// matches the app's hold-to-talk model. Escape cancels recording. The bound key code is
/// updated immediately; the app re-installs the hotkey live.
public struct KeyRecorderView: View {
    /// The key code to update when a key is recorded.
    @Binding private var keyCode: UInt16
    /// Whether we're currently capturing a key press.
    @State private var recording = false
    /// The active local event monitor (opaque token from AppKit).
    @State private var monitor: Any?

    /// Creates the recorder bound to a key code.
    /// - Parameter keyCode: The key code binding to update.
    public init(keyCode: Binding<UInt16>) {
        self._keyCode = keyCode
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(KeyName.display(for: keyCode))
                .foregroundStyle(recording ? Color.accentColor : Color.secondary)
            Button(recording ? "Press a key…  (Esc cancels)" : "Record") {
                if recording { cancel() } else { startRecording() }
            }
            .buttonStyle(.bordered)
        }
        .onDisappear(perform: cancel)
    }

    /// Begins capturing the next key/modifier press via a local event monitor.
    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard let captured = KeyRecorderView.capturedKeyCode(
                type: event.type,
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags
            ) else { return event }

            if captured == 53 { // Escape cancels without changing the key.
                cancel()
                return nil
            }
            keyCode = captured
            cancel()
            return nil // swallow the captured event so it isn't delivered to the app
        }
    }

    /// Stops capturing and removes the monitor.
    private func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    /// Decides which key code (if any) to capture from an event's primitives.
    ///
    /// Key-down captures the key. Flags-changed captures only on the **press** edge — when
    /// the modifier's flag is now set — so releasing a modifier doesn't register.
    /// - Returns: The key code to record, or `nil` to keep waiting.
    static func capturedKeyCode(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> UInt16? {
        switch type {
        case .keyDown:
            return keyCode
        case .flagsChanged:
            guard let flag = modifierFlag(forKeyCode: keyCode) else { return nil }
            return modifierFlags.contains(flag) ? keyCode : nil
        default:
            return nil
        }
    }

    /// Maps a modifier key code to the `NSEvent.ModifierFlags` it sets while held.
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: The flag for a modifier key, or `nil` for ordinary keys.
    static func modifierFlag(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        case 57: return .capsLock
        case 63: return .function
        default: return nil
        }
    }
}
