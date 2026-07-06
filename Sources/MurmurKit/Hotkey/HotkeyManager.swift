import AppKit
import CoreGraphics

/// Global dictation hotkey driven by a `CGEventTap` on a dedicated thread.
///
/// Fires `onPress` when the configured combo goes down and `onRelease` when it comes up.
/// Detection lives in ``HotkeyDetector`` (combos, auto-repeat debounce, missed-key-up
/// resync); this class owns the tap plumbing.
///
/// The tap runs on its **own thread with its own run loop** — never the main run loop.
/// The tap is an active (`.defaultTap`) filter, so every keyboard event in the session
/// waits on its callback; serviced from the main run loop it stalls whenever the app
/// does (audio-engine start, HUD animation, memory pressure), and after ~1 s of
/// unresponsiveness macOS disables the tap and the hotkey's key-up is lost mid-hold.
/// An ordinary-key hotkey (e.g. F20) is hit hardest because holding it auto-repeats
/// `keyDown`s into the stalled tap. On its own user-interactive thread the callback
/// only runs the pure detector, so it always answers in time.
///
/// If the system still disables the tap (`tapDisabledByTimeout`/`ByUserInput`), it is
/// re-enabled in place and the detector state is reconciled against the *physical* key
/// state, releasing a hold whose key-up was swallowed by the outage instead of leaving
/// a stuck recording.
@MainActor
public final class HotkeyManager {
    /// Called on the main thread when the hotkey combo is pressed.
    public var onPress: (() -> Void)?
    /// Called on the main thread when the hotkey combo is released.
    public var onRelease: (() -> Void)?
    /// Called if the event tap cannot be created (usually missing Input Monitoring).
    public var onTapFailure: (() -> Void)?

    /// The tap thread owner.
    private let runner: EventTapRunner

    /// Whether the event tap is currently installed (created and not torn down).
    public var isActive: Bool { runner.isActive }

    /// Creates a manager for the given combo.
    /// - Parameters:
    ///   - keyCode: The primary virtual key code (default Right Option is 61).
    ///   - modifiers: Raw `CGEventFlags` of extra required modifiers (0 for none).
    public init(keyCode: UInt16, modifiers: UInt64 = 0) {
        self.runner = EventTapRunner(
            keyCode: CGKeyCode(keyCode),
            modifiers: CGEventFlags(rawValue: modifiers)
        )
        runner.onEdge = { [weak self] edge in
            // Tap-thread → main-thread hop; a serial queue preserves edge order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch edge {
                    case .press: self.onPress?()
                    case .release: self.onRelease?()
                    case .releaseThenPress:
                        self.onRelease?()
                        self.onPress?()
                    case .none: break
                    }
                }
            }
        }
    }

    /// Installs the event tap on its dedicated thread.
    ///
    /// Returns once the tap is live (or creation failed); calls ``onTapFailure`` on
    /// failure so the caller can surface the missing Input Monitoring permission.
    public func start() {
        guard runner.start() else {
            Log.hotkey.error("failed to create event tap — grant Input Monitoring permission")
            onTapFailure?()
            return
        }
        Log.hotkey.info("hotkey tap installed for key code \(Int(self.runner.keyCode)) modifiers 0x\(String(self.runner.modifiers.rawValue, radix: 16), privacy: .public)")
    }

    /// Removes the event tap and stops its thread.
    public func stop() {
        runner.stop()
    }

    /// Maps a modifier key code to its high-level `CGEventFlags` mask, if it is a modifier.
    ///
    /// Both the left and right key of each pair map to the same mask, so a modifier hotkey
    /// responds to either side.
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: The flag mask set while that modifier is held, or `nil` for ordinary keys.
    nonisolated public static func modifierMask(for keyCode: CGKeyCode) -> CGEventFlags? {
        HotkeyDetector.modifierMask(for: keyCode)
    }

    /// Reports whether a modifier key code's modifier is active in the given flags.
    /// - Parameters:
    ///   - keyCode: The virtual key code.
    ///   - flags: The event flags from a `flagsChanged` event.
    /// - Returns: `true`/`false` for a modifier key, or `nil` if `keyCode` is not a modifier.
    nonisolated public static func modifierActive(forKeyCode keyCode: CGKeyCode, flags: CGEventFlags) -> Bool? {
        guard let mask = HotkeyDetector.modifierMask(for: keyCode) else { return nil }
        return flags.contains(mask)
    }
}

/// Owns the tap thread, the `CGEventTap`, and the detector state.
///
/// Everything after `start()` runs on the tap thread: the callback feeds the detector
/// and answers the swallow verdict inline, so the hot path never waits on the main
/// thread. Tap handles are guarded by a lock because `start()`/`stop()`/`isActive`
/// are called from the main thread.
final class EventTapRunner {
    /// The primary virtual key code.
    let keyCode: CGKeyCode
    /// The sanitized extra required modifiers.
    let modifiers: CGEventFlags
    /// Called **on the tap thread** for every detected edge.
    var onEdge: ((HotkeyDetector.Edge) -> Void)?

    /// Guards the tap handles across the main and tap threads.
    private let lock = NSLock()
    /// The active event tap (guarded by `lock`).
    private var eventTap: CFMachPort?
    /// The tap's run-loop source (guarded by `lock`).
    private var runLoopSource: CFRunLoopSource?
    /// The tap thread's run loop, kept to stop it (guarded by `lock`).
    private var runLoop: CFRunLoop?
    /// Detection state; touched only on the tap thread after `start()`.
    private var detector: HotkeyDetector

    /// Whether the event tap is currently installed.
    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return eventTap != nil
    }

    /// Creates a runner for a combo.
    /// - Parameters:
    ///   - keyCode: The primary virtual key code.
    ///   - modifiers: Extra required modifiers (unsupported bits are stripped).
    init(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(HotkeyDetector.allowedModifiers)
        self.detector = HotkeyDetector(keyCode: keyCode, modifiers: modifiers)
    }

    deinit { stop() }

    /// Spawns the tap thread and blocks briefly until the tap is created there.
    /// - Returns: `true` if the tap is live, `false` if creation failed (permissions).
    func start() -> Bool {
        stop()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            self?.threadMain(ready: ready)
        }
        thread.name = "io.github.jvr0x.murmur.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        // Tap creation is immediate in practice; the timeout only guards a wedged spawn.
        _ = ready.wait(timeout: .now() + 2)
        return isActive
    }

    /// Disables and tears down the tap, stopping its thread's run loop.
    func stop() {
        lock.lock()
        let tap = eventTap
        let source = runLoopSource
        let loop = runLoop
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopSourceInvalidate(source) }
        if let loop { CFRunLoopStop(loop) }
    }

    /// The tap thread body: creates the tap, signals readiness, and services it until
    /// the run loop is stopped.
    /// - Parameter ready: Signaled once creation succeeded or failed.
    private func threadMain(ready: DispatchSemaphore) {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let runner = Unmanaged<EventTapRunner>.fromOpaque(refcon).takeUnretainedValue()
                return runner.handle(type: type, event: event)
                    ? nil
                    : Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            ready.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lock.lock()
        eventTap = tap
        runLoopSource = source
        runLoop = CFRunLoopGetCurrent()
        lock.unlock()

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        ready.signal()
        CFRunLoopRun()
    }

    /// Handles one tapped event on the tap thread.
    /// - Parameters:
    ///   - type: The event type.
    ///   - event: The event.
    /// - Returns: `true` to swallow the event, `false` to pass it through.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables a tap it deems unresponsive; re-enable in place and
        // reconcile with the physical key state, since edges were lost meanwhile.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let edge = detector.reconcile(
                comboPhysicallyDown: Self.comboPhysicallyDown(keyCode: keyCode, modifiers: modifiers)
            )
            if edge != .none {
                Log.hotkey.info("tap was disabled by the system; reconciled with a \(String(describing: edge), privacy: .public)")
                onEdge?(edge)
            }
            return false
        }

        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let verdict = detector.process(
            type: type, eventKeyCode: eventKeyCode, flags: event.flags, isRepeat: isRepeat
        )
        if verdict.edge != .none { onEdge?(verdict.edge) }
        return verdict.swallow
    }

    /// Probes whether every part of the combo is still physically held, via the
    /// session's live key state (survives tap outages, unlike tracked edges).
    /// - Parameters:
    ///   - keyCode: The primary virtual key code.
    ///   - modifiers: The required extra modifiers.
    /// - Returns: `true` if the primary key and every required modifier are down.
    static func comboPhysicallyDown(keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        func anyKeyDown(_ codes: [CGKeyCode]) -> Bool {
            codes.contains { CGEventSource.keyState(.combinedSessionState, key: $0) }
        }
        let primaryCodes = HotkeyDetector.modifierMask(for: keyCode)
            .map(HotkeyDetector.keyCodes(for:)) ?? [keyCode]
        guard anyKeyDown(primaryCodes) else { return false }
        for mask in [CGEventFlags.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
        where modifiers.contains(mask) {
            guard anyKeyDown(HotkeyDetector.keyCodes(for: mask)) else { return false }
        }
        return true
    }
}
