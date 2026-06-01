import AppKit
import CoreGraphics

/// Global hold-to-talk hotkey driven by a `CGEventTap`.
///
/// Fires `onPress` when the configured key goes down and `onRelease` when it comes up.
/// Modifier-only keys (e.g. Right Option, key code 61) are detected via `flagsChanged`
/// using device-dependent flag bits; ordinary keys use `keyDown`/`keyUp`. The tap is
/// listen-only, so it never swallows the key from other apps.
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
    /// Tracks the current down/up state to debounce auto-repeat and double flag events.
    private var isDown = false

    /// Creates a manager for the given key code.
    /// - Parameter keyCode: The virtual key code (default Right Option is 61).
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
        let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard kc == keyCode else { return }

        let down: Bool
        if let bit = HotkeyManager.deviceFlagBit(for: keyCode) {
            guard type == .flagsChanged else { return }
            down = (event.flags.rawValue & bit) != 0
        } else {
            switch type {
            case .keyDown: down = true
            case .keyUp: down = false
            default: return
            }
        }
        DispatchQueue.main.async { [weak self] in self?.setDown(down) }
    }

    /// Applies a debounced down/up transition and fires the callbacks.
    /// - Parameter down: Whether the key is now down.
    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        if down { onPress?() } else { onRelease?() }
    }

    /// Maps a modifier key code to its device-dependent flag bit, if it is a modifier.
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: The raw flag bit set while that modifier is held, or `nil` for ordinary keys.
    nonisolated static func deviceFlagBit(for keyCode: CGKeyCode) -> UInt64? {
        switch keyCode {
        case 59: return 0x0000_0001 // left control
        case 56: return 0x0000_0002 // left shift
        case 60: return 0x0000_0004 // right shift
        case 55: return 0x0000_0008 // left command
        case 54: return 0x0000_0010 // right command
        case 58: return 0x0000_0020 // left option
        case 61: return 0x0000_0040 // right option
        case 62: return 0x0000_2000 // right control
        default: return nil
        }
    }
}
