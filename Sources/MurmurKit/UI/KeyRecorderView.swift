import AppKit
import SwiftUI

/// A Settings control that records the dictation hotkey by capturing the next key or
/// combo the user presses — so you set the hotkey by pressing it, not by typing a code.
///
/// Supports a single key (F20), a single modifier (Right Option), a modifier combo
/// (⌘ + ⌥), or modifiers plus a key (⌃ + Space). Ordinary keys commit immediately with
/// whatever modifiers are held; modifier-only combos commit when the first key of the
/// combo is released. Escape cancels recording. The bound combo is updated immediately;
/// the app re-installs the hotkey live.
public struct KeyRecorderView: View {
    /// The primary key code to update when a combo is recorded.
    @Binding private var keyCode: UInt16
    /// The raw extra-modifier flags to update when a combo is recorded.
    @Binding private var modifiers: UInt64
    /// Whether we're currently capturing a combo.
    @State private var recording = false
    /// The active local event monitor (opaque token from AppKit).
    @State private var monitor: Any?
    /// The capture state machine, reset each time recording starts.
    @State private var recorder = KeyComboRecorder()

    /// Creates the recorder bound to a combo.
    /// - Parameters:
    ///   - keyCode: The primary key code binding to update.
    ///   - modifiers: The raw extra-modifier flags binding to update.
    public init(keyCode: Binding<UInt16>, modifiers: Binding<UInt64>) {
        self._keyCode = keyCode
        self._modifiers = modifiers
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(KeyName.display(keyCode: keyCode, modifiers: modifiers))
                .foregroundStyle(recording ? Color.accentColor : Color.secondary)
            Button(recording ? "Press a key or combo…  (Esc cancels)" : "Record") {
                if recording { cancel() } else { startRecording() }
            }
            .buttonStyle(.bordered)
        }
        .onDisappear(perform: cancel)
    }

    /// Begins capturing the next key/combo press via a local event monitor.
    private func startRecording() {
        recording = true
        recorder = KeyComboRecorder(initialFlags: NSEvent.modifierFlags)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch recorder.process(
                type: event.type, keyCode: event.keyCode, modifierFlags: event.modifierFlags
            ) {
            case .none:
                return event
            case .cancel:
                cancel()
                return nil
            case .commit(let combo):
                keyCode = combo.keyCode
                modifiers = combo.modifiers
                cancel()
                return nil // swallow the captured event so it isn't delivered to the app
            }
        }
    }

    /// Stops capturing and removes the monitor.
    private func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
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

/// The hotkey-capture state machine, kept pure so combo recording is unit-testable.
///
/// Modifier state is tracked from `flagsChanged` **edges of modifier keys only** — never
/// from a `keyDown`'s own flags, because AppKit sets `.function` for every F-key and
/// arrow press, which would pollute an F20 recording with a phantom fn modifier.
struct KeyComboRecorder {
    /// A captured combo.
    struct Combo: Equatable {
        /// The primary virtual key code.
        let keyCode: UInt16
        /// Raw `CGEventFlags` of the extra modifiers.
        let modifiers: UInt64
    }

    /// What the recorder decided for one event.
    enum Action: Equatable {
        /// Keep waiting.
        case none
        /// Recording was cancelled (Escape).
        case cancel
        /// A combo was captured.
        case commit(Combo)
    }

    /// The modifier flags a combo may include (Caps Lock excluded — it toggles).
    private static let combinable: NSEvent.ModifierFlags = [
        .command, .option, .shift, .control, .function,
    ]

    /// Modifiers currently held, tracked from flag edges (seeded at start).
    private var heldFlags: NSEvent.ModifierFlags
    /// Union of every modifier held during this recording (drives modifier-only combos).
    private var peakFlags: NSEvent.ModifierFlags = []
    /// The most recently pressed modifier key, the primary of a modifier-only combo.
    private var lastModifierKeyCode: UInt16?

    /// Creates a recorder, seeding the held-modifier state (so a combo whose modifiers
    /// were already held when recording started still commits correctly).
    /// - Parameter initialFlags: The current `NSEvent.modifierFlags` at start.
    init(initialFlags: NSEvent.ModifierFlags = []) {
        self.heldFlags = initialFlags.intersection(Self.combinable)
    }

    /// Processes one monitored event.
    /// - Parameters:
    ///   - type: The event type (`keyDown` or `flagsChanged`).
    ///   - keyCode: The event's virtual key code.
    ///   - modifierFlags: The event's modifier flags.
    /// - Returns: The action to take.
    mutating func process(
        type: NSEvent.EventType, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags
    ) -> Action {
        switch type {
        case .keyDown where keyCode == 53:
            return .cancel // Escape always cancels, never records.
        case .keyDown:
            // An ordinary key commits immediately with the tracked held modifiers.
            return .commit(Combo(keyCode: keyCode, modifiers: Self.cgRaw(heldFlags)))
        case .flagsChanged:
            guard let flag = KeyRecorderView.modifierFlag(forKeyCode: keyCode),
                  Self.combinable.contains(flag)
            else { return .none }
            if modifierFlags.contains(flag) {
                // Press edge of this modifier key.
                heldFlags.insert(flag)
                peakFlags.formUnion(heldFlags)
                lastModifierKeyCode = keyCode
                return .none
            }
            // Release edge: a modifier-only combo commits on its first release, with
            // the last-pressed modifier as the primary key and the rest as extras.
            heldFlags.remove(flag)
            guard let primary = lastModifierKeyCode, !peakFlags.isEmpty else { return .none }
            let primaryFlag = KeyRecorderView.modifierFlag(forKeyCode: primary) ?? []
            return .commit(Combo(
                keyCode: primary,
                modifiers: Self.cgRaw(peakFlags.subtracting(primaryFlag))
            ))
        default:
            return .none
        }
    }

    /// Converts AppKit modifier flags to raw `CGEventFlags` for persistence.
    /// - Parameter flags: The AppKit flags.
    /// - Returns: The equivalent raw `CGEventFlags` bits.
    static func cgRaw(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        var out = CGEventFlags()
        if flags.contains(.command) { out.insert(.maskCommand) }
        if flags.contains(.option) { out.insert(.maskAlternate) }
        if flags.contains(.shift) { out.insert(.maskShift) }
        if flags.contains(.control) { out.insert(.maskControl) }
        if flags.contains(.function) { out.insert(.maskSecondaryFn) }
        return out.rawValue
    }
}
