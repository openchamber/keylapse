/// The modifier keys of a Mac keyboard, in the order macOS prints them, with Fn last.
public enum ModifierFamily: String, CaseIterable, Codable, Hashable, Sendable {
    case control, option, shift, command, fn

    public var title: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Command"
        case .fn: return "Fn"
        }
    }

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .fn: return "Fn"
        }
    }

    /// Fn has one key; the others come in left and right pairs.
    public var hasSides: Bool { self != .fn }
}

/// Which physical key of a modifier pair; `either` accepts both.
public enum Side: String, Codable, Hashable, Sendable {
    case left, right, either

    public var title: String? {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .either: return nil
        }
    }
}

/// One modifier key that is held: its family and, when it matters, its side.
public struct HeldModifier: Hashable, Codable, Sendable {
    public var family: ModifierFamily
    public var side: Side

    public init(_ family: ModifierFamily, _ side: Side = .either) {
        self.family = family
        self.side = family.hasSides ? side : .either
    }

    /// macOS virtual key codes of the modifier keys.
    public init?(keyCode: UInt16) {
        switch keyCode {
        case 63: self.init(.fn)
        case 59: self.init(.control, .left)
        case 62: self.init(.control, .right)
        case 58: self.init(.option, .left)
        case 61: self.init(.option, .right)
        case 56: self.init(.shift, .left)
        case 60: self.init(.shift, .right)
        case 55: self.init(.command, .left)
        case 54: self.init(.command, .right)
        default: return nil
        }
    }

    /// "Left Command", "Control", "Fn".
    public var title: String { [side.title, family.title].compactMap { $0 }.joined(separator: " ") }
}

/// Modifier keys pressed together and released without any other key: Fn, Control+Fn,
/// Control+Option, Right Command… Sides match exactly as recorded; `either` takes both.
public struct ModifierChord: Hashable, Codable, Sendable {
    public private(set) var keys: [HeldModifier]

    public init(_ keys: [HeldModifier]) {
        let order = ModifierFamily.allCases
        var unique: [HeldModifier] = []
        for key in keys where !unique.contains(key) { unique.append(key) }
        self.keys = unique.sorted { a, b in
            let fa = order.firstIndex(of: a.family)!, fb = order.firstIndex(of: b.family)!
            return fa != fb ? fa < fb : a.side.rawValue < b.side.rawValue
        }
    }

    public init<S: Sequence>(_ keys: S) where S.Element == HeldModifier { self.init(Array(keys)) }

    public static let fn = ModifierChord([HeldModifier(.fn)])
    public static let controlFn = ModifierChord([HeldModifier(.control), HeldModifier(.fn)])

    public var isEmpty: Bool { keys.isEmpty }
    public var isFnAlone: Bool { self == .fn }
    public var families: Set<ModifierFamily> { Set(keys.map(\.family)) }

    /// Whether the keys held right now are exactly this chord. `held` carries the concrete
    /// side of each key; a key whose side the keyboard does not report comes as `either`.
    public func matches(_ held: Set<HeldModifier>) -> Bool {
        guard !keys.isEmpty, Set(held.map(\.family)) == families else { return false }
        for key in keys {
            let sides = Set(held.filter { $0.family == key.family }.map(\.side))
            switch key.side {
            case .either: continue
            case .left, .right:
                guard sides == [key.side] || sides == [.either] else { return false }
            }
        }
        // A side the chord does not name must not be doubled either (both Shifts, for example).
        for family in families where held.filter({ $0.family == family }).count > 1 {
            guard keys.filter({ $0.family == family }).count > 1 else { return false }
        }
        return true
    }

    /// "Control + Fn", "Left Command".
    public var title: String { keys.map(\.title).joined(separator: " + ") }
}

/// Modifiers held while a regular key is pressed. Fn counts, so Fn-Space is distinct from Space.
public struct ComboModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let command = Self(rawValue: 4)
    public static let shift = Self(rawValue: 8)
    public static let fn = Self(rawValue: 16)

    public init(_ family: ModifierFamily) {
        switch family {
        case .control: self = .control
        case .option: self = .option
        case .shift: self = .shift
        case .command: self = .command
        case .fn: self = .fn
        }
    }

    /// Mac order: Control, Option, Shift, Command, then Fn.
    public var ordered: [ModifierFamily] { ModifierFamily.allCases.filter { contains(Self($0)) } }

    public var symbols: String { ordered.map(\.symbol).joined() }
}

/// Which physical side of Control, Option, Shift and Command was pressed.
public struct ComboSides: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let leftControl = Self(rawValue: 1)
    public static let rightControl = Self(rawValue: 2)
    public static let leftOption = Self(rawValue: 4)
    public static let rightOption = Self(rawValue: 8)
    public static let leftCommand = Self(rawValue: 16)
    public static let rightCommand = Self(rawValue: 32)
    public static let leftShift = Self(rawValue: 64)
    public static let rightShift = Self(rawValue: 128)

    private static func pair(_ family: ModifierFamily) -> (Self, Self)? {
        switch family {
        case .control: return (.leftControl, .rightControl)
        case .option: return (.leftOption, .rightOption)
        case .command: return (.leftCommand, .rightCommand)
        case .shift: return (.leftShift, .rightShift)
        case .fn: return nil
        }
    }

    /// The side recorded for a family: left, right, or either when unknown or both.
    public func side(of family: ModifierFamily) -> Side {
        guard let (left, right) = Self.pair(family) else { return .either }
        switch (contains(left), contains(right)) {
        case (true, false): return .left
        case (false, true): return .right
        default: return .either
        }
    }

    /// Whether these pressed sides satisfy the recorded ones, family by family.
    public func satisfies(_ recorded: ComboSides, for modifiers: ComboModifiers) -> Bool {
        for family in modifiers.ordered {
            let wanted = recorded.side(of: family)
            guard wanted != .either else { continue }
            guard side(of: family) == wanted else { return false }
        }
        return true
    }
}

/// A regular key with modifiers, such as ⌥Space, ⌃⇧L or F13. Sides are honoured as recorded:
/// a combination recorded with the left Command key does not answer to the right one.
/// Without recorded sides either side works.
public struct KeyCombo: Equatable, Codable, Hashable, Sendable {
    /// macOS virtual key code of the main key.
    public var keyCode: UInt16
    public var modifiers: ComboModifiers
    /// The sides pressed when the combination was recorded; empty means any side.
    public var sides: ComboSides

    public init(keyCode: UInt16, modifiers: ComboModifiers, sides: ComboSides = []) {
        self.keyCode = keyCode
        let ignoresFn = Self.functionKeys.contains(keyCode) || Self.navigationKeys.contains(keyCode)
        self.modifiers = ignoresFn ? modifiers.subtracting(.fn) : modifiers
        self.sides = sides
    }

    enum CodingKeys: String, CodingKey { case keyCode, modifiers, sides }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(keyCode: try container.decode(UInt16.self, forKey: .keyCode),
                  modifiers: try container.decode(ComboModifiers.self, forKey: .modifiers),
                  sides: try container.decodeIfPresent(ComboSides.self, forKey: .sides) ?? [])
    }

    /// Virtual key codes of F1–F19.
    public static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80]

    /// Arrows, Home/End, Page Up/Down and forward delete. macOS reports the Fn flag for
    /// these whether or not Fn is held, so the flag carries no information there.
    public static let navigationKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121, 117]

    public var isFunctionKey: Bool { Self.functionKeys.contains(keyCode) }

    /// Keys whose Fn flag must be ignored: F-keys (the "Use F1, F2… as standard function keys"
    /// setting decides whether Fn is reported) and navigation keys.
    public var ignoresFn: Bool { isFunctionKey || Self.navigationKeys.contains(keyCode) }

    /// A bare letter would hijack typing; a combination needs a modifier unless it is an F-key.
    public var isValid: Bool { !modifiers.isEmpty || isFunctionKey }

    public func matches(keyCode: UInt16, modifiers pressed: ComboModifiers, sides pressedSides: ComboSides = []) -> Bool {
        guard keyCode == self.keyCode, (ignoresFn ? pressed.subtracting(.fn) : pressed) == modifiers else { return false }
        return pressedSides.satisfies(sides, for: modifiers)
    }

    /// The side recorded for a modifier of this combination.
    public func side(of family: ModifierFamily) -> Side { sides.side(of: family) }
}

extension KeyCombo {
    /// Combinations macOS itself reacts to. Keylapse can still take them over, but the user
    /// should know what stops working while it runs.
    public var systemUse: String? {
        guard keyCode == 49 else { return nil }  // Space
        switch modifiers.subtracting(.fn) {
        case [.command]: return "Spotlight"
        case [.control], [.control, .option]: return "the macOS input source switch"
        case [.control, .command]: return "the emoji picker"
        case [.option, .command]: return "Finder search"
        default: return nil
        }
    }
}

/// What a shortcut is: modifier keys tapped together, or a key combination.
public enum Trigger: Hashable, Codable, Sendable {
    case modifiers(ModifierChord)
    case combo(KeyCombo)

    public var isValid: Bool {
        switch self {
        case .modifiers(let chord): return !chord.isEmpty
        case .combo(let combo): return combo.isValid
        }
    }

    public var chord: ModifierChord? {
        if case .modifiers(let chord) = self { return chord }
        return nil
    }

    public var combo: KeyCombo? {
        if case .combo(let combo) = self { return combo }
        return nil
    }

    public var isFnAlone: Bool { chord?.isFnAlone ?? false }

    /// Whether Fn is one of the keys to press. F-keys and navigation keys carry the Fn flag
    /// whether or not Fn is held, so they do not count.
    public var usesFn: Bool {
        switch self {
        case .modifiers(let chord): return chord.families.contains(.fn)
        case .combo(let combo): return combo.modifiers.contains(.fn) && !combo.ignoresFn
        }
    }
}

/// The user's two shortcuts. They are independent: each is whatever was recorded for it,
/// and the only rule is that they differ.
public struct Shortcut: Equatable, Codable, Sendable {
    public var switchTrigger: Trigger
    public var correction: Trigger

    public static let standard = Shortcut(switchTrigger: .modifiers(.fn), correction: .modifiers(.controlFn))

    public init(switchTrigger: Trigger, correction: Trigger) {
        self.switchTrigger = switchTrigger
        self.correction = correction
    }

    public var usesCombos: Bool { switchTrigger.combo != nil || correction.combo != nil }

    public var isValid: Bool { switchTrigger.isValid && correction.isValid && switchTrigger != correction }

    /// Fn is not used for typing, so it may switch on press. Any other modifier chord takes
    /// part in combinations such as ⌥e, so it waits for release to avoid switching mid-keystroke.
    public func switchesOnRelease(preference: Bool) -> Bool {
        !switchTrigger.isFnAlone || preference
    }

    /// Any shortcut with Fn in it depends on the macOS "Press Globe key to" setting being Do
    /// Nothing: while macOS keeps the key for an action of its own, a chord such as Command + Fn
    /// does not reach Keylapse either.
    public var needsFnSystemAction: Bool { switchTrigger.usesFn || correction.usesFn }
}
