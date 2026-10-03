/// The letters a layout can type on its base and Shift layers, in both cases.
/// Derived from the layout's own table, so no per-language list is needed.
public enum LayoutAlphabet {
    /// Keeps letters only, drops duplicates, and returns a stable lowercase string.
    public static func derive<S: Sequence>(from characters: S) -> String where S.Element == Character {
        var seen = Set<Character>()
        var letters: [Character] = []
        for character in characters where character.isLetter {
            for lowered in String(character).lowercased() {
                // Turkish İ lowercases to "i" plus a combining dot; keep the plain base letter.
                let variant = lowered.unicodeScalars.count > 1 ? Character(String(lowered.unicodeScalars.first!)) : lowered
                if seen.insert(variant).inserted { letters.append(variant) }
            }
        }
        return String(letters.sorted())
    }

    /// Too few letters means the table is not a typing layout, e.g. a symbol or numeric layout.
    public static let minimumLetters = 10
}
