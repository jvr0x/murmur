import XCTest
@testable import MurmurKit

/// Verifies the transcription backends' response parsing.
final class BackendParsingTests: XCTestCase {
    /// whisper.cpp responses yield the trimmed text.
    func testWhisperCppParse() throws {
        let data = Data(#"{"text":"  hello world  "}"#.utf8)
        XCTAssertEqual(try WhisperCppBackend.parse(data), "hello world")
    }

    /// A whisper.cpp response without `text` throws.
    func testWhisperCppParseMissingText() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try WhisperCppBackend.parse(data))
    }

    /// Non-JSON bodies throw.
    func testWhisperCppParseGarbage() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try WhisperCppBackend.parse(data))
    }

    /// OpenAI-compatible responses yield the trimmed text.
    func testOpenAIParse() throws {
        let data = Data(#"{"text":"hi there"}"#.utf8)
        XCTAssertEqual(try OpenAIAudioBackend.parse(data), "hi there")
    }
}
