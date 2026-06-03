import AppKit
import Combine

/// The application delegate that owns and wires together every subsystem.
///
/// Construction is deferred to `applicationDidFinishLaunching` so that AppKit is
/// fully initialized before status items, event taps, and the audio engine are
/// created. Subsystems are added as the milestones land.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Loaded settings and the live config.
    private let settings = SettingsStore()
    /// Supervises the bundled whisper.cpp server in local mode.
    private var supervisor: ServerSupervisor?
    /// Drives the record → transcribe → clean → insert pipeline.
    private var controller: DictationController?
    /// Global hold-to-talk hotkey.
    private var hotkey: HotkeyManager?
    /// Menu-bar status item and menu.
    private var statusItem: StatusItemController?
    /// Watches permission state to rebuild the hotkey tap the moment access is granted.
    private var permissions: PermissionsModel?
    /// Combine subscriptions (e.g. live hotkey re-install on settings change).
    private var cancellables = Set<AnyCancellable>()

    /// Creates the delegate.
    public override init() {
        super.init()
    }

    /// Boots the app once AppKit has finished launching.
    /// - Parameter notification: The launch notification (unused).
    public func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Murmur launching")
        let controller = DictationController(settings: settings)
        self.controller = controller

        let permissions = PermissionsModel()
        self.permissions = permissions

        let statusItem = StatusItemController(settings: settings, permissions: permissions)
        statusItem.install()
        self.statusItem = statusItem

        // Reflect pipeline state in the menu-bar glyph and HUD.
        controller.onStateChange = { [weak statusItem] state in
            statusItem?.update(for: state)
        }
        controller.onError = { [weak statusItem] error in
            statusItem?.showError(error)
        }

        startServerIfNeeded()
        installHotkey(controller: controller)
        requestPermissionsIfNeeded()
        observePermissions(controller: controller)
    }

    /// Requests the required permissions on launch, and opens the onboarding window if the
    /// hotkey/insertion permissions are missing (so the user isn't left with a silent app).
    private func requestPermissionsIfNeeded() {
        Task { _ = await Permissions.requestMicrophone() }
        if !Permissions.hasInputMonitoring { Permissions.requestInputMonitoring() }
        if !Permissions.hasAccessibility { Permissions.promptAccessibility() }
        if !Permissions.hasInputMonitoring || !Permissions.hasAccessibility {
            Log.app.info("required permissions missing; showing onboarding")
            statusItem?.presentOnboarding()
        }
    }

    /// Watches permission state and rebuilds the hotkey tap the moment Input Monitoring and
    /// Accessibility are both granted — so a grant takes effect immediately, without the
    /// previous "grant changes nothing until you restart" behavior.
    /// - Parameter controller: The pipeline the rebuilt hotkey drives.
    private func observePermissions(controller: DictationController) {
        guard let permissions else { return }
        permissions.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                guard let self, let hotkey = self.hotkey else { return }
                if snapshot.warrantsHotkeyRebuild(tapActive: hotkey.isActive) {
                    Log.app.info("permissions now sufficient; rebuilding hotkey tap")
                    self.rebuildHotkey(keyCode: self.settings.config.hotkeyKeyCode, controller: controller)
                }
            }
            .store(in: &cancellables)
        permissions.start()
    }

    /// Stops background processes on quit.
    /// - Parameter notification: The termination notification (unused).
    public func applicationWillTerminate(_ notification: Notification) {
        supervisor?.stop()
        hotkey?.stop()
    }

    /// Launches the local whisper.cpp server when the STT backend is local.
    private func startServerIfNeeded() {
        guard settings.config.sttBackend == .whisperCpp else {
            Log.server.info("Remote STT backend selected; not launching local server")
            return
        }
        let supervisor = ServerSupervisor()
        self.supervisor = supervisor
        supervisor.startBundledServer(
            port: settings.config.whisperServerPort,
            modelName: settings.config.sttModel
        )
    }

    /// Wires the hold-to-talk hotkey to the dictation controller, and re-installs it live
    /// whenever the hotkey is changed in Settings.
    /// - Parameter controller: The pipeline to start/stop on key press/release.
    private func installHotkey(controller: DictationController) {
        rebuildHotkey(keyCode: settings.config.hotkeyKeyCode, controller: controller)
        settings.$config
            .map(\.hotkeyKeyCode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] keyCode in
                guard let self, let controller = self.controller else { return }
                Log.hotkey.info("hotkey changed in settings; re-installing for key code \(Int(keyCode))")
                self.rebuildHotkey(keyCode: keyCode, controller: controller)
            }
            .store(in: &cancellables)
    }

    /// Tears down any existing hotkey tap and installs a fresh one for `keyCode`.
    /// - Parameters:
    ///   - keyCode: The virtual key code to watch.
    ///   - controller: The pipeline to start/stop on key press/release.
    private func rebuildHotkey(keyCode: UInt16, controller: DictationController) {
        hotkey?.stop()
        let hotkey = HotkeyManager(keyCode: keyCode)
        hotkey.onPress = { controller.begin() }
        hotkey.onRelease = { controller.end() }
        hotkey.onTapFailure = { [weak self] in
            self?.statusItem?.showError(MurmurError.permissionDenied("Input Monitoring"))
        }
        hotkey.start()
        self.hotkey = hotkey
    }
}
