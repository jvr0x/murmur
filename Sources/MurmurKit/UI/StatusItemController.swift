import AppKit
import QuartzCore
import SwiftUI

/// Owns the menu-bar status item, its menu, the status HUD, and the auxiliary windows.
@MainActor
public final class StatusItemController: NSObject {
    /// The menu-bar status item.
    private var statusItem: NSStatusItem?
    /// A small colored dot overlaid on the wave glyph to signal the active state.
    private let statusDot = CALayer()
    /// The disabled header item; its title tracks the configured hotkey.
    private var headerItem: NSMenuItem?
    /// Settings backing the settings window.
    private let settings: SettingsStore
    /// Live permission state, shared with the onboarding window for live status.
    private let permissions: PermissionsModel
    /// The floating status HUD.
    private let hud = RecordingHUD()
    /// The lazily-created settings window.
    private var settingsWindow: NSWindow?
    /// The lazily-created onboarding window.
    private var onboardingWindow: NSWindow?

    /// Creates the controller.
    /// - Parameters:
    ///   - settings: The shared settings store.
    ///   - permissions: The shared, live permission state for onboarding.
    public init(settings: SettingsStore, permissions: PermissionsModel) {
        self.settings = settings
        self.permissions = permissions
        super.init()
    }

    /// Installs the status item and its menu.
    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            Self.applyWaveGlyph(to: button)
            button.wantsLayer = true
            button.layer?.masksToBounds = false
            statusDot.frame = CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
            statusDot.cornerRadius = Self.dotSize / 2
            statusDot.isHidden = true
            button.layer?.addSublayer(statusDot)
        }

        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(
            title: Self.menuHeaderTitle(for: settings.config.hotkeyKeyCode),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        headerItem = header
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), ","))
        menu.addItem(menuItem("Permissions…", #selector(openOnboarding), ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Murmur", #selector(quit), "q"))
        item.menu = menu
        statusItem = item
    }

    /// Reflects a pipeline state in the menu-bar glyph and HUD.
    /// - Parameter state: The current dictation state.
    public func update(for state: DictationState) {
        switch state {
        case .idle:        setDot(nil)
        case .recording:   setDot(.systemRed)
        case .transcribing: setDot(.systemBlue)
        case .cleaning:    setDot(.systemPurple)
        case .inserting:   setDot(.systemGreen)
        }
        hud.update(state)
    }

    /// Briefly shows an error glyph and logs the error.
    /// - Parameter error: The error to surface.
    public func showError(_ error: Error) {
        Log.app.error("\(error.localizedDescription, privacy: .public)")
        setDot(.systemOrange)
        hud.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.setDot(nil)
        }
    }

    /// The idle menu-bar glyph (fallback if the bundled wave asset can't be loaded).
    private static let idleGlyph = "🎙️"

    /// Diameter of the status dot, in points.
    private static let dotSize: CGFloat = 7

    /// Sets `button.image` to the monochrome wave template, sized for the menu bar.
    ///
    /// The image is marked as a template so macOS tints it for light/dark menu bars.
    /// Falls back to the legacy emoji title if the bundled asset can't be loaded.
    /// - Parameter button: The status-item button to brand.
    private static func applyWaveGlyph(to button: NSStatusBarButton) {
        guard let url = Bundle.main.url(forResource: "StatusWave", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            button.title = idleGlyph
            return
        }
        image.isTemplate = true
        let height: CGFloat = 17
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 2.3
        image.size = NSSize(width: height * aspect, height: height)
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    /// Shows the status dot in `color`, or hides it when `color` is `nil` (idle).
    /// - Parameter color: The dot color for the active state, or `nil` for none.
    private func setDot(_ color: NSColor?) {
        guard let color else {
            statusDot.isHidden = true
            return
        }
        if let button = statusItem?.button {
            let s = Self.dotSize
            statusDot.frame = CGRect(x: button.bounds.maxX - s - 1,
                                     y: button.bounds.maxY - s - 2,
                                     width: s, height: s)
        }
        statusDot.backgroundColor = color.cgColor
        statusDot.isHidden = false
    }

    /// Builds the disabled menu header naming the configured hold-to-talk key.
    /// - Parameter keyCode: The configured hotkey's virtual key code.
    /// - Returns: A header like `"Murmur — hold Right Option ⌥ to talk"`.
    nonisolated static func menuHeaderTitle(for keyCode: UInt16) -> String {
        "Murmur — hold \(KeyName.display(for: keyCode)) to talk"
    }

    /// Builds a target-bound menu item.
    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Opens (creating if needed) the settings window.
    @objc private func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView().environmentObject(settings)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Murmur Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: 620))
            settingsWindow = window
        }
        present(settingsWindow)
    }

    /// Opens (creating if needed) the permissions window. Menu action wrapper.
    @objc private func openOnboarding() {
        presentOnboarding()
    }

    /// Shows the permissions/onboarding window (also called on first launch when a
    /// required permission is missing).
    public func presentOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: permissions)))
            window.title = "Murmur Permissions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 440, height: 340))
            onboardingWindow = window
        }
        present(onboardingWindow)
    }

    /// Brings a window to the front and activates the app.
    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Terminates the app.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    /// Refreshes the header to the currently configured hotkey just before the menu opens.
    ///
    /// The hotkey can change at runtime (Settings applies it live), so the title is derived
    /// here rather than only at install time — keeping the menu in sync without a separate
    /// settings subscription.
    /// - Parameter menu: The menu about to be displayed.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        headerItem?.title = Self.menuHeaderTitle(for: settings.config.hotkeyKeyCode)
    }
}
