import CoreGraphics

/// Pure hotkey-detection state machine, fed raw event-tap primitives.
///
/// Lives in the event-tap thread's domain: every event is turned into a ``Verdict`` —
/// which edge (if any) to report and whether the tap must swallow the event. Keeping the
/// logic pure makes the tricky cases (auto-repeat, missed key-ups, combos, tap-disable
/// recovery) unit-testable without a live `CGEventTap`.
///
/// Detection model:
/// - **Ordinary primary key** (e.g. F20): presses on `keyDown` when all required
///   modifiers are held, releases on the primary `keyUp` only — releasing a modifier
///   early does *not* end the hold (forgiving for dictation). Auto-repeat `keyDown`s are
///   debounced but still swallowed while the press is owned.
/// - **Modifier primary key** (e.g. Right Option): tracked via the high-level flags on
///   `flagsChanged`, so either the left or right key of the pair works; with extra
///   modifiers the full flag union must be present. Modifier events are never swallowed.
///
/// Self-healing: a fresh (non-repeat) `keyDown` while already down means a `keyUp` was
/// lost (tap disabled, tap rebuilt mid-hold) — the machine resyncs by releasing and
/// pressing again instead of inverting edges forever, which is exactly the failure mode
/// of a stuck "Listening…" that only quick taps appear to escape.
struct HotkeyDetector {
    /// The edge to report to the app for one processed event.
    enum Edge: Equatable {
        /// The hotkey combo was pressed.
        case press
        /// The hotkey combo was released.
        case release
        /// A missed release was detected; report a release *then* a fresh press.
        case releaseThenPress
        /// Nothing to report.
        case none
    }

    /// The outcome of processing one event.
    struct Verdict: Equatable {
        /// The edge to report.
        let edge: Edge
        /// Whether the tap must swallow the event so it doesn't reach the focused app.
        let swallow: Bool
    }

    /// The primary virtual key code (may itself be a modifier key).
    let keyCode: CGKeyCode
    /// Extra required modifiers, sanitized to the supported device-independent flags.
    let modifiers: CGEventFlags
    /// Whether the combo is currently considered pressed.
    private(set) var isDown = false
    /// Whether the current press's `keyDown` was swallowed (so its `keyUp` must be too).
    private var swallowedDown = false

    /// The modifier flags a hotkey may require (Caps Lock deliberately excluded — it
    /// toggles rather than holds).
    static let allowedModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn,
    ]

    /// Creates a detector for a combo.
    /// - Parameters:
    ///   - keyCode: The primary virtual key code.
    ///   - modifiers: Raw `CGEventFlags` of extra required modifiers (unsupported bits
    ///     are stripped).
    init(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers)
    }

    /// The full flag set a modifier-primary combo requires (primary's mask + extras).
    private var requiredFlags: CGEventFlags {
        var required = modifiers
        if let primary = Self.modifierMask(for: keyCode) { required.insert(primary) }
        return required
    }

    /// Processes one tapped event.
    /// - Parameters:
    ///   - type: The event type (`keyDown`, `keyUp`, or `flagsChanged`).
    ///   - eventKeyCode: The event's virtual key code.
    ///   - flags: The event's modifier flags.
    ///   - isRepeat: Whether this is an auto-repeat `keyDown`.
    /// - Returns: The edge to report and whether to swallow the event.
    mutating func process(
        type: CGEventType,
        eventKeyCode: CGKeyCode,
        flags: CGEventFlags,
        isRepeat: Bool
    ) -> Verdict {
        if Self.modifierMask(for: keyCode) != nil {
            return processModifierPrimary(type: type, flags: flags)
        }
        return processOrdinaryPrimary(
            type: type, eventKeyCode: eventKeyCode, flags: flags, isRepeat: isRepeat
        )
    }

    /// Handles a modifier-primary combo: only `flagsChanged` events matter, and the
    /// combo is active while the full required flag union is present. Never swallows —
    /// a modifier flag can't be discarded cleanly and a bare modifier leaks no
    /// character/action to other apps.
    private mutating func processModifierPrimary(
        type: CGEventType, flags: CGEventFlags
    ) -> Verdict {
        guard type == .flagsChanged else { return Verdict(edge: .none, swallow: false) }
        let active = flags.contains(requiredFlags)
        guard active != isDown else { return Verdict(edge: .none, swallow: false) }
        isDown = active
        return Verdict(edge: active ? .press : .release, swallow: false)
    }

    /// Handles an ordinary-primary combo on `keyDown`/`keyUp` of the primary key.
    private mutating func processOrdinaryPrimary(
        type: CGEventType, eventKeyCode: CGKeyCode, flags: CGEventFlags, isRepeat: Bool
    ) -> Verdict {
        guard eventKeyCode == keyCode else { return Verdict(edge: .none, swallow: false) }
        switch type {
        case .keyDown:
            let comboMatched = flags.contains(modifiers)
            if !isDown {
                // Fresh press (a repeat here means the original keyDown was missed —
                // e.g. the tap was rebuilt mid-hold — so it still counts as the press).
                guard comboMatched else { return Verdict(edge: .none, swallow: false) }
                isDown = true
                swallowedDown = true
                return Verdict(edge: .press, swallow: true)
            }
            if isRepeat {
                // Auto-repeat of the owned press: debounce, but keep swallowing so the
                // repeating key never leaks into the focused app mid-dictation.
                return Verdict(edge: .none, swallow: swallowedDown)
            }
            // Fresh keyDown while already down: the keyUp was lost. Resync.
            if comboMatched {
                swallowedDown = true
                return Verdict(edge: .releaseThenPress, swallow: true)
            }
            // The new press doesn't match the combo (e.g. bare key without required
            // modifiers): release the stuck state and let the app have the key.
            isDown = false
            swallowedDown = false
            return Verdict(edge: .release, swallow: false)
        case .keyUp:
            // Pair the swallow with the down that started it, even if modifiers were
            // released first or the state already resynced.
            let swallow = swallowedDown
            swallowedDown = false
            guard isDown else { return Verdict(edge: .none, swallow: swallow) }
            isDown = false
            return Verdict(edge: .release, swallow: swallow)
        default:
            return Verdict(edge: .none, swallow: false)
        }
    }

    /// Recovers after the system disabled and re-enabled the tap (timeout / user input):
    /// events were lost in between, so the tracked state is reconciled against the
    /// *physical* key state instead of trusting edges that may never arrive.
    /// - Parameter comboPhysicallyDown: Whether every part of the combo is still held
    ///   (probed via `CGEventSource.keyState`).
    /// - Returns: The edge to report (`.release` if the combo was let go while the tap
    ///   was dead), or `.none` if the hold survives seamlessly.
    mutating func reconcile(comboPhysicallyDown: Bool) -> Edge {
        guard isDown, !comboPhysicallyDown else { return .none }
        isDown = false
        swallowedDown = false
        return .release
    }

    /// Maps a modifier key code to its high-level `CGEventFlags` mask, if it is a
    /// modifier. Both the left and right key of each pair map to the same mask, so a
    /// modifier hotkey responds to either side.
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: The flag mask set while that modifier is held, or `nil` for ordinary keys.
    static func modifierMask(for keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 55, 54: return .maskCommand     // left / right command
        case 56, 60: return .maskShift       // left / right shift
        case 58, 61: return .maskAlternate   // left / right option
        case 59, 62: return .maskControl     // left / right control
        case 63: return .maskSecondaryFn     // fn / globe
        default: return nil
        }
    }

    /// The physical key codes that can hold a modifier flag (left/right pairs).
    /// - Parameter mask: A single modifier mask.
    /// - Returns: The key codes whose keys set that mask.
    static func keyCodes(for mask: CGEventFlags) -> [CGKeyCode] {
        switch mask {
        case .maskCommand: return [55, 54]
        case .maskShift: return [56, 60]
        case .maskAlternate: return [58, 61]
        case .maskControl: return [59, 62]
        case .maskSecondaryFn: return [63]
        default: return []
        }
    }
}
