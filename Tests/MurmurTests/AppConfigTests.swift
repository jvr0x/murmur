import CoreGraphics
import Foundation
import XCTest
@testable import MurmurKit

/// Verifies config defaults and tolerant decoding.
final class AppConfigTests: XCTestCase {
    /// Defaults match the documented values.
    func testDefaults() {
        let config = AppConfig.default
        XCTAssertEqual(config.hotkeyKeyCode, 61)
        XCTAssertEqual(config.hotkeyModifiers, 0)
        XCTAssertEqual(config.hotkeyMode, .hold)
        XCTAssertEqual(config.sttBackend, .whisperCpp)
        XCTAssertEqual(config.llmBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.insertionMethod, .paste)
        XCTAssertTrue(config.restoreClipboard)
    }

    /// A pre-combo config (hotkeyKeyCode only) keeps its key and gains the defaults:
    /// no extra modifiers, hold-to-talk mode — existing setups behave unchanged.
    func testLegacyHotkeyConfigDecodesToHoldWithNoModifiers() throws {
        let json = Data(#"{"hotkeyKeyCode":90}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.hotkeyKeyCode, 90)
        XCTAssertEqual(decoded.hotkeyModifiers, 0)
        XCTAssertEqual(decoded.hotkeyMode, .hold)
    }

    /// A combo + toggle config round-trips through JSON intact.
    func testComboAndModePersist() throws {
        var config = AppConfig.default
        config.hotkeyKeyCode = 49
        config.hotkeyModifiers = CGEventFlags.maskControl.rawValue
        config.hotkeyMode = .toggle
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.hotkeyMode, .toggle)
    }

    /// Failure case: an unknown activation mode string rejects the file (same as the
    /// other enum fields) — `SettingsStore` then falls back to the full defaults.
    func testUnknownModeRejectsConfig() {
        let json = Data(#"{"hotkeyMode":"double-tap"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: json))
    }

    /// Encoding then decoding reproduces the same config.
    func testRoundTrip() throws {
        let config = AppConfig.default
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    /// A partial JSON object decodes, with absent keys falling back to defaults.
    func testPartialDecodeUsesDefaults() throws {
        let json = Data(#"{"sttModel":"custom-model"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.sttModel, "custom-model")
        XCTAssertEqual(decoded.hotkeyKeyCode, 61)
        XCTAssertEqual(decoded.sttBackend, .whisperCpp)
    }

    /// An empty JSON object decodes entirely to defaults.
    func testEmptyDecodeIsAllDefaults() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .default)
    }
}
