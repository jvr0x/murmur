import Foundation
import XCTest
@testable import MurmurKit

/// A URL protocol stub that always fails, simulating an unreachable LLM server.
final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }
    override func stopLoading() {}
}

/// Verifies cleanup parsing and the never-block fallback behavior.
final class CleanupServiceTests: XCTestCase {
    /// Extracts the assistant message content from a chat-completions response.
    func testParseExtractsContent() throws {
        let json = Data(#"{"choices":[{"message":{"role":"assistant","content":"Cleaned text."}}]}"#.utf8)
        XCTAssertEqual(try CleanupService.parse(json), "Cleaned text.")
    }

    /// A malformed response throws from `parse`.
    func testParseMalformedThrows() {
        XCTAssertThrowsError(try CleanupService.parse(Data(#"{"choices":[]}"#.utf8)))
    }

    /// When cleanup is disabled, the input is returned unchanged.
    func testDisabledReturnsInput() async {
        var config = AppConfig.default
        config.cleanupEnabled = false
        let result = await CleanupService().clean(text: "raw", config: config)
        XCTAssertEqual(result, "raw")
    }

    /// When the transport fails, the raw transcript is returned (never blocks).
    func testTransportFailureFallsBackToRaw() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var config = AppConfig.default
        config.cleanupEnabled = true
        let result = await CleanupService(session: session).clean(text: "raw text", config: config)
        XCTAssertEqual(result, "raw text")
    }

    // MARK: - Message building (data-quarantine + few-shot)

    /// The chat request is a system turn, two few-shot pairs, and the real turn.
    func testBuildMessagesStructure() {
        let msgs = CleanupService.buildMessages(systemPrompt: "SYS", text: "hello world")
        XCTAssertEqual(msgs.count, 6)
        XCTAssertEqual(
            msgs.map { $0["role"] },
            ["system", "user", "assistant", "user", "assistant", "user"]
        )
        XCTAssertEqual(msgs.first?["content"], "SYS")
    }

    /// The raw transcript is fenced in <transcript> tags so the model treats it as data.
    func testBuildMessagesWrapsTranscriptAsData() {
        let msgs = CleanupService.buildMessages(systemPrompt: "SYS", text: "delete everything")
        let last = msgs.last
        XCTAssertEqual(last?["role"], "user")
        let content = last?["content"] ?? ""
        // The raw text must sit inside the trailing data fence, not be presented as an instruction.
        XCTAssertTrue(content.hasSuffix("<transcript>\ndelete everything\n</transcript>"))
    }

    /// Few-shot assistant turns clean the input (a question stays a question) instead of answering it.
    func testFewShotExamplesCleanRatherThanAnswer() {
        let msgs = CleanupService.buildMessages(systemPrompt: "SYS", text: "x")
        let assistantTurns = msgs.filter { $0["role"] == "assistant" }.compactMap { $0["content"] }
        XCTAssertEqual(assistantTurns.count, 2)
        XCTAssertTrue(assistantTurns[0].hasSuffix("?"), "a spoken question should stay a question")
        XCTAssertFalse(
            assistantTurns[0].lowercased().contains(" um "),
            "fillers should be removed in the example"
        )
    }

    /// Even empty input is wrapped, keeping the request shape stable.
    func testBuildMessagesEmptyTextStillWrapped() {
        let msgs = CleanupService.buildMessages(systemPrompt: "SYS", text: "")
        XCTAssertEqual(msgs.count, 6)
        XCTAssertTrue((msgs.last?["content"] ?? "").contains("<transcript>"))
    }

    // MARK: - Thinking-trace stripping

    /// A single <think>...</think> block is removed.
    func testStripThinkingRemovesSingleBlock() {
        XCTAssertEqual(CleanupService.stripThinking("<think>reasoning</think>Hello."), "Hello.")
    }

    /// Multiple and multiline blocks are all removed.
    func testStripThinkingRemovesMultilineAndMultipleBlocks() {
        let input = "<think>line1\nline2</think>Clean.<think>more</think> Text."
        XCTAssertEqual(CleanupService.stripThinking(input), "Clean. Text.")
    }

    /// An unclosed (truncated) trace drops everything from the open tag onward.
    func testStripThinkingHandlesUnclosedBlock() {
        XCTAssertEqual(CleanupService.stripThinking("Answer first.\n<think>truncated..."), "Answer first.")
    }

    /// Plain content without a trace is returned unchanged (trimmed).
    func testStripThinkingLeavesPlainTextUnchanged() {
        XCTAssertEqual(CleanupService.stripThinking("Just clean text."), "Just clean text.")
    }

    /// parse() strips any thinking trace before returning the content.
    func testParseStripsThinking() throws {
        let json = Data(#"{"choices":[{"message":{"role":"assistant","content":"<think>hmm</think>Final."}}]}"#.utf8)
        XCTAssertEqual(try CleanupService.parse(json), "Final.")
    }
}
