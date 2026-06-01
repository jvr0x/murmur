import AppKit

/// A small, non-interactive floating panel that shows the current pipeline status.
@MainActor
public final class RecordingHUD {
    /// The floating panel, created lazily.
    private var panel: NSPanel?
    /// The status label inside the panel.
    private let label = NSTextField(labelWithString: "")

    /// Creates an empty HUD.
    public init() {}

    /// Shows the HUD with the given status text.
    /// - Parameter text: The status message (e.g. "Listening…").
    public func show(_ text: String) {
        ensurePanel()
        label.stringValue = text
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
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
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

        let container = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.autoresizingMask = [.width, .height]

        label.textColor = .labelColor
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: 12, y: 16, width: 196, height: 24)
        label.autoresizingMask = [.width]
        container.addSubview(label)
        panel.contentView = container

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 110, y: frame.minY + 90))
        }
        self.panel = panel
    }
}
