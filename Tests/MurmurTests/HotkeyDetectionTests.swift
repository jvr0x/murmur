import CoreGraphics
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies modifier-key detection from event flags.
///
/// Regression: detection must work using the standard high-level modifier flag
/// (`.maskAlternate` for Option), which `CGEvent.flags` always sets — not the
/// device-dependent low bits, which are not reliably present.
final class HotkeyDetectionTests: XCTestCase {
    /// Option key codes (left 58, right 61) map to the Option mask; non-modifiers map to nil.
    func testModifierMask() {
        XCTAssertEqual(HotkeyManager.modifierMask(for: 58), .maskAlternate) // left option
        XCTAssertEqual(HotkeyManager.modifierMask(for: 61), .maskAlternate) // right option
        XCTAssertEqual(HotkeyManager.modifierMask(for: 55), .maskCommand)   // left command
        XCTAssertNil(HotkeyManager.modifierMask(for: 0))                    // 'a' — not a modifier
    }

    /// The bug: with only the high-level `.maskAlternate` flag set (no device bits),
    /// the Option hotkey must be detected as active.
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

    /// An ordinary-key hotkey (e.g. F20 = 90) swallows its own key-down/up so the key does
    /// not also reach the focused app; other keys and flags-changed events pass through.
    ///
    /// Regression: a listen-only tap let the hotkey leak into the frontmost app (F20 walked
    /// Claude Code back through prompt history).
    func testSwallowsOrdinaryHotkeyKeyEventsOnly() {
        XCTAssertTrue(HotkeyManager.shouldSwallow(hotkeyCode: 90, eventType: .keyDown, eventKeyCode: 90))
        XCTAssertTrue(HotkeyManager.shouldSwallow(hotkeyCode: 90, eventType: .keyUp, eventKeyCode: 90))
        XCTAssertFalse(HotkeyManager.shouldSwallow(hotkeyCode: 90, eventType: .keyDown, eventKeyCode: 0))
        XCTAssertFalse(HotkeyManager.shouldSwallow(hotkeyCode: 90, eventType: .flagsChanged, eventKeyCode: 90))
    }

    /// A modifier hotkey (e.g. Right Option = 61) is never swallowed: a modifier flag can't
    /// be discarded cleanly and a bare modifier leaks no character/action to other apps.
    func testModifierHotkeyNeverSwallowed() {
        XCTAssertFalse(HotkeyManager.shouldSwallow(hotkeyCode: 61, eventType: .keyDown, eventKeyCode: 61))
        XCTAssertFalse(HotkeyManager.shouldSwallow(hotkeyCode: 61, eventType: .flagsChanged, eventKeyCode: 61))
    }
}
