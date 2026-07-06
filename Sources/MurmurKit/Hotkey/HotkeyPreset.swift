import CoreGraphics
import Foundation

/// Ready-made hotkey choices offered in Settings (Spokenly-style), plus `custom`.
///
/// This is a presentation-layer convenience only: the persisted source of truth remains
/// ``AppConfig/hotkeyKeyCode`` + ``AppConfig/hotkeyModifiers``. The selected preset is
/// *derived* from those via ``detect(keyCode:modifiers:)``, so there is no separate
/// stored state to keep in sync (same pattern as ``LLMProvider``).
///
/// Note: a bare-modifier preset responds to **either side** of its key pair (e.g. the
/// Right Option preset also fires on Left Option) — detection tracks the high-level
/// modifier flag, which both sides set.
public enum HotkeyPreset: String, CaseIterable, Identifiable, Sendable {
    /// Hold/tap Right Option ⌥ (the app default).
    case rightOption
    /// Hold/tap Right Command ⌘.
    case rightCommand
    /// Hold/tap the fn / Globe key.
    case fnGlobe
    /// Hold/tap F20 (common on programmable keyboards).
    case f20
    /// Hold/tap F13.
    case f13
    /// Hold/tap Control + Space.
    case controlSpace
    /// Hold/tap Option + Space.
    case optionSpace
    /// Anything recorded manually with the key recorder.
    case custom

    /// Stable identity for SwiftUI pickers.
    public var id: String { rawValue }

    /// Human-readable name shown in the picker.
    public var displayName: String {
        switch self {
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        case .fnGlobe: return "fn / Globe 🌐"
        case .f20: return "F20"
        case .f13: return "F13"
        case .controlSpace: return "⌃ + Space"
        case .optionSpace: return "⌥ + Space"
        case .custom: return "Custom…"
        }
    }

    /// The combo this preset applies, or `nil` for ``custom`` (recorded manually).
    public var combo: (keyCode: UInt16, modifiers: UInt64)? {
        switch self {
        case .rightOption: return (61, 0)
        case .rightCommand: return (54, 0)
        case .fnGlobe: return (63, 0)
        case .f20: return (90, 0)
        case .f13: return (105, 0)
        case .controlSpace: return (49, CGEventFlags.maskControl.rawValue)
        case .optionSpace: return (49, CGEventFlags.maskAlternate.rawValue)
        case .custom: return nil
        }
    }

    /// Detects the preset matching a configured combo, falling back to ``custom``.
    /// - Parameters:
    ///   - keyCode: The configured primary key code.
    ///   - modifiers: The configured raw extra-modifier flags.
    /// - Returns: The matching preset, or ``custom`` if none matches.
    public static func detect(keyCode: UInt16, modifiers: UInt64) -> HotkeyPreset {
        for preset in HotkeyPreset.allCases {
            if let combo = preset.combo, combo.keyCode == keyCode, combo.modifiers == modifiers {
                return preset
            }
        }
        return .custom
    }
}
