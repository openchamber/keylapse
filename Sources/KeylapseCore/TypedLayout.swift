/// Works out which layout a piece of text was typed on, without guessing.
///
/// First the obvious: every layout that cannot type one of the text's letters is ruled out.
/// One layout left is the answer, whatever layout is active. Several left: the active layout
/// decides if it is one of them; otherwise nobody can tell, and the caller says so instead of
/// picking one. A letter none of the layouts has on its plain or Shift keys rules them all out,
/// so text is refused rather than left half converted. (Letters reached with Option do not
/// count: mistyped text is not typed with Option, and the Ukrainian layouts reach ъ, ы, э, ё
/// that way.)
public enum TypedLayout {
    public enum Choice: Equatable {
        case source(String)
        /// Several layouts could have typed it and the active one is not among them.
        case ambiguous
        /// No single layout has all of these letters (two alphabets mixed, or a letter only an
        /// uncorrectable layout has).
        case impossible
        case noLetters
    }

    /// - Parameters:
    ///   - layouts: the layouts that can be corrected, with their alphabets, in list order.
    public static func choose(for text: String, layouts: [(id: String, alphabet: String)], activeID: String) -> Choice {
        let letters = Set(LayoutAlphabet.derive(from: text))
        guard !letters.isEmpty else { return .noLetters }
        let candidates = layouts.filter { letters.isSubset(of: Set($0.alphabet)) }
        switch candidates.count {
        case 0: return .impossible
        case 1: return .source(candidates[0].id)
        default: return candidates.contains { $0.id == activeID } ? .source(activeID) : .ambiguous
        }
    }
}
