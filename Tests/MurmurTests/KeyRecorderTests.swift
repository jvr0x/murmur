import AppKit
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies key-name display (incl. combos) and the combo-recorder capture logic.
final class KeyRecorderTests: XCTestCase {
    /// Key codes map to readable names, with a fallback for unmapped codes.
    func testKeyName() {
        XCTAssertEqual(KeyName.display(for: 61), "Right Option ⌥")
        XCTAssertEqual(KeyName.display(for: 49), "Space")
        XCTAssertEqual(KeyName.display(for: 122), "F1")
        XCTAssertEqual(KeyName.display(for: 8), "C")
        XCTAssertEqual(KeyName.display(for: 999), "Key #999")
    }

    /// Combo names join HIG-ordered modifier symbols with the key name; no modifiers
    /// renders the plain key name.
    func testComboDisplay() {
        XCTAssertEqual(
            KeyName.display(keyCode: 49, modifiers: CGEventFlags.maskControl.rawValue),
            "⌃ + Space"
        )
        XCTAssertEqual(
            KeyName.display(
                keyCode: 90,
                modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue
            ),
            "⇧ + ⌘ + F20"
        )
        XCTAssertEqual(KeyName.display(keyCode: 90, modifiers: 0), "F20")
    }

    /// Expected use: modifiers pressed during recording are tracked from flag edges, so
    /// an ordinary key commits together with them (⌃ + Space).
    func testOrdinaryKeyCommitsWithHeldModifiers() {
        var r = KeyComboRecorder()
        XCTAssertEqual(r.process(type: .flagsChanged, keyCode: 59, modifierFlags: [.control]), .none)
        XCTAssertEqual(
            r.process(type: .keyDown, keyCode: 49, modifierFlags: [.control]),
            .commit(.init(keyCode: 49, modifiers: CGEventFlags.maskControl.rawValue))
        )
    }

    /// Regression guard: AppKit sets `.function` in every F-key press's own flags, which
    /// must NOT pollute the combo — recording F20 captures F20 alone, not fn + F20.
    func testFunctionKeyDoesNotGainPhantomFnModifier() {
        var r = KeyComboRecorder()
        XCTAssertEqual(
            r.process(type: .keyDown, keyCode: 90, modifierFlags: [.function]),
            .commit(.init(keyCode: 90, modifiers: 0))
        )
    }

    /// A single modifier tap (press then release) commits that modifier alone — the
    /// pre-combo behavior, now committed on the release edge.
    func testSingleModifierTapCommitsOnRelease() {
        var r = KeyComboRecorder()
        XCTAssertEqual(r.process(type: .flagsChanged, keyCode: 61, modifierFlags: [.option]), .none)
        XCTAssertEqual(
            r.process(type: .flagsChanged, keyCode: 61, modifierFlags: []),
            .commit(.init(keyCode: 61, modifiers: 0))
        )
    }

    /// A modifier-only combo (⌘ then ⌥) commits on the first release: primary is the
    /// last-pressed modifier, the rest become extras.
    func testModifierComboCommitsOnFirstRelease() {
        var r = KeyComboRecorder()
        XCTAssertEqual(r.process(type: .flagsChanged, keyCode: 55, modifierFlags: [.command]), .none)
        XCTAssertEqual(
            r.process(type: .flagsChanged, keyCode: 61, modifierFlags: [.command, .option]),
            .none
        )
        XCTAssertEqual(
            r.process(type: .flagsChanged, keyCode: 55, modifierFlags: [.option]),
            .commit(.init(keyCode: 61, modifiers: CGEventFlags.maskCommand.rawValue))
        )
    }

    /// Modifiers already held when recording starts are seeded, so the combo still
    /// commits correctly.
    func testSeededModifiersAreIncluded() {
        var r = KeyComboRecorder(initialFlags: [.command])
        XCTAssertEqual(
            r.process(type: .keyDown, keyCode: 49, modifierFlags: [.command]),
            .commit(.init(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue))
        )
    }

    /// Escape cancels without committing.
    func testEscapeCancels() {
        var r = KeyComboRecorder()
        _ = r.process(type: .flagsChanged, keyCode: 55, modifierFlags: [.command])
        XCTAssertEqual(r.process(type: .keyDown, keyCode: 53, modifierFlags: [.command]), .cancel)
    }

    /// Failure cases: releasing a modifier that was never tracked, and Caps Lock (which
    /// toggles rather than holds), record nothing.
    func testUntrackedReleaseAndCapsLockAreIgnored() {
        var r = KeyComboRecorder()
        XCTAssertEqual(r.process(type: .flagsChanged, keyCode: 61, modifierFlags: []), .none)
        XCTAssertEqual(
            r.process(type: .flagsChanged, keyCode: 57, modifierFlags: [.capsLock]),
            .none
        )
    }

    /// Modifier key codes map to their `NSEvent.ModifierFlags`; ordinary keys map to nil.
    func testModifierFlagMapping() {
        XCTAssertEqual(KeyRecorderView.modifierFlag(forKeyCode: 58), .option)
        XCTAssertEqual(KeyRecorderView.modifierFlag(forKeyCode: 63), .function)
        XCTAssertNil(KeyRecorderView.modifierFlag(forKeyCode: 0))
    }
}
