import Foundation
import XCTest
@testable import MurmurKit

/// Verifies the menu-bar header title reflects the configured hold-to-talk key.
///
/// Regression: the header was hardcoded to "Murmur — hold Right Option to talk", so it
/// kept naming Right Option even after the user changed the hotkey in Settings. It must be
/// derived from the configured key code via `KeyName`, matching what the Settings recorder
/// shows.
final class MenuHeaderTests: XCTestCase {
    /// Expected use: the default key code (61) names Right Option, with the same glyph the
    /// Settings recorder displays.
    func testDefaultHotkeyTitle() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(for: 61),
            "Murmur — hold Right Option ⌥ to talk"
        )
    }

    /// The bug: a non-default key must appear in the header instead of "Right Option".
    func testConfiguredKeyAppearsInTitle() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(for: 49),
            "Murmur — hold Space to talk"
        )
        XCTAssertFalse(StatusItemController.menuHeaderTitle(for: 49).contains("Right Option"))
    }

    /// Edge: an ordinary (non-modifier) key, e.g. F20, is named plainly.
    func testOrdinaryKeyTitle() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(for: 90),
            "Murmur — hold F20 to talk"
        )
    }

    /// Failure case: an unmapped key code falls back to the `Key #<code>` form.
    func testUnmappedKeyTitleFallsBack() {
        XCTAssertEqual(
            StatusItemController.menuHeaderTitle(for: 200),
            "Murmur — hold Key #200 to talk"
        )
    }
}
