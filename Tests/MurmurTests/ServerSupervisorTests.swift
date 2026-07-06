import Foundation
import XCTest
@testable import MurmurKit

/// Verifies bundled-model selection.
///
/// Regression: when both a multilingual model and an English-only (`.en`) model are
/// present, the server must load the one matching the configured model (turbo), not
/// whichever happens to be listed first — otherwise non-English dictation silently fails.
final class ServerSupervisorTests: XCTestCase {
    /// Prefers the model whose filename matches the configured model name.
    func testPrefersConfiguredModel() {
        let names = ["ggml-base.en.bin", "ggml-large-v3-turbo-q5_0.bin"]
        XCTAssertEqual(
            ServerSupervisor.selectModel(from: names, preferring: "whisper-large-v3-turbo"),
            "ggml-large-v3-turbo-q5_0.bin"
        )
        // Order must not matter.
        XCTAssertEqual(
            ServerSupervisor.selectModel(from: names.reversed(), preferring: "whisper-large-v3-turbo"),
            "ggml-large-v3-turbo-q5_0.bin"
        )
    }

    /// With no name match, prefers a multilingual model over an English-only one.
    func testPrefersMultilingualOverEnglishOnly() {
        let names = ["ggml-base.en.bin", "ggml-small.bin"]
        XCTAssertEqual(ServerSupervisor.selectModel(from: names, preferring: "unknown"), "ggml-small.bin")
    }

    /// Falls back to the only model when it's English-only.
    func testFallsBackToOnlyModel() {
        XCTAssertEqual(
            ServerSupervisor.selectModel(from: ["ggml-base.en.bin"], preferring: "whisper-large-v3-turbo"),
            "ggml-base.en.bin"
        )
    }

    /// Ignores non-model files and returns nil when there are none.
    func testNoModels() {
        XCTAssertNil(ServerSupervisor.selectModel(from: ["README.md", "whisper-server"], preferring: "x"))
        XCTAssertNil(ServerSupervisor.selectModel(from: [], preferring: "x"))
    }

    /// Expected use: pgrep output (one PID per line) parses into PIDs for the
    /// stale-server sweep.
    func testParsePIDs() {
        XCTAssertEqual(ServerSupervisor.parsePIDs(from: "5621\n34135\n"), [5621, 34135])
    }

    /// Edge: blank lines, whitespace, and garbage are dropped; this process's own PID is
    /// excluded as defense against an over-broad pattern match.
    func testParsePIDsSkipsGarbageAndOwnPID() {
        let own = ProcessInfo.processInfo.processIdentifier
        XCTAssertEqual(
            ServerSupervisor.parsePIDs(from: " 42 \n\nnot-a-pid\n-7\n\(own)\n"),
            [42]
        )
    }

    /// Failure case: empty output (no stale servers) parses to an empty list.
    func testParsePIDsEmpty() {
        XCTAssertEqual(ServerSupervisor.parsePIDs(from: ""), [])
    }
}
