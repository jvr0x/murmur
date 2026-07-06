import CoreGraphics
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies the menu-bar header reflects the configured hotkey combo and activation mode.
///
/// Regression: the header was once hardcoded to "hold Right Option", ignoring the
/// configured key. It must be derived from the live config — combo *and* mode — matching
/// what the Settings recorder shows.
final class MenuHeaderTests: XCTestCase {
    /// Expected use: the default combo (Right Option, hold) names the key with the same
    /// glyph the Settings recorder displays.
    func testDefaultHotkeyTitle() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(keyCode: 61, modifiers: 0, mode: .hold),
            "Murmur — hold Right Option ⌥ to talk"
        )
    }

    /// A configured key appears in the header instead of "Right Option".
    func testConfiguredKeyAppearsInTitle() {
        let title = StatusItemController.menuHeaderTitle(keyCode: 49, modifiers: 0, mode: .hold)
        XCTAssertEqual(title, "Murmur — hold Space to talk")
        XCTAssertFalse(title.contains("Right Option"))
    }

    /// A combo renders with its modifier symbols.
    func testComboAppearsInTitle() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(
                keyCode: 49, modifiers: CGEventFlags.maskControl.rawValue, mode: .hold
            ),
            "Murmur — hold ⌃ + Space to talk"
        )
    }

    /// Toggle mode says "tap … to start/stop" instead of "hold … to talk".
    func testToggleModePhrasing() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(keyCode: 90, modifiers: 0, mode: .toggle),
            "Murmur — tap F20 to start/stop"
        )
    }

    /// The config overload derives all three fields from the live config.
    func testConfigOverload() {
        var config = AppConfig.default
        config.hotkeyKeyCode = 90
        config.hotkeyMode = .toggle
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(for: config),
            "Murmur — tap F20 to start/stop"
        )
    }

    /// Failure case: an unmapped key code falls back to the `Key #<code>` form.
    func testUnmappedKeyTitleFallsBack() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(keyCode: 200, modifiers: 0, mode: .hold),
            "Murmur — hold Key #200 to talk"
        )
    }
}
