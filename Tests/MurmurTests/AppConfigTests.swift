import Foundation
import XCTest
@testable import MurmurKit

/// Verifies config defaults and tolerant decoding.
final class AppConfigTests: XCTestCase {
    /// Defaults match the documented values.
    func testDefaults() {
        let config = AppConfig.default
        XCTAssertEqual(config.hotkeyKeyCode, 61)
        XCTAssertEqual(config.sttBackend, .whisperCpp)
        XCTAssertEqual(config.llmBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(config.insertionMethod, .paste)
        XCTAssertTrue(config.restoreClipboard)
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
