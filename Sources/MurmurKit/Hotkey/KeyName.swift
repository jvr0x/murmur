import Foundation

/// Maps macOS virtual key codes to human-readable names for display in Settings.
public enum KeyName {
    /// Returns a readable name for a virtual key code (e.g. 61 → "Right Option ⌥").
    /// - Parameter keyCode: The virtual key code.
    /// - Returns: A display name, or `"Key #<code>"` for unmapped codes.
    public static func display(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key #\(keyCode)"
    }

    /// Virtual-key-code → display-name table (ANSI layout + modifiers).
    private static let names: [UInt16: String] = [
        // Modifiers
        55: "Left Command ⌘", 54: "Right Command ⌘",
        56: "Left Shift ⇧", 60: "Right Shift ⇧",
        58: "Left Option ⌥", 61: "Right Option ⌥",
        59: "Left Control ⌃", 62: "Right Control ⌃",
        57: "Caps Lock ⇪", 63: "fn",
        // Whitespace / navigation
        49: "Space", 36: "Return ↩", 76: "Enter ⌅", 48: "Tab ⇥", 53: "Escape ⎋",
        51: "Delete ⌫", 117: "Forward Delete ⌦",
        123: "← Left", 124: "→ Right", 125: "↓ Down", 126: "↑ Up",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // Letters
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        // Digits
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        // Punctuation
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".",
        44: "/", 50: "`",
    ]
}
