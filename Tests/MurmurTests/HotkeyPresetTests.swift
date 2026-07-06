import CoreGraphics
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies preset combos and derived-selection detection.
final class HotkeyPresetTests: XCTestCase {
    /// Expected use: every concrete preset's combo detects back to that preset, so the
    /// picker shows the right selection after a preset (or matching recording) is applied.
    func testDetectRoundTripsEveryPreset() {
        for preset in HotkeyPreset.allCases {
            guard let combo = preset.combo else { continue }
            XCTAssertEqual(
                HotkeyPreset.detect(keyCode: combo.keyCode, modifiers: combo.modifiers),
                preset
            )
        }
    }

    /// The app-default combo (Right Option, no modifiers) maps to the Right Option preset.
    func testDefaultConfigIsRightOption() {
        let d = AppConfig.default
        XCTAssertEqual(
            HotkeyPreset.detect(keyCode: d.hotkeyKeyCode, modifiers: d.hotkeyModifiers),
            .rightOption
        )
    }

    /// Edge: presets carry the documented combos (F20 = 90, ⌃ + Space = 49 + control).
    func testPresetCombos() {
        XCTAssertEqual(HotkeyPreset.f20.combo?.keyCode, 90)
        XCTAssertEqual(HotkeyPreset.f20.combo?.modifiers, 0)
        XCTAssertEqual(HotkeyPreset.controlSpace.combo?.keyCode, 49)
        XCTAssertEqual(HotkeyPreset.controlSpace.combo?.modifiers, CGEventFlags.maskControl.rawValue)
        XCTAssertNil(HotkeyPreset.custom.combo)
    }

    /// Failure case: an unlisted combo falls back to `custom` instead of mis-selecting.
    func testUnknownComboDetectsAsCustom() {
        XCTAssertEqual(
            HotkeyPreset.detect(keyCode: 90, modifiers: CGEventFlags.maskCommand.rawValue),
            .custom
        )
        XCTAssertEqual(HotkeyPreset.detect(keyCode: 12, modifiers: 0), .custom)
    }
}
