import AppKit
import SwiftUI

/// A small, non-interactive floating panel showing the current pipeline status with
/// the app logo and an animated Solana-gradient waveform.
@MainActor
public final class RecordingHUD {
    /// The floating panel, created lazily.
    private var panel: NSPanel?
    /// Drives the hosted SwiftUI view's animated state.
    private let model = HUDModel()

    /// The panel size, sized to fit the hosted SwiftUI content.
    private static let size = NSSize(width: 252, height: 96)

    /// Creates an empty HUD.
    public init() {}

    /// Reflects a pipeline state: shows and animates the HUD, or hides it when idle.
    /// - Parameter state: The current dictation state.
    public func update(_ state: DictationState) {
        guard state.hudLabel != nil else { hide(); return }
        ensurePanel()
        model.state = state
        panel?.orderFrontRegardless()
    }

    /// Hides the HUD.
    public func hide() {
        panel?.orderOut(nil)
    }

    /// Creates the panel on first use and positions it at the bottom-center of the screen.
    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 90))
        }
        self.panel = panel
    }
}
