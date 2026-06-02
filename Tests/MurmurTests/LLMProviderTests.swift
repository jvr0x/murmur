import Foundation
import XCTest
@testable import MurmurKit

/// Verifies the LLM provider presets and URL-based detection used by the Settings picker.
final class LLMProviderTests: XCTestCase {
    /// Each known provider exposes its expected default base URL; custom has none.
    func testDefaultBaseURLs() {
        XCTAssertEqual(LLMProvider.ollama.defaultBaseURL, "http://localhost:11434/v1")
        XCTAssertEqual(LLMProvider.lmStudio.defaultBaseURL, "http://localhost:1234/v1")
        XCTAssertNil(LLMProvider.custom.defaultBaseURL)
    }

    /// Detection maps known URLs to providers and everything else to custom.
    func testDetect() {
        XCTAssertEqual(LLMProvider.detect(from: "http://localhost:11434/v1"), .ollama)
        XCTAssertEqual(LLMProvider.detect(from: "http://localhost:1234/v1"), .lmStudio)
        XCTAssertEqual(LLMProvider.detect(from: "http://spark.local:8000/v1"), .custom)
    }

    /// Detection tolerates surrounding whitespace.
    func testDetectTrimsWhitespace() {
        XCTAssertEqual(LLMProvider.detect(from: "  http://localhost:1234/v1  "), .lmStudio)
    }
}
