/// Works out which layout a piece of text was typed on, without guessing.
///
/// First the obvious: every layout that cannot type one of the text's letters is ruled out.
/// One layout left is the answer, whatever layout is active. Several left: the layouts the
/// neighbouring words were typed on decide, then the active layout if it is one of them;
/// otherwise nobody can tell, and the caller says so instead of picking one. A word with a
/// letter none of the layouts has on its plain or Shift keys rules them all out, so text is
/// refused rather than left half converted. (Letters reached with Option do not count:
/// mistyped text is not typed with Option, and the Ukrainian layouts reach ъ, ы, э, ё that way.)
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

    /// Which single layout typed the whole text, letters of all its words taken together.
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

    /// A stretch of the text typed on one layout. Runs joined together give the text back.
    public struct Run: Equatable {
        public let text: String
        public let sourceID: String
        public init(text: String, sourceID: String) {
            self.text = text
            self.sourceID = sourceID
        }
    }

    public enum Split: Equatable {
        /// Every word has its layout; neighbouring runs always differ in layout.
        case runs([Run])
        /// A word fits several layouts and neither its neighbours nor the active layout settle it.
        case ambiguous
        /// A word no single layout can type.
        case impossible
        case noLetters
    }

    /// The text word by word, each word with the layout that typed it. Words are decided by
    /// their own letters first; a word that fits several layouts takes the one its neighbours
    /// were typed on when that singles one out, then the active layout, and is otherwise
    /// ambiguous. Spaces, punctuation and digits go with the word before them (the first word
    /// when there is none), so they are converted on the same keys as that word.
    public static func split(_ text: String, layouts: [(id: String, alphabet: String)], activeID: String) -> Split {
        let alphabets = layouts.map { (id: $0.id, letters: Set($0.alphabet)) }
        var words: [(text: String, candidates: [String])] = []
        var current = ""
        var inWord = false
        for character in text {
            let wordCharacter = !character.isWhitespace
            if wordCharacter != inWord && !current.isEmpty {
                words.append((current, []))
                current = ""
            }
            inWord = wordCharacter
            current.append(character)
        }
        if !current.isEmpty { words.append((current, [])) }

        for index in words.indices {
            let letters = Set(LayoutAlphabet.derive(from: words[index].text))
            words[index].candidates = letters.isEmpty ? [] : alphabets.filter { letters.isSubset(of: $0.letters) }.map(\.id)
            if !letters.isEmpty && words[index].candidates.isEmpty { return .impossible }
        }
        let lettered = words.indices.filter { !words[$0].candidates.isEmpty }
        guard !lettered.isEmpty else { return .noLetters }

        var decided: [Int: String] = [:]
        for index in lettered where words[index].candidates.count == 1 { decided[index] = words[index].candidates[0] }
        let known = Set(decided.values)
        for index in lettered where decided[index] == nil {
            let candidates = words[index].candidates
            let fitting = candidates.filter(known.contains)
            if fitting.count == 1 { decided[index] = fitting[0] }
            else if candidates.contains(activeID) { decided[index] = activeID }
            else { return .ambiguous }
        }

        var runs: [Run] = []
        var sourceID = decided[lettered[0]]!
        for index in words.indices {
            if let own = decided[index] { sourceID = own }
            if let last = runs.last, last.sourceID == sourceID {
                runs[runs.count - 1] = Run(text: last.text + words[index].text, sourceID: sourceID)
            } else {
                runs.append(Run(text: words[index].text, sourceID: sourceID))
            }
        }
        return .runs(runs)
    }
}
