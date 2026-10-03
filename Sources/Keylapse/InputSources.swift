import Carbon
import Foundation
import KeylapseCore

enum AppError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct KeyboardSource {
    let source: TISInputSource
    let id: String
    let name: String
    /// BCP 47 tag macOS reports for the source, e.g. "uk" or "pt-BR".
    let language: String
    /// Letters on the base and Shift layers; empty for input methods and non-letter layouts.
    let alphabet: String

    /// Languages the user has chosen not to correct, even though their layouts would work.
    static let excludedLanguages: Set<String> = ["ru"]

    var languageCode: String {
        language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
    }

    var supportsCorrection: Bool {
        alphabet.count >= LayoutAlphabet.minimumLetters && !Self.excludedLanguages.contains(languageCode)
    }

    /// The language as macOS names it in the user's locale, e.g. "Ukrainian"; falls back to the source name.
    var languageTitle: String {
        guard !languageCode.isEmpty, let title = Locale.current.localizedString(forLanguageCode: languageCode) else { return name }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// What distinguishes this layout from others of the same language, e.g. "U.S." or "Ukrainian-PC".
    var variantTitle: String? {
        guard languageTitle != name || id.hasPrefix("com.apple.keylayout.") else { return nil }
        var parts: [String] = []
        if name.caseInsensitiveCompare(languageTitle) != .orderedSame { parts.append(name) }
        if id.hasPrefix("com.apple.keylayout.") {
            let variant = String(id.dropFirst("com.apple.keylayout.".count))
            func normalized(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
            if normalized(variant) != normalized(name) { parts.append(variant) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var displayName: String {
        guard let variantTitle else { return languageTitle }
        return "\(languageTitle) · \(variantTitle)"
    }
}

final class InputSources {
    private(set) var sources: [KeyboardSource] = []
    private let includeDisabled: Bool
    init(includeDisabled: Bool = false) {
        self.includeDisabled = includeDisabled
        reload()
    }

    private func string(_ source: TISInputSource, _ key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    func reload() {
        guard let list = TISCreateInputSourceList(nil, includeDisabled)?.takeRetainedValue() as? [TISInputSource] else { return }
        let stillEnabled = includeDisabled ? nil : Self.enabledInputMethods()
        sources = list.compactMap { source in
            guard string(source, kTISPropertyInputSourceCategory) == kTISCategoryKeyboardInputSource as String,
                  let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selectable).takeUnretainedValue()) else { return nil }
            if !includeDisabled, let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
               !CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(enabled).takeUnretainedValue()) { return nil }
            // An input method removed in System Settings can linger in this process's list while
            // its helper is still running; the preference it was removed from is the truth.
            if let stillEnabled, Self.isInputMethod(source),
               !stillEnabled.contains(string(source, kTISPropertyInputSourceID)), !stillEnabled.contains(string(source, kTISPropertyBundleID)) {
                return nil
            }
            let languages: [String]
            if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
                languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
            } else { languages = [] }
            return KeyboardSource(source: source, id: string(source, kTISPropertyInputSourceID),
                                   name: string(source, kTISPropertyLocalizedName), language: languages.first ?? "",
                                   alphabet: alphabet(of: source))
        }
    }

    private static func isInputMethod(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
        return type == kTISTypeKeyboardInputMethodWithoutModes || type == kTISTypeKeyboardInputMethodModeEnabled || type == kTISTypeKeyboardInputMode
    }

    /// Input methods and modes listed in Keyboard → Input Sources (bundle ids and mode ids);
    /// nil when the preference cannot be read, in which case nothing is filtered.
    private static func enabledInputMethods() -> Set<String>? {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        guard let entries = CFPreferencesCopyAppValue("AppleEnabledInputSources" as CFString, domain) as? [[String: Any]] else { return nil }
        var ids: Set<String> = []
        for entry in entries {
            if let bundle = entry["Bundle ID"] as? String { ids.insert(bundle) }
            if let mode = entry["Input Mode"] as? String { ids.insert(mode) }
        }
        return ids
    }

    /// Letters reachable on the base and Shift layers of a keyboard-layout source.
    private func alphabet(of source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType),
              Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() == kTISTypeKeyboardLayout,
              TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { return "" }
        var characters: [Character] = []
        for shifted in [false, true] {
            for key in Self.letterKeys {
                if let character = character(source, key, shifted) { characters.append(character) }
            }
        }
        return LayoutAlphabet.derive(from: characters)
    }

    /// Physical keys that carry letters or punctuation on typing layouts, including the ISO extra key (10).
    private static let letterKeys: [UInt16] = Array(0...50) + [10]

    var currentID: String { string(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID) }

    func select(_ id: String) throws {
        guard let source = sources.first(where: { $0.id == id }), TISSelectInputSource(source.source) == noErr else {
            throw AppError.message("Could not select keyboard layout. Check Keyboard → Input Sources.")
        }
    }

    func enabledSources() -> [KeyboardSource] {
        reload()
        return sources
    }

    /// The layouts text can be corrected between, whatever is active right now.
    func supportedSources() throws -> [KeyboardSource] {
        reload()
        let supported = sources.filter(\.supportsCorrection)
        guard supported.count >= 2 else {
            throw AppError.message("Text correction needs two supported layouts. Add another in macOS Keyboard settings.")
        }
        return supported
    }

    /// The active layout, when it is of a language Keylapse does not correct and every letter
    /// of the text is one it types: the text is then taken to have been typed on it. Letters
    /// come first here too: text that layout cannot have typed (Greek, Latin, Cyrillic with
    /// і ї є ґ) has nothing to do with it and is corrected as usual.
    func uncorrectedSource(of text: String) -> KeyboardSource? {
        guard let current = sources.first(where: { $0.id == currentID }), KeyboardSource.excludedLanguages.contains(current.languageCode) else { return nil }
        let letters = Set(LayoutAlphabet.derive(from: text))
        return !letters.isEmpty && letters.isSubset(of: Set(current.alphabet)) ? current : nil
    }

    /// The layout the text was typed on, worked out from its letters first and from the active
    /// layout only when the letters leave more than one possibility. Throws what to tell the
    /// user when it cannot be known, or when it was typed on a layout that is not corrected.
    func typedSource(of text: String, among supported: [KeyboardSource]) throws -> KeyboardSource {
        if let current = uncorrectedSource(of: text) {
            throw AppError.message("Keylapse doesn’t correct \(current.languageTitle). Крим це Україна.")
        }
        let choice = TypedLayout.choose(for: text, layouts: supported.map { (id: $0.id, alphabet: $0.alphabet) }, activeID: currentID)
        switch choice {
        case .source(let id):
            guard let source = supported.first(where: { $0.id == id }) else { fallthrough }
            return source
        case .ambiguous:
            throw AppError.message("Switch to the layout used to type this text, then try again.")
        case .impossible:
            // Letters of two of the user's layouts together: the selection took in too much.
            // A letter none of the correctable layouts has is a different matter.
            let correctable = Set(supported.map(\.alphabet).joined())
            if Set(LayoutAlphabet.derive(from: text)).isSubset(of: correctable) {
                throw AppError.message("Select only the mistyped text.")
            }
            // Letters that exist only in a layout of an excluded language get the same answer as that layout.
            let excluded = Set(sources.filter { KeyboardSource.excludedLanguages.contains($0.languageCode) }.map(\.alphabet).joined())
            let onlyExcluded = !Set(LayoutAlphabet.derive(from: text)).intersection(excluded).subtracting(correctable).isEmpty
            throw AppError.message("Keylapse can’t correct some of these letters." + (onlyExcluded ? " Крим це Україна." : ""))
        case .noLetters:
            throw ConversionError.noLetters
        }
    }

    func toggle() throws {
        let selected = enabledSources()
        guard selected.count > 1 else { return }
        // A source macOS refuses to select (one just removed in System Settings can linger in
        // the list for a while) is stepped over, so the cycle never gets stuck in front of it.
        let cycle = try LayoutCycle(selected.map(\.id))
        var id = currentID
        for _ in 1..<selected.count {
            id = cycle.next(after: id)
            if (try? select(id)) != nil { return }
        }
        throw AppError.message("Could not select keyboard layout. Check Keyboard → Input Sources.")
    }

    /// How the keys of one layout map onto another. Read from the actual macOS layout
    /// tables, so variants such as Ukrainian-PC punctuation are honoured.
    func layoutPair(_ first: KeyboardSource, _ second: KeyboardSource) throws -> LayoutPair {
        guard first.supportsCorrection, second.supportsCorrection else {
            throw AppError.message("Text correction isn’t supported for these layouts yet.")
        }
        var forward: [Character: Character] = [:]
        var backward: [Character: Character] = [:]
        // First occurrence wins: prefer unshifted physical keys over duplicates.
        for shifted in [false, true] {
            for key in UInt16(0)...UInt16(50) {
                guard let a = character(first.source, key, shifted), let b = character(second.source, key, shifted) else { continue }
                if forward[a] == nil { forward[a] = b }
                if backward[b] == nil { backward[b] = a }
            }
            // ISO extra key; includes ґ on some Ukrainian layouts.
            if let a = character(first.source, 10, shifted), let b = character(second.source, 10, shifted) {
                if forward[a] == nil { forward[a] = b }
                if backward[b] == nil { backward[b] = a }
            }
        }
        // Fill missing letters from Option layers without replacing base-layer mappings.
        let firstLetters = Set(first.alphabet + first.alphabet.uppercased())
        let secondLetters = Set(second.alphabet + second.alphabet.uppercased())
        for optionShift in [false, true] {
            for key in UInt16(0)...UInt16(50) {
                guard let a = character(first.source, key, optionShift, option: true),
                       let b = character(second.source, key, optionShift, option: true) else { continue }
                if secondLetters.contains(b), backward[b] == nil { backward[b] = a }
                if firstLetters.contains(a), forward[a] == nil { forward[a] = b }
                // Preserve the existing English/Ukrainian ґ round trip.
                if secondLetters.contains(b), forward[a] == nil { forward[a] = b }
                if firstLetters.contains(a), backward[b] == nil { backward[b] = a }
            }
        }
        guard !forward.isEmpty && !backward.isEmpty else { throw AppError.message("These layouts do not provide a keyboard mapping.") }
        return LayoutPair(forward: forward, backward: backward,
                          firstAlphabet: first.alphabet, secondAlphabet: second.alphabet)
    }

    private func character(_ source: TISInputSource, _ key: UInt16, _ shifted: Bool, option: Bool = false) -> Character? {
        let text = Self.translate(source, key: key, modifiers: (shifted ? shiftKey : 0) | (option ? optionKey : 0))
        guard let text, text.count == 1, let character = text.first,
              !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return character
    }

    /// What a key types on a keyboard layout with the given Carbon modifiers (`shiftKey`, `cmdKey`…),
    /// dead keys ignored. Nil for a source without a key table, or a key that types nothing.
    static func translate(_ source: TISInputSource, key: UInt16, modifiers: Int = 0, action: Int = kUCKeyActionDown) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var state: UInt32 = 0
        var count = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, key, UInt16(action), UInt32(modifiers >> 8) & 0xFF,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &state, buffer.count, &count, &buffer)
        guard status == noErr, count > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: count)
    }
}
