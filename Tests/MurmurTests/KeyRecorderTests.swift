import AppKit
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies key-name display and the key-recorder capture logic.
final class KeyRecorderTests: XCTestCase {
    /// Key codes map to readable names, with a fallback for unmapped codes.
    func testKeyName() {
        XCTAssertEqual(KeyName.display(for: 61), "Right Option ⌥")
        XCTAssertEqual(KeyName.display(for: 49), "Space")
        XCTAssertEqual(KeyName.display(for: 122), "F1")
        XCTAssertEqual(KeyName.display(for: 8), "C")
        XCTAssertEqual(KeyName.display(for: 999), "Key #999")
    }

    /// A key-down captures that key code.
    func testCaptureKeyDown() {
        XCTAssertEqual(
            KeyRecorderView.capturedKeyCode(type: .keyDown, keyCode: 49, modifierFlags: []),
            49
        )
    }

    /// A modifier captures on the press edge (flag set) and not on release (flag clear).
    func testCaptureModifierEdges() {
        XCTAssertEqual(
            KeyRecorderView.capturedKeyCode(type: .flagsChanged, keyCode: 61, modifierFlags: [.option]),
            61
        )
        XCTAssertNil(
            KeyRecorderView.capturedKeyCode(type: .flagsChanged, keyCode: 61, modifierFlags: [])
        )
    }

    /// Modifier key codes map to their `NSEvent.ModifierFlags`; ordinary keys map to nil.
    func testModifierFlagMapping() {
        XCTAssertEqual(KeyRecorderView.modifierFlag(forKeyCode: 58), .option)
        XCTAssertEqual(KeyRecorderView.modifierFlag(forKeyCode: 63), .function)
        XCTAssertNil(KeyRecorderView.modifierFlag(forKeyCode: 0))
    }
}
