import Foundation

public enum ConversionError: Error, LocalizedError {
    case noLetters, mixedScripts, unmappable(Character)
    public var errorDescription: String? {
        switch self {
        case .noLetters: return "Select text containing letters from the selected layouts."
        case .mixedScripts: return "The selection mixes both alphabets. Select only the text typed in the wrong layout."
        case .unmappable(let character): return "The selected layouts have no mapping for \"\(character)\"."
        }
    }
}

/// Two layouts matched key by key: what each key of the first types on the second and back.
/// The mappings are keyboard positions, not phonetic transliteration.
public struct LayoutPair {
    public let forward: [Character: Character]
    public let backward: [Character: Character]
    public let firstAlphabet: Set<Character>
    public let secondAlphabet: Set<Character>

    public init(forward: [Character: Character], backward: [Character: Character],
                firstAlphabet: String, secondAlphabet: String) {
        self.forward = forward
        self.backward = backward
        self.firstAlphabet = Set(firstAlphabet.lowercased() + firstAlphabet.uppercased())
        self.secondAlphabet = Set(secondAlphabet.lowercased() + secondAlphabet.uppercased())
    }

    private init(forward: [Character: Character], backward: [Character: Character],
                 firstAlphabet: Set<Character>, secondAlphabet: Set<Character>) {
        self.forward = forward
        self.backward = backward
        self.firstAlphabet = firstAlphabet
        self.secondAlphabet = secondAlphabet
    }

    /// The same pair seen from the second layout.
    public var reversed: LayoutPair {
        LayoutPair(forward: backward, backward: forward, firstAlphabet: secondAlphabet, secondAlphabet: firstAlphabet)
    }

    /// Text typed on the first layout, as the same keys type it on the second. The direction is
    /// the caller's decision and is never reversed here: text that holds no letter of the first
    /// layout, or a letter only the second one has, is refused.
    public func convert(_ text: String) throws -> String {
        guard text.contains(where: { firstAlphabet.contains($0) }) else { throw ConversionError.noLetters }
        guard !text.contains(where: { secondAlphabet.contains($0) && !firstAlphabet.contains($0) }) else {
            throw ConversionError.mixedScripts
        }
        let alphabet = firstAlphabet.union(secondAlphabet)
        return try String(text.map { character in
            if let converted = forward[character] { return converted }
            if alphabet.contains(character) { throw ConversionError.unmappable(character) }
            return character
        })
    }
}
