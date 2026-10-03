import Carbon
import Cocoa
import KeylapseCore

/// Human names for keys and shortcuts, for keycaps, hints and the menu bar tooltip.
enum KeyNames {
    private static let special: [UInt16: String] = [
        49: "space", 36: "return", 76: "enter", 48: "tab", 53: "esc", 51: "delete", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "home", 119: "end", 116: "pg up", 121: "pg dn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19"
    ]

    /// What is printed on the key: special names, or the unmodified character of the current layout.
    static func name(for keyCode: UInt16) -> String {
        if let name = special[keyCode] { return name }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let text = InputSources.translate(source, key: keyCode, action: kUCKeyActionDisplay)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "key \(keyCode)" : text.uppercased()
    }

    /// "⌥ Space", "⌃⇧ L", "F13"; side-specific combinations read "Left ⌘ Space".
    static func title(_ combo: KeyCombo) -> String {
        let key = name(for: combo.keyCode).capitalized
        let sided = combo.modifiers.ordered.contains { combo.side(of: $0) != .either }
        guard sided else {
            let symbols = combo.modifiers.symbols
            return symbols.isEmpty ? key : "\(symbols) \(key)"
        }
        let parts = combo.modifiers.ordered.map { family -> String in
            [combo.side(of: family).title, family.symbol].compactMap { $0 }.joined(separator: " ")
        } + [key]
        return parts.joined(separator: " ")
    }

    /// "⌃ + Fn", "Right ⌘", "⌥ Space".
    static func symbols(_ trigger: Trigger) -> String {
        switch trigger {
        case .modifiers(let chord):
            return chord.keys.map { [$0.side.title, $0.family.symbol].compactMap { $0 }.joined(separator: " ") }.joined(separator: " + ")
        case .combo(let combo):
            return title(combo)
        }
    }

    /// "Control + Fn", "Right Command", "⌥ Space": what the Settings hint names.
    static func title(_ trigger: Trigger) -> String {
        switch trigger {
        case .modifiers(let chord): return chord.title
        case .combo(let combo): return title(combo)
        }
    }

    /// Menu bar tooltip lines, e.g. "Switch: Fn" and "Correct: ⌃ + Fn".
    static func summary(_ shortcut: Shortcut) -> String {
        "Switch: \(symbols(shortcut.switchTrigger))\nCorrect: \(symbols(shortcut.correction))"
    }
}
