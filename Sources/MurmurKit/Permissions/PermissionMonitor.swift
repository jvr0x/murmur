import AppKit
import Combine

/// A point-in-time reading of the three macOS permissions Murmur needs.
public struct PermissionSnapshot: Equatable, Sendable {
    /// Whether microphone access is granted.
    public var microphone: Bool
    /// Whether Accessibility is granted (text insertion + active event tap).
    public var accessibility: Bool
    /// Whether Input Monitoring is granted (listening for the hotkey).
    public var inputMonitoring: Bool

    /// Creates a snapshot.
    public init(microphone: Bool, accessibility: Bool, inputMonitoring: Bool) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    /// Whether all three permissions are granted.
    public var allGranted: Bool { microphone && accessibility && inputMonitoring }

    /// Whether the hold-to-talk tap can be created.
    ///
    /// The tap is an **active** `cgSessionEventTap` (it swallows the hotkey's own key
    /// events), so it needs Accessibility, and it listens for keys, so it needs Input
    /// Monitoring. Microphone is unrelated to the tap.
    public var hotkeyReady: Bool { inputMonitoring && accessibility }

    /// Whether this snapshot warrants (re)building the hotkey tap.
    ///
    /// True only when the permissions now suffice *and* the tap isn't already live — the
    /// exact condition missed before, which left a granted permission with no running tap.
    /// - Parameter tapActive: Whether the hotkey tap is currently installed.
    /// - Returns: `true` if the tap should be rebuilt.
    public func warrantsHotkeyRebuild(tapActive: Bool) -> Bool { hotkeyReady && !tapActive }
}

/// Watches macOS permission state and republishes it so the rest of the app can react the
/// moment a permission is granted — without requiring a restart.
///
/// TCC offers no change notification, so this polls on a timer and also refreshes whenever
/// the app reactivates (e.g. the user returns from System Settings). Polling stops once all
/// permissions are granted. The probe is injectable for testing.
@MainActor
public final class PermissionsModel: ObservableObject {
    /// The latest known permission state.
    @Published public private(set) var snapshot: PermissionSnapshot

    /// Reads the current permission state (injected so tests can fake it).
    private let probe: @MainActor () -> PermissionSnapshot
    /// The polling timer, live only while not all permissions are granted.
    private var timer: Timer?
    /// The app-reactivation observer token.
    private var activationObserver: NSObjectProtocol?

    /// Creates the model with a permission probe (defaults to the live system state).
    /// - Parameter probe: A closure returning the current permission snapshot.
    public init(probe: @escaping @MainActor () -> PermissionSnapshot = { Permissions.snapshot() }) {
        self.probe = probe
        self.snapshot = probe()
    }

    /// Re-reads permission state, publishing a change only when something actually changed.
    public func refresh() {
        let current = probe()
        if current != snapshot { snapshot = current }
    }

    /// Begins watching: polls on `interval`, refreshes on app reactivation, and stops polling
    /// once everything is granted. Idempotent.
    /// - Parameter interval: Poll period in seconds.
    public func start(interval: TimeInterval = 1.5) {
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }
        guard timer == nil, !snapshot.allGranted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                if self.snapshot.allGranted { self.stop() }
            }
        }
    }

    /// Stops the polling timer (keeps the reactivation observer).
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
