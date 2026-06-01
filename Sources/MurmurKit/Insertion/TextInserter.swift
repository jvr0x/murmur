import AppKit
import CoreGraphics

/// Inserts text into the frontmost application at the cursor.
///
/// Requires the Accessibility permission (to post synthetic events into other apps). The
/// default `paste` method writes to the pasteboard, synthesizes ⌘V, then restores the
/// previous clipboard. The `keystroke` method types the text as Unicode for apps where
/// paste misbehaves.
@MainActor
public enum TextInserter {
    /// Inserts `text` using the given method.
    /// - Parameters:
    ///   - text: The text to insert.
    ///   - method: Paste or keystroke synthesis.
    ///   - restoreClipboard: Whether to restore the clipboard after a paste.
    public static func insert(_ text: String, method: InsertionMethod, restoreClipboard: Bool) {
        guard !text.isEmpty else { return }
        switch method {
        case .paste: pasteInsert(text, restore: restoreClipboard)
        case .keystroke: keystrokeInsert(text)
        }
    }

    /// Pastes `text` via the clipboard and a synthetic ⌘V, optionally restoring the clipboard.
    private static func pasteInsert(_ text: String, restore: Bool) {
        let pasteboard = NSPasteboard.general
        let snapshot = restore ? PasteboardSnapshot(pasteboard: pasteboard) : nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()
        if let snapshot {
            // Delay so the target app reads the pasteboard before we restore it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                snapshot.restore(to: pasteboard)
            }
        }
    }

    /// Posts a synthetic ⌘V key press to the HID event tap.
    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // ANSI 'v'
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Types `text` as a single Unicode keystroke burst.
    private static func keystrokeInsert(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(text.utf16)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        utf16.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
