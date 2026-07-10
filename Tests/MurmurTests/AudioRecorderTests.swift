import AVFoundation
import XCTest
@testable import MurmurKit

/// Verifies the microphone-contention hardening in ``AudioRecorder``: the permission preflight,
/// idempotent teardown, and the pure configuration-change interruption policy.
///
/// These tests never start an engine or touch a live microphone/TCC (headless CI): the denied
/// probe makes ``AudioRecorder/start()`` throw before any engine is created, ``stop()`` and
/// ``cancel()`` are no-ops while idle, and the interruption policy is exercised through the
/// pure static decision seam.
final class AudioRecorderTests: XCTestCase {
    /// Failure: `start()` throws `.permissionDenied("Microphone")` when access is denied, and
    /// no session becomes active — a following `stop()` returns empty `Data`.
    func testStartThrowsWhenPermissionDenied() {
        let recorder = AudioRecorder(authorizationProbe: { .denied })
        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? MurmurError, .permissionDenied("Microphone"))
        }
        // The preflight ran before any engine was created, so there is no active session.
        XCTAssertTrue(recorder.stop().isEmpty)
    }

    /// Failure: `.notDetermined` is treated as unauthorized and throws without prompting,
    /// mirroring the denied case (onboarding, not the recorder, requests access).
    func testStartThrowsWhenPermissionNotDetermined() {
        let recorder = AudioRecorder(authorizationProbe: { .notDetermined })
        XCTAssertThrowsError(try recorder.start()) { error in
            XCTAssertEqual(error as? MurmurError, .permissionDenied("Microphone"))
        }
    }

    /// Edge: `stop()` before any `start()` returns empty `Data`, and repeated `stop()` /
    /// `cancel()` in any order are safe no-ops (idempotent teardown, no crash).
    func testStopAndCancelAreIdempotentNoOps() {
        let recorder = AudioRecorder(authorizationProbe: { .denied })
        XCTAssertTrue(recorder.stop().isEmpty)   // stop without start
        XCTAssertTrue(recorder.stop().isEmpty)   // double stop
        recorder.cancel()                        // cancel without start
        recorder.cancel()                        // double cancel
        XCTAssertTrue(recorder.stop().isEmpty)   // cancel-then-stop
    }

    /// Expected: the interruption policy fires only for the current session generation while
    /// recording; a stale generation (late notification from a torn-down session) or a
    /// not-recording state is ignored.
    func testShouldInterruptPolicy() {
        // Current session, recording → interrupt.
        XCTAssertTrue(AudioRecorder.shouldInterrupt(notificationGeneration: 3, currentGeneration: 3, isRecording: true))
        // Stale generation → ignore (a torn-down session's late notification must not fire).
        XCTAssertFalse(AudioRecorder.shouldInterrupt(notificationGeneration: 2, currentGeneration: 3, isRecording: true))
        // Current session but not recording → ignore.
        XCTAssertFalse(AudioRecorder.shouldInterrupt(notificationGeneration: 3, currentGeneration: 3, isRecording: false))
    }

    /// The interruption error carries the exact user-facing message DictationController surfaces.
    func testMicInterruptedErrorDescription() {
        XCTAssertEqual(
            MurmurError.micInterrupted.errorDescription,
            "The microphone was interrupted by another app; recording stopped."
        )
    }
}
