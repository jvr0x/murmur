import XCTest
@testable import MurmurKit

/// Verifies permission-snapshot logic and live re-check behavior — the gap that caused
/// "I grant the permission but nothing happens until I restart".
final class PermissionMonitorTests: XCTestCase {
    /// `allGranted` requires all three; `hotkeyReady` requires Input Monitoring + Accessibility.
    func testSnapshotComputedFlags() {
        XCTAssertTrue(PermissionSnapshot(microphone: true, accessibility: true, inputMonitoring: true).allGranted)
        XCTAssertFalse(PermissionSnapshot(microphone: true, accessibility: true, inputMonitoring: false).allGranted)
        // The active hold-to-talk tap needs Input Monitoring (listen) + Accessibility (swallow); mic is irrelevant.
        XCTAssertTrue(PermissionSnapshot(microphone: false, accessibility: true, inputMonitoring: true).hotkeyReady)
        XCTAssertFalse(PermissionSnapshot(microphone: true, accessibility: false, inputMonitoring: true).hotkeyReady)
        XCTAssertFalse(PermissionSnapshot(microphone: true, accessibility: true, inputMonitoring: false).hotkeyReady)
    }

    /// A newly-granted snapshot warrants rebuilding the tap only when the tap isn't already live.
    func testWarrantsRebuildOnlyWhenReadyAndInactive() {
        let ready = PermissionSnapshot(microphone: false, accessibility: true, inputMonitoring: true)
        XCTAssertTrue(ready.warrantsHotkeyRebuild(tapActive: false))   // the bug: granted but tap dead → rebuild
        XCTAssertFalse(ready.warrantsHotkeyRebuild(tapActive: true))   // already live → leave it
        let notReady = PermissionSnapshot(microphone: true, accessibility: false, inputMonitoring: true)
        XCTAssertFalse(notReady.warrantsHotkeyRebuild(tapActive: false))
    }

    /// `refresh()` reflects a probe change and publishes exactly once per distinct change.
    @MainActor
    func testModelRefreshDetectsTransition() {
        var current = PermissionSnapshot(microphone: false, accessibility: false, inputMonitoring: false)
        let model = PermissionsModel(probe: { current })
        XCTAssertFalse(model.snapshot.hotkeyReady)

        var emissions = 0
        let token = model.$snapshot.dropFirst().sink { _ in emissions += 1 }

        current = PermissionSnapshot(microphone: false, accessibility: true, inputMonitoring: true)
        model.refresh()
        XCTAssertTrue(model.snapshot.hotkeyReady)
        XCTAssertEqual(emissions, 1)

        model.refresh()                       // no change → no extra emission
        XCTAssertEqual(emissions, 1)
        token.cancel()
    }
}
