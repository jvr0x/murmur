import CoreGraphics
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies the hotkey detection state machine (edges, combos, swallowing, recovery).
///
/// Regressions covered:
/// - Modifier detection must use the standard high-level flag (`.maskAlternate` for
///   Option), which `CGEvent.flags` always sets — not device-dependent low bits.
/// - An ordinary-key hotkey must swallow its own key events so the key doesn't leak
///   into the focused app (F20 once walked Claude Code back through prompt history).
/// - A lost `keyUp` (tap disabled mid-hold) must not invert press/release edges
///   forever: the F20 "tap pops the HUD but hold-and-release does nothing" bug.
final class HotkeyDetectionTests: XCTestCase {
    /// Option key codes (left 58, right 61) map to the Option mask; non-modifiers map to nil.
    func testModifierMask() {
        XCTAssertEqual(HotkeyManager.modifierMask(for: 58), .maskAlternate) // left option
        XCTAssertEqual(HotkeyManager.modifierMask(for: 61), .maskAlternate) // right option
        XCTAssertEqual(HotkeyManager.modifierMask(for: 55), .maskCommand)   // left command
        XCTAssertNil(HotkeyManager.modifierMask(for: 0))                    // 'a' — not a modifier
    }

    /// With only the high-level `.maskAlternate` flag set (no device bits), the Option
    /// hotkey must be detected as active.
    func testOptionDetectedFromStandardFlag() {
        XCTAssertEqual(HotkeyManager.modifierActive(forKeyCode: 61, flags: [.maskAlternate]), true)
        XCTAssertEqual(HotkeyManager.modifierActive(forKeyCode: 58, flags: [.maskAlternate]), true)
    }

    /// No Option flag → not active; non-modifier key → nil (handled via key up/down instead).
    func testOptionInactiveAndNonModifier() {
        XCTAssertEqual(HotkeyManager.modifierActive(forKeyCode: 61, flags: []), false)
        XCTAssertEqual(HotkeyManager.modifierActive(forKeyCode: 61, flags: [.maskShift]), false)
        XCTAssertNil(HotkeyManager.modifierActive(forKeyCode: 0, flags: [.maskAlternate]))
    }

    /// Expected use: an ordinary-key hotkey (F20 = 90) presses on key-down, releases on
    /// key-up, and both events are swallowed so the key never reaches the focused app.
    func testOrdinaryKeyPressReleaseAndSwallow() {
        var d = HotkeyDetector(keyCode: 90)
        XCTAssertEqual(
            d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .press, swallow: true)
        )
        XCTAssertTrue(d.isDown)
        XCTAssertEqual(
            d.process(type: .keyUp, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .release, swallow: true)
        )
        XCTAssertFalse(d.isDown)
    }

    /// Holding an ordinary key auto-repeats key-downs: they are debounced (no extra
    /// press edges) but still swallowed while the press is owned.
    func testAutoRepeatIsDebouncedButSwallowed() {
        var d = HotkeyDetector(keyCode: 90)
        _ = d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: false)
        for _ in 0..<5 {
            XCTAssertEqual(
                d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: true),
                .init(edge: .none, swallow: true)
            )
        }
        XCTAssertEqual(
            d.process(type: .keyUp, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .release, swallow: true)
        )
    }

    /// Other keys and flags-changed events pass through an ordinary-key hotkey untouched.
    func testUnrelatedEventsPassThrough() {
        var d = HotkeyDetector(keyCode: 90)
        XCTAssertEqual(
            d.process(type: .keyDown, eventKeyCode: 0, flags: [], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
        XCTAssertEqual(
            d.process(type: .flagsChanged, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
    }

    /// The F20 bug: a lost key-up (tap disabled mid-hold) must self-heal. A fresh
    /// (non-repeat) key-down while already down reports release-then-press instead of
    /// being debounced into inverted edges forever.
    func testMissedKeyUpResyncsOnFreshKeyDown() {
        var d = HotkeyDetector(keyCode: 90)
        _ = d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: false)
        // keyUp lost; user presses again.
        XCTAssertEqual(
            d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .releaseThenPress, swallow: true)
        )
        XCTAssertTrue(d.isDown)
    }

    /// Tap-outage recovery: if the combo is no longer physically held, the detector
    /// releases; if it is still held, the hold survives seamlessly.
    func testReconcileAfterTapOutage() {
        var d = HotkeyDetector(keyCode: 90)
        _ = d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: false)
        XCTAssertEqual(d.reconcile(comboPhysicallyDown: true), HotkeyDetector.Edge.none)
        XCTAssertTrue(d.isDown)
        XCTAssertEqual(d.reconcile(comboPhysicallyDown: false), .release)
        XCTAssertFalse(d.isDown)
        // Idle detector: nothing to reconcile.
        XCTAssertEqual(d.reconcile(comboPhysicallyDown: false), HotkeyDetector.Edge.none)
    }

    /// A key-up that arrives after the tap was rebuilt (down never seen) reports no
    /// edge and is not swallowed beyond the pairing rule.
    func testStrayKeyUpIsIgnored() {
        var d = HotkeyDetector(keyCode: 90)
        XCTAssertEqual(
            d.process(type: .keyUp, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
    }

    /// A repeat key-down with no tracked press (tap came up mid-hold) still counts as
    /// the press, so a rebuilt tap picks up an in-flight hold.
    func testRepeatKeyDownStartsPressWhenNotTracked() {
        var d = HotkeyDetector(keyCode: 90)
        XCTAssertEqual(
            d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: true),
            .init(edge: .press, swallow: true)
        )
    }

    /// Combo hotkey (⌘⇧F20): presses only when all required modifiers are held; the
    /// bare key passes through to the app when the combo doesn't match.
    func testComboRequiresModifiers() {
        var d = HotkeyDetector(keyCode: 90, modifiers: [.maskCommand, .maskShift])
        XCTAssertEqual(
            d.process(type: .keyDown, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
        XCTAssertEqual(
            d.process(type: .keyDown, eventKeyCode: 90, flags: [.maskCommand], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
        XCTAssertEqual(
            d.process(
                type: .keyDown, eventKeyCode: 90,
                flags: [.maskCommand, .maskShift], isRepeat: false
            ),
            .init(edge: .press, swallow: true)
        )
    }

    /// Releasing a required modifier early does not end the hold; only the primary
    /// key-up releases (forgiving for dictation), and that key-up is still swallowed.
    func testEarlyModifierReleaseKeepsHold() {
        var d = HotkeyDetector(keyCode: 90, modifiers: [.maskCommand])
        _ = d.process(type: .keyDown, eventKeyCode: 90, flags: [.maskCommand], isRepeat: false)
        XCTAssertEqual(
            d.process(type: .flagsChanged, eventKeyCode: 55, flags: [], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
        XCTAssertTrue(d.isDown)
        XCTAssertEqual(
            d.process(type: .keyUp, eventKeyCode: 90, flags: [], isRepeat: false),
            .init(edge: .release, swallow: true)
        )
    }

    /// A modifier hotkey (Right Option = 61) presses/releases via flags and is never
    /// swallowed: a modifier flag can't be discarded cleanly and leaks nothing.
    func testModifierHotkeyEdgesNeverSwallowed() {
        var d = HotkeyDetector(keyCode: 61)
        XCTAssertEqual(
            d.process(type: .flagsChanged, eventKeyCode: 61, flags: [.maskAlternate], isRepeat: false),
            .init(edge: .press, swallow: false)
        )
        XCTAssertEqual(
            d.process(type: .flagsChanged, eventKeyCode: 61, flags: [], isRepeat: false),
            .init(edge: .release, swallow: false)
        )
    }

    /// A modifier-only combo (⌘ + Option) requires the full flag union and releases
    /// when any part drops.
    func testModifierComboUnion() {
        var d = HotkeyDetector(keyCode: 61, modifiers: [.maskCommand])
        XCTAssertEqual(
            d.process(type: .flagsChanged, eventKeyCode: 61, flags: [.maskAlternate], isRepeat: false),
            .init(edge: .none, swallow: false)
        )
        XCTAssertEqual(
            d.process(
                type: .flagsChanged, eventKeyCode: 55,
                flags: [.maskAlternate, .maskCommand], isRepeat: false
            ),
            .init(edge: .press, swallow: false)
        )
        XCTAssertEqual(
            d.process(type: .flagsChanged, eventKeyCode: 55, flags: [.maskAlternate], isRepeat: false),
            .init(edge: .release, swallow: false)
        )
    }

    /// Failure case: unsupported modifier bits (Caps Lock, device bits) are stripped at
    /// construction, so garbage in a saved config can't wedge detection.
    func testUnsupportedModifierBitsAreStripped() {
        let d = HotkeyDetector(
            keyCode: 90,
            modifiers: [.maskAlphaShift, .maskCommand, CGEventFlags(rawValue: 0x2)]
        )
        XCTAssertEqual(d.modifiers, [.maskCommand])
    }
}
