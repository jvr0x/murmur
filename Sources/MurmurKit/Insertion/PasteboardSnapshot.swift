import AppKit

/// Captures and restores the contents of an `NSPasteboard`.
///
/// Used to put the user's clipboard back after Murmur temporarily overwrites it to paste
/// transcribed text. Restoration is best-effort across all item types present at capture.
public struct PasteboardSnapshot {
    /// One dictionary of type→data per captured pasteboard item.
    private let items: [[NSPasteboard.PasteboardType: Data]]

    /// Captures the current contents of a pasteboard.
    /// - Parameter pasteboard: The pasteboard to snapshot (defaults to the general one).
    public init(pasteboard: NSPasteboard = .general) {
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            if !entry.isEmpty { captured.append(entry) }
        }
        self.items = captured
    }

    /// Restores the captured contents, replacing whatever is on the pasteboard now.
    /// - Parameter pasteboard: The pasteboard to restore into.
    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
