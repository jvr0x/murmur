import AppKit
import CoreGraphics

/// Global hold-to-talk hotkey driven by a `CGEventTap`.
///
/// Fires `onPress` when the configured key goes down and `onRelease` when it comes up.
/// Modifier keys (Option, Command, Shift, Control) are detected via their high-level
/// `CGEventFlags` on `flagsChanged` events — which `CGEvent.flags` always reports — so a
/// modifier hotkey responds to **either** the left or right key. Ordinary keys use
/// `keyDown`/`keyUp`. The tap is listen-only, so it never swallows the key from other apps.
@MainActor
public final class HotkeyManager {
    /// Called when the hotkey is pressed.
    public var onPress: (() -> Void)?
    /// Called when the hotkey is released.
    public var onRelease: (() -> Void)?
    /// Called if the event tap cannot be created (usually missing Input Monitoring).
    public var onTapFailure: (() -> Void)?

    /// The virtual key code to watch.
    private let keyCode: CGKeyCode
    /// The active event tap.
    private var eventTap: CFMachPort?
    /// The run-loop source for the tap.
    private var runLoopSource: CFRunLoopSource?
    /// Tracks the current down/up state to debounce auto-repeat and duplicate flag events.
    private var isDown = false

    /// Creates a manager for the given key code.
    /// - Parameter keyCode: The virtual key code (default Right Option is 61; any Option works).
    public init(keyCode: UInt16) {
        self.keyCode = CGKeyCode(keyCode)
    }

    /// Installs the event tap on the main run loop.
    ///
    /// Calls ``onTapFailure`` if the tap cannot be created.
    public func start() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    manager.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            Log.hotkey.error("failed to create event tap — grant Input Monitoring permission")
            onTapFailure?()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.info("hotkey tap installed for key code \(Int(self.keyCode))")
    }

    /// Removes the event tap.
    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// Handles a tapped event (runs on the main run loop where the source is installed).
    /// - Parameters:
    ///   - type: The event type.
    ///   - event: The event.
    nonisolated private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap that is slow or interrupted; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in self?.reenable() }
            return
        }

        let down: Bool
        if HotkeyManager.modifierMask(for: keyCode) != nil {
            // Modifier hotkey: track the high-level flag (responds to either left/right key).
            guard type == .flagsChanged else { return }
            down = HotkeyManager.modifierActive(forKeyCode: keyCode, flags: event.flags) ?? false
        } else {
            // Ordinary key: match the key code on key down/up.
            let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard kc == keyCode else { return }
            switch type {
            case .keyDown: down = true
            case .keyUp: down = false
            default: return
            }
        }
        DispatchQueue.main.async { [weak self] in self?.setDown(down) }
    }

    /// Re-enables the tap after the system disabled it.
    private func reenable() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.debug("event tap re-enabled")
    }

    /// Applies a debounced down/up transition and fires the callbacks.
    /// - Parameter down: Whether the key is now down.
    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        Log.hotkey.debug("hotkey \(down ? "pressed" : "released")")
        if down { onPress?() } else { onRelease?() }
    }

    /// Maps a modifier key code to its high-level `CGEventFlags` mask, if it is a modifier.
    ///
    /// Both the left and right key of each pair map to the same mask, so a modifier hotkey
    /// responds to either side.
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: The flag mask set while that modifier is held, or `nil` for ordinary keys.
    nonisolated static func modifierMask(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 55, 54: return .maskCommand   // left / right command
        case 56, 60: return .maskShift     // left / right shift
        case 58, 61: return .maskAlternate // left / right option
        case 59, 62: return .maskControl   // left / right control
        default: return nil
        }
    }

    /// Reports whether a modifier key code's modifier is active in the given flags.
    /// - Parameters:
    ///   - keyCode: The virtual key code.
    ///   - flags: The event flags from a `flagsChanged` event.
    /// - Returns: `true`/`false` for a modifier key, or `nil` if `keyCode` is not a modifier.
    nonisolated static func modifierActive(forKeyCode keyCode: CGKeyCode, flags: CGEventFlags) -> Bool? {
        guard let mask = modifierMask(for: keyCode) else { return nil }
        return flags.contains(mask)
    }
}
