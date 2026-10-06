/// Works out which layout a piece of text was typed on, word by word, without guessing.
///
/// First the obvious: every layout that cannot type one of the word's letters is ruled out.
/// One layout left is the answer, whatever layout is active. Several left: the layouts the
/// neighbouring words were typed on decide, then the active layout if it is one of them. When
/// the layouts left would type the word on the same keys it makes no difference which one it
/// was, so the first is taken; otherwise nobody can tell, and the caller says so instead of
/// picking one. A word with a letter none of the layouts has on its plain or Shift keys rules
/// them all out, so text is refused rather than left half converted. (Letters reached with
/// Option do not count: mistyped text is not typed with Option, and the Ukrainian layouts
/// reach ъ, ы, э, ё that way.)
public enum TypedLayout {
    /// A layout that can be corrected: its letters, and the key each one sits on.
    public struct Layout {
        public let id: String
        public let alphabet: String
        /// The key (and layer) that types each lowercase letter; empty when unknown, in
        /// which case the layout never counts as typing a word the same way as another.
        public let positions: [Character: Int]
        public init(id: String, alphabet: String, positions: [Character: Int] = [:]) {
            self.id = id
            self.alphabet = alphabet
            self.positions = positions
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
        /// A word fits several layouts that would type it differently, and neither its
        /// neighbours nor the active layout settle it.
        case ambiguous
        /// A word no single layout can type.
        case impossible
        case noLetters
    }

    /// The text word by word, each word with the layout that typed it. Spaces, punctuation
    /// and digits go with the word before them (the first word when there is none), so they
    /// are converted on the same keys as that word.
    /// - Parameters:
    ///   - layouts: the layouts that can be corrected, in list order.
    public static func split(_ text: String, layouts: [Layout], activeID: String) -> Split {
        let alphabets = layouts.map { Set($0.alphabet) }
        var words: [(text: String, letters: Set<Character>, candidates: [Int])] = []
        var current = ""
        var inWord = false
        for character in text {
            let wordCharacter = !character.isWhitespace
            if wordCharacter != inWord && !current.isEmpty {
                words.append((current, [], []))
                current = ""
            }
            inWord = wordCharacter
            current.append(character)
        }
        if !current.isEmpty { words.append((current, [], [])) }

        for index in words.indices {
            let letters = Set(LayoutAlphabet.derive(from: words[index].text))
            words[index].letters = letters
            words[index].candidates = letters.isEmpty ? [] : layouts.indices.filter { letters.isSubset(of: alphabets[$0]) }
            if !letters.isEmpty && words[index].candidates.isEmpty { return .impossible }
        }
        let lettered = words.indices.filter { !words[$0].candidates.isEmpty }
        guard !lettered.isEmpty else { return .noLetters }

        var decided: [Int: Int] = [:]
        for index in lettered where words[index].candidates.count == 1 { decided[index] = words[index].candidates[0] }
        let known = Set(decided.values)
        for index in lettered where decided[index] == nil {
            let candidates = words[index].candidates
            let fitting = candidates.filter(known.contains)
            if fitting.count == 1 { decided[index] = fitting[0] }
            else if let active = candidates.first(where: { layouts[$0].id == activeID }) { decided[index] = active }
            else if typedAlike(words[index].letters, on: candidates.map { layouts[$0] }) { decided[index] = fitting.first ?? candidates[0] }
            else { return .ambiguous }
        }

        var runs: [Run] = []
        var sourceID = layouts[decided[lettered[0]]!].id
        for index in words.indices {
            if let own = decided[index] { sourceID = layouts[own].id }
            if let last = runs.last, last.sourceID == sourceID {
                runs[runs.count - 1] = Run(text: last.text + words[index].text, sourceID: sourceID)
            } else {
                runs.append(Run(text: words[index].text, sourceID: sourceID))
            }
        }
        return .runs(runs)
    }

    /// Whether every one of these layouts types each letter on the same key, so a word of
    /// them converts to the same text whichever layout it is taken to be typed on.
    private static func typedAlike(_ letters: Set<Character>, on layouts: [Layout]) -> Bool {
        guard let first = layouts.first else { return false }
        return letters.allSatisfy { letter in
            guard let key = first.positions[letter] else { return false }
            return layouts.dropFirst().allSatisfy { $0.positions[letter] == key }
        }
    }
}
