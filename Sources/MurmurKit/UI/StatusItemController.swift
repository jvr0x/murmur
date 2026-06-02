import AppKit
import SwiftUI

/// Owns the menu-bar status item, its menu, the status HUD, and the auxiliary windows.
@MainActor
public final class StatusItemController: NSObject {
    /// The menu-bar status item.
    private var statusItem: NSStatusItem?
    /// Settings backing the settings window.
    private let settings: SettingsStore
    /// The floating status HUD.
    private let hud = RecordingHUD()
    /// The lazily-created settings window.
    private var settingsWindow: NSWindow?
    /// The lazily-created onboarding window.
    private var onboardingWindow: NSWindow?

    /// Creates the controller.
    /// - Parameter settings: The shared settings store.
    public init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    /// Installs the status item and its menu.
    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = Self.idleGlyph

        let menu = NSMenu()
        let header = NSMenuItem(title: "Murmur — hold Right Option to talk", action: nil, keyEquivalent: "")
        header.isEnabled = false
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
        case .idle:
            statusItem?.button?.title = Self.idleGlyph
            hud.hide()
        case .recording:
            statusItem?.button?.title = "🔴"
            hud.show("Listening…")
        case .transcribing:
            statusItem?.button?.title = "✍️"
            hud.show("Transcribing…")
        case .cleaning:
            statusItem?.button?.title = "✨"
            hud.show("Polishing…")
        case .inserting:
            statusItem?.button?.title = "⌨️"
            hud.show("Inserting…")
        }
    }

    /// Briefly shows an error glyph and logs the error.
    /// - Parameter error: The error to surface.
    public func showError(_ error: Error) {
        Log.app.error("\(error.localizedDescription, privacy: .public)")
        statusItem?.button?.title = "⚠️"
        hud.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusItem?.button?.title = Self.idleGlyph
        }
    }

    /// The idle menu-bar glyph.
    private static let idleGlyph = "🎙️"

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
            let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
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
