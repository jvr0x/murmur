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
}
