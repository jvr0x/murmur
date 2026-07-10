import AVFoundation
import XCTest
@testable import MurmurKit

/// Verifies the pure, TCC-free permission decisions that drive the reworked onboarding UX:
/// the `AVAuthorizationStatus` → `PermissionStatus` mapping and the microphone "Grant" action
/// derived from it. No test here touches live permission state.
final class OnboardingLogicTests: XCTestCase {
    /// Maps every `AVAuthorizationStatus` to the expected tri-state `PermissionStatus`,
    /// including the `.restricted` collapse to `.denied`.
    func testAuthorizationStatusMapping() {
        XCTAssertEqual(Permissions.permissionStatus(for: .authorized), .granted)
        XCTAssertEqual(Permissions.permissionStatus(for: .notDetermined), .notDetermined)
        XCTAssertEqual(Permissions.permissionStatus(for: .denied), .denied)
        XCTAssertEqual(Permissions.permissionStatus(for: .restricted), .denied)
    }

    /// Expected use: an undetermined mic status makes "Grant" show the system prompt.
    func testGrantRequestsWhenNotDetermined() {
        XCTAssertEqual(Permissions.microphoneGrantAction(for: .notDetermined), .requestSystemPrompt)
    }

    /// Failure case: a denied mic status makes "Grant" open System Settings, because macOS
    /// will not present the prompt again after the user has decided.
    func testGrantOpensSettingsWhenDenied() {
        XCTAssertEqual(Permissions.microphoneGrantAction(for: .denied), .openSystemSettings)
    }

    /// Edge case: `.authorized` maps to `.granted`, and the (never-shown) Grant action for a
    /// granted status resolves to opening Settings rather than prompting.
    func testGrantedStateMappingAndAction() {
        XCTAssertEqual(Permissions.permissionStatus(for: .authorized), .granted)
        XCTAssertEqual(Permissions.microphoneGrantAction(for: .granted), .openSystemSettings)
    }

    /// The Microphone privacy-pane URL is the exact string macOS expects.
    @MainActor
    func testMicrophonePaneURL() {
        XCTAssertEqual(
            Permissions.microphonePane,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }
}
