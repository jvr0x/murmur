import XCTest
@testable import MurmurKit

/// Verifies the dictation state-machine transition rules.
final class DictationStateTests: XCTestCase {
    /// The full happy path advances through every stage.
    func testLegalForwardPath() {
        XCTAssertEqual(DictationState.idle.next(.recording), .recording)
        XCTAssertEqual(DictationState.recording.next(.transcribing), .transcribing)
        XCTAssertEqual(DictationState.transcribing.next(.cleaning), .cleaning)
        XCTAssertEqual(DictationState.cleaning.next(.inserting), .inserting)
        XCTAssertEqual(DictationState.inserting.next(.idle), .idle)
    }

    /// Cleanup may be skipped, going straight from transcribing to inserting.
    func testCleanupSkipped() {
        XCTAssertEqual(DictationState.transcribing.next(.inserting), .inserting)
    }

    /// Illegal jumps and re-entrant transitions are rejected.
    func testIllegalTransitions() {
        XCTAssertNil(DictationState.idle.next(.transcribing))
        XCTAssertNil(DictationState.idle.next(.inserting))
        XCTAssertNil(DictationState.recording.next(.recording))
        XCTAssertNil(DictationState.inserting.next(.recording))
    }

    /// Active states may reset back to idle (e.g. on error or empty capture).
    func testErrorResetToIdle() {
        XCTAssertEqual(DictationState.recording.next(.idle), .idle)
        XCTAssertEqual(DictationState.transcribing.next(.idle), .idle)
        XCTAssertEqual(DictationState.cleaning.next(.idle), .idle)
    }

    /// Idle shows no HUD; every active state has a distinct label.
    func testHUDLabels() {
        XCTAssertNil(DictationState.idle.hudLabel)
        XCTAssertEqual(DictationState.recording.hudLabel, "Listening…")
        XCTAssertEqual(DictationState.transcribing.hudLabel, "Transcribing…")
        XCTAssertEqual(DictationState.cleaning.hudLabel, "Polishing…")
        XCTAssertEqual(DictationState.inserting.hudLabel, "Inserting…")
        // Active labels are all distinct.
        let labels = [DictationState.recording, .transcribing, .cleaning, .inserting]
            .compactMap(\.hudLabel)
        XCTAssertEqual(Set(labels).count, labels.count)
    }
}
