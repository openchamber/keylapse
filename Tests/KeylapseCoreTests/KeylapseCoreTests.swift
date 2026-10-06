import Foundation
import Testing
import KeylapseCore

struct TestFailure: Error {}

struct GestureTests {
    static let fn: Set<HeldModifier> = [HeldModifier(.fn)]
    static let control: Set<HeldModifier> = [HeldModifier(.control, .left)]
    static let both: Set<HeldModifier> = [HeldModifier(.fn), HeldModifier(.control, .left)]
    static let three: Set<HeldModifier> = [HeldModifier(.fn), HeldModifier(.control, .left), HeldModifier(.shift, .left)]

    @Test func plainFnIsImmediateAndSingle() {
        var gesture = KeyGesture()
        #expect(gesture.modifiersChanged(Self.fn) == [.switchLayout])
        #expect(gesture.modifiersChanged(Self.fn) == [])
        #expect(gesture.modifiersChanged([]) == [])
    }

    @Test func controlFirstDoesNotSwitch() {
        var gesture = KeyGesture()
        #expect(gesture.modifiersChanged(Self.control) == [])
        #expect(gesture.modifiersChanged(Self.both) == [])
        #expect(gesture.modifiersChanged(Self.control) == [])
        #expect(gesture.modifiersChanged([]) == [.correctSelection])
    }

    @Test func fnFirstRestoresAndWaitsForBothKeysUp() {
        var gesture = KeyGesture()
        #expect(gesture.modifiersChanged(Self.fn) == [.switchLayout])
        #expect(gesture.modifiersChanged(Self.both) == [.restoreLayout])
        #expect(gesture.modifiersChanged(Self.fn) == [])
        #expect(gesture.modifiersChanged([]) == [.correctSelection])
    }

    @Test func thirdKeyCancelsCorrectionAndDoesNotSwallowSystemShortcut() {
        var gesture = KeyGesture()
        _ = gesture.modifiersChanged(Self.control)
        _ = gesture.modifiersChanged(Self.both)
        #expect(gesture.otherKeyPressed() == [])
        #expect(gesture.modifiersChanged([]) == [])
    }

    @Test func fnLetterShortcutRestoresOriginalLayout() {
        var gesture = KeyGesture()
        _ = gesture.modifiersChanged(Self.fn)
        #expect(gesture.otherKeyPressed() == [.restoreLayout])
        #expect(gesture.modifiersChanged([]) == [])
    }

    @Test func additionalModifierCancelsAndNextGestureStillWorks() {
        var gesture = KeyGesture()
        _ = gesture.modifiersChanged(Self.both)
        _ = gesture.modifiersChanged(Self.three)
        #expect(gesture.modifiersChanged([]) == [])
        _ = gesture.modifiersChanged(Self.both)
        #expect(gesture.modifiersChanged([]) == [.correctSelection])
    }

    @Test func optionalReleaseSwitchSkipsCombinations() {
        var gesture = KeyGesture()
        gesture.switchOnRelease = true
        #expect(gesture.modifiersChanged(Self.fn) == [])
        #expect(gesture.modifiersChanged([]) == [.switchLayout])
        _ = gesture.modifiersChanged(Self.fn)
        _ = gesture.otherKeyPressed()
        #expect(gesture.modifiersChanged([]) == [])
        _ = gesture.modifiersChanged(Self.both)
        #expect(gesture.modifiersChanged([]) == [.correctSelection])
    }

    @Test func anyChordsWorkOnRelease() {
        // Right Command switches; Control + Option corrects. Neither is Fn, so both wait for release.
        let rightCommand = ModifierChord([HeldModifier(.command, .right)])
        let controlOption = ModifierChord([HeldModifier(.control), HeldModifier(.option)])
        var gesture = KeyGesture(switchChord: rightCommand, correctionChord: controlOption)
        gesture.switchOnRelease = true
        #expect(gesture.modifiersChanged([HeldModifier(.command, .right)]) == [])
        #expect(gesture.modifiersChanged([]) == [.switchLayout])
        // The left key is a different key.
        _ = gesture.modifiersChanged([HeldModifier(.command, .left)])
        #expect(gesture.modifiersChanged([]) == [])
        // Control + Option in either order, from either side.
        _ = gesture.modifiersChanged([HeldModifier(.option, .right)])
        _ = gesture.modifiersChanged([HeldModifier(.option, .right), HeldModifier(.control, .left)])
        _ = gesture.modifiersChanged([HeldModifier(.control, .left)])
        #expect(gesture.modifiersChanged([]) == [.correctSelection])
        // A combination shortcut leaves no chord to match.
        gesture.switchChord = nil
        _ = gesture.modifiersChanged([HeldModifier(.command, .right)])
        #expect(gesture.modifiersChanged([]) == [])
    }
}

struct ConversionTests {
    /// Hand-written U.S. ↔ Ukrainian table; the app reads the real macOS tables instead.
    private let pair: LayoutPair = {
        let en = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,./QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?")
        let uk = Array("йцукенгшщзхїфівапролджєячсмитьбю.ЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,")
        return LayoutPair(forward: Dictionary(uniqueKeysWithValues: zip(en, uk)),
                          backward: Dictionary(uniqueKeysWithValues: zip(uk, en)),
                          firstAlphabet: "abcdefghijklmnopqrstuvwxyz", secondAlphabet: "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя")
    }()

    @Test func bothDirectionsAndCase() throws {
        #expect(try pair.convert("ghbdsn") == "привіт")
        #expect(try pair.reversed.convert("Руддщ") == "Hello")
        #expect(try pair.convert("GHBDsN") == "ПРИВіТ")
    }

    @Test func whitespaceEmojiAndPunctuation() throws {
        #expect(try pair.convert("rj;ty\n\t🙂 123") == "кожен\n\t🙂 123")
        #expect(try pair.convert("ghbdsn/") == "привіт.")
    }

    @Test func mixedTextIsNotSilentlyCorrupted() {
        #expect(throws: ConversionError.self) { try pair.convert("hello привіт") }
        #expect(throws: ConversionError.self) { try pair.reversed.convert("hello привіт") }
        #expect(throws: ConversionError.self) { try pair.convert("123 🙂") }
        // No key of the hand-written table types ґ.
        #expect(throws: ConversionError.self) { try pair.reversed.convert("ґ") }
    }

    @Test func theDirectionIsNeverReversed() throws {
        #expect(throws: ConversionError.self) { try pair.convert("привіт") }
        #expect(throws: ConversionError.self) { try pair.reversed.convert("hello") }
    }

    @Test func sharedAlphabetsConvertEitherWay() throws {
        let pair = LayoutPair(forward: ["y": "z", "z": "y", "a": "a"],
                              backward: ["z": "y", "y": "z", "a": "a"],
                              firstAlphabet: "abcdefghijklmnopqrstuvwxyz",
                              secondAlphabet: "abcdefghijklmnopqrstuvwxyzäöüß")
        #expect(try pair.convert("yaz") == "zay")
        #expect(try pair.reversed.convert("zay") == "yaz")
        // ä is a letter of the second layout only, so it cannot have been typed on the first.
        #expect(throws: ConversionError.self) { try pair.convert("ä") }
    }

    @Test func sharedAlphabetDirectionsAreNotInterchangeable() throws {
        let pair = LayoutPair(forward: ["a": "q", "q": "w", "w": "a"],
                              backward: ["q": "a", "w": "q", "a": "w"],
                              firstAlphabet: "aqw", secondAlphabet: "aqw")
        #expect(try pair.convert("a") == "q")
        #expect(try pair.reversed.convert("a") == "w")
    }
}

struct LayoutAlphabetTests {
    @Test func keepsLettersOnlyInOneCaseWithoutDuplicates() {
        let typed: [Character] = Array("qwertyQWERTY123;'[]ї€") + ["ß", "ẞ", "İ", "i"]
        let alphabet = LayoutAlphabet.derive(from: typed)
        #expect(alphabet.contains("q") && alphabet.contains("y") && alphabet.contains("ї"))
        #expect(!alphabet.contains("Q") && !alphabet.contains("1") && !alphabet.contains(";") && !alphabet.contains("€"))
        #expect(alphabet.filter { $0 == "e" }.count == 1)
        #expect(alphabet.contains("ß"))
        #expect(!alphabet.contains("i̇"))
        #expect(alphabet.filter { $0 == "i" }.count == 1)
    }

    @Test func symbolLayoutsFallBelowTheMinimum() {
        #expect(LayoutAlphabet.derive(from: Array("1234567890-=[]")).count < LayoutAlphabet.minimumLetters)
        #expect(LayoutAlphabet.derive(from: Array("abcdefghijklmnopqrstuvwxyz")).count >= LayoutAlphabet.minimumLetters)
    }
}

struct LayoutCycleTests {
    @Test func cyclesInOrderAndRecoversFromOutsideSource() throws {
        let three = try LayoutCycle(["en", "uk", "de"])
        #expect(three.next(after: "en") == "uk")
        #expect(three.next(after: "uk") == "de")
        #expect(three.next(after: "de") == "en")
        #expect(three.next(after: "outside") == "en")
        let two = try LayoutCycle(["uk", "en"])
        #expect(two.next(after: "en") == "uk")
        let many = try LayoutCycle((0..<20).map(String.init))
        #expect(many.next(after: "19") == "0")
    }

    @Test func rejectsInvalidSelections() {
        #expect(throws: LayoutCycle.InvalidSelection.self) { try LayoutCycle(["en"]) }
        #expect(throws: LayoutCycle.InvalidSelection.self) { try LayoutCycle(["en", "uk", "en"]) }
    }
}

struct FnSystemActionTests {
    @Test func typePrecedesLegacyAndUnknownIsHonest() {
        #expect(FnSystemAction.resolve(type: 1, legacy: 0) == .conflict)
        #expect(FnSystemAction.resolve(type: 0, legacy: 1) == .ready)
        #expect(FnSystemAction.resolve(type: nil, legacy: 0) == .ready)
        #expect(FnSystemAction.resolve(type: nil, legacy: 2) == .conflict)
        #expect(FnSystemAction.resolve(type: nil, legacy: nil) == .unknown)
        #expect(FnSystemAction.resolve(type: -1, legacy: 0) == .unknown)
    }
}

struct ShortcutTests {
    static let rightCommand = Trigger.modifiers(ModifierChord([HeldModifier(.command, .right)]))
    static let controlOption = Trigger.modifiers(ModifierChord([HeldModifier(.control, .left), HeldModifier(.option, .left)]))

    @Test func standardIsFnWithControlFn() {
        #expect(Shortcut.standard.switchTrigger == .modifiers(.fn))
        #expect(Shortcut.standard.correction == .modifiers(.controlFn))
        #expect(Shortcut.standard.isValid)
        #expect(Shortcut.standard.needsFnSystemAction)
        #expect(!Shortcut.standard.usesCombos)
    }

    @Test func theTwoShortcutsAreIndependentButMustDiffer() {
        let same = Shortcut(switchTrigger: Self.rightCommand, correction: Self.rightCommand)
        #expect(!same.isValid)
        let different = Shortcut(switchTrigger: Self.rightCommand, correction: Self.controlOption)
        #expect(different.isValid && !different.needsFnSystemAction)
        // Any mix of chords and combinations is fine.
        let mixed = Shortcut(switchTrigger: .combo(KeyCombo(keyCode: 49, modifiers: .option)), correction: .modifiers(.controlFn))
        // Fn inside a chord needs the macOS Fn action out of the way just as Fn alone does.
        #expect(mixed.isValid && mixed.usesCombos && mixed.needsFnSystemAction)
        let empty = Shortcut(switchTrigger: .modifiers(ModifierChord([])), correction: Self.controlOption)
        #expect(!empty.isValid)
    }

    @Test func onlyFnAloneMaySwitchOnPress() {
        #expect(!Shortcut.standard.switchesOnRelease(preference: false))
        #expect(Shortcut.standard.switchesOnRelease(preference: true))
        let option = Shortcut(switchTrigger: .modifiers(ModifierChord([HeldModifier(.option, .right)])), correction: .modifiers(.controlFn))
        #expect(option.switchesOnRelease(preference: false))
        // The correction still has Fn in it, so the macOS Fn action still matters.
        #expect(option.needsFnSystemAction)
    }

    @Test func chordsMatchSidesAsRecorded() {
        let either = ModifierChord([HeldModifier(.control), HeldModifier(.fn)])
        #expect(either.matches([HeldModifier(.control, .left), HeldModifier(.fn)]))
        #expect(either.matches([HeldModifier(.control, .right), HeldModifier(.fn)]))
        #expect(!either.matches([HeldModifier(.fn)]))
        #expect(!either.matches([HeldModifier(.control, .left), HeldModifier(.fn), HeldModifier(.shift, .left)]))
        let left = ModifierChord([HeldModifier(.command, .left)])
        #expect(left.matches([HeldModifier(.command, .left)]))
        #expect(!left.matches([HeldModifier(.command, .right)]))
        #expect(!left.matches([HeldModifier(.command, .left), HeldModifier(.command, .right)]))
        // A keyboard that reports no side bits still works.
        #expect(left.matches([HeldModifier(.command, .either)]))
        // Keys are kept once and in Mac order, whatever the order pressed.
        let chord = ModifierChord([HeldModifier(.fn), HeldModifier(.option, .left), HeldModifier(.control, .left), HeldModifier(.fn)])
        #expect(chord.keys.map(\.family) == [.control, .option, .fn])
        #expect(chord.title == "Left Control + Left Option + Fn")
    }

    @Test func comboNeedsModifierUnlessFunctionKey() {
        #expect(!KeyCombo(keyCode: 49, modifiers: []).isValid)          // bare Space
        #expect(KeyCombo(keyCode: 49, modifiers: .option).isValid)       // ⌥Space
        #expect(KeyCombo(keyCode: 105, modifiers: []).isValid)           // F13
        #expect(!KeyCombo(keyCode: 0, modifiers: []).isValid)            // bare A
    }

    @Test func fnFlagIsIgnoredWhereTheSystemSetsItAnyway() {
        let f1 = KeyCombo(keyCode: 122, modifiers: [.fn])
        #expect(f1.modifiers.isEmpty)
        #expect(f1.matches(keyCode: 122, modifiers: []))
        #expect(f1.matches(keyCode: 122, modifiers: .fn))
        #expect(!f1.matches(keyCode: 122, modifiers: .shift))
        let fnSpace = KeyCombo(keyCode: 49, modifiers: .fn)
        #expect(fnSpace.isValid)
        #expect(fnSpace.matches(keyCode: 49, modifiers: .fn))
        #expect(!fnSpace.matches(keyCode: 49, modifiers: []))
    }

    @Test func combosHonourRecordedSides() throws {
        let left = KeyCombo(keyCode: 49, modifiers: .command, sides: .leftCommand)
        let right = KeyCombo(keyCode: 49, modifiers: .command, sides: .rightCommand)
        #expect(left.matches(keyCode: 49, modifiers: .command, sides: .leftCommand))
        #expect(!left.matches(keyCode: 49, modifiers: .command, sides: .rightCommand))
        #expect(right.matches(keyCode: 49, modifiers: .command, sides: .rightCommand))
        #expect(Shortcut(switchTrigger: .combo(left), correction: .combo(right)).isValid)
        #expect(!Shortcut(switchTrigger: .combo(left), correction: .combo(left)).isValid)
        #expect(left.side(of: .command) == .left && left.side(of: .option) == .either)
        // Without recorded sides (older settings, defaults) either side works.
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: Data(#"{"keyCode":49,"modifiers":4}"#.utf8))
        #expect(decoded.matches(keyCode: 49, modifiers: .command, sides: .rightCommand))
        #expect(decoded.matches(keyCode: 49, modifiers: .command, sides: .leftCommand))
    }

    @Test func roundTripsThroughJSON() throws {
        let shortcut = Shortcut(switchTrigger: .combo(KeyCombo(keyCode: 49, modifiers: [.option, .fn], sides: .rightOption)),
                                correction: Self.controlOption)
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
    }

    @Test func combinationsStoredWithoutSidesAnswerToEitherSide() throws {
        let combo = try JSONDecoder().decode(Shortcut.self, from: Data(#"{"switchTrigger":{"combo":{"_0":{"keyCode":49,"modifiers":2}}},"correction":{"combo":{"_0":{"keyCode":49,"modifiers":10}}}}"#.utf8))
        #expect(combo.switchTrigger == .combo(KeyCombo(keyCode: 49, modifiers: .option)))
        #expect(combo.correction == .combo(KeyCombo(keyCode: 49, modifiers: [.option, .shift])))
    }

    @Test func modifierKeysAreRecognisedOnBothSides() {
        #expect(HeldModifier(keyCode: 63) == HeldModifier(.fn))
        #expect(HeldModifier(keyCode: 58) == HeldModifier(.option, .left) && HeldModifier(keyCode: 61) == HeldModifier(.option, .right))
        #expect(HeldModifier(keyCode: 55) == HeldModifier(.command, .left) && HeldModifier(keyCode: 54) == HeldModifier(.command, .right))
        #expect(HeldModifier(keyCode: 59) == HeldModifier(.control, .left) && HeldModifier(keyCode: 62) == HeldModifier(.control, .right))
        #expect(HeldModifier(keyCode: 56) == HeldModifier(.shift, .left) && HeldModifier(keyCode: 60) == HeldModifier(.shift, .right))
        #expect(HeldModifier(keyCode: 49) == nil)
        #expect(HeldModifier(.fn, .left).side == .either)
    }

    @Test func systemCombinationsAreNamed() {
        #expect(KeyCombo(keyCode: 49, modifiers: .command).systemUse == "Spotlight")
        #expect(KeyCombo(keyCode: 49, modifiers: [.control, .option]).systemUse == "the macOS input source switch")
        #expect(KeyCombo(keyCode: 49, modifiers: [.option, .shift]).systemUse == nil)
        #expect(KeyCombo(keyCode: 0, modifiers: .command).systemUse == nil)
    }

    @Test func modifierSymbolsFollowMacOrder() {
        #expect(ComboModifiers([.command, .shift, .control, .option]).symbols == "⌃⌥⇧⌘")
        #expect(ComboModifiers([.option, .fn]).symbols == "⌥Fn")
    }
}

@Suite struct TypedLayoutTests {
    static let latin = "abcdefghijklmnopqrstuvwxyz"
    static let ukrainian = "абвгдежзийклмнопрстуфхцчшщьюяієїґ"
    static let belarusian = "абвгдежзйклмнопрстуфхцчшьюяіўыэё"
    static let layouts: [(id: String, alphabet: String)] = [("en", latin), ("uk", ukrainian), ("by", belarusian), ("de", latin + "üöäß")]

    private func choose(_ text: String, active: String) -> TypedLayout.Choice {
        TypedLayout.choose(for: text, layouts: Self.layouts, activeID: active)
    }

    @Test func lettersOfOneLayoutDecideWhateverIsActive() {
        #expect(choose("руддщ", active: "en") == .source("uk"))
        #expect(choose("прывітанне", active: "de") == .source("by"))
        #expect(choose("lj,ht üjxe", active: "uk") == .source("de"))
    }

    @Test func sharedLettersFollowTheActiveLayoutAndAreNeverGuessed() {
        #expect(choose("мама", active: "uk") == .source("uk"))
        #expect(choose("мама", active: "by") == .source("by"))
        #expect(choose("мама", active: "en") == .ambiguous)
        #expect(choose("ghbdsn", active: "uk") == .ambiguous)
    }

    private func split(_ text: String, active: String) -> TypedLayout.Split {
        TypedLayout.split(text, layouts: Self.layouts, activeID: active)
    }

    @Test func wordsTypedOnTwoLayoutsAreSplitIntoRuns() {
        #expect(split("ghbdsn цщкдв", active: "en") == .runs([.init(text: "ghbdsn ", sourceID: "en"), .init(text: "цщкдв", sourceID: "uk")]))
        // Latin letters fit English and German alike, and neither neighbour nor the active layout says which.
        #expect(split("ghbdsn цщкдв", active: "uk") == .ambiguous)
        #expect(split("руддщ, world! 123", active: "en") == .runs([.init(text: "руддщ, ", sourceID: "uk"), .init(text: "world! 123", sourceID: "en")]))
        #expect(split(" - руддщ", active: "en") == .runs([.init(text: " - руддщ", sourceID: "uk")]))
    }

    @Test func wordsOfOneLayoutMakeOneRun() {
        #expect(split("ghbdsn ghbdsn", active: "en") == .runs([.init(text: "ghbdsn ghbdsn", sourceID: "en")]))
        #expect(split("ghbdsn ghbdsn", active: "uk") == .ambiguous)
        #expect(split("lj,ht üjxe", active: "uk") == .runs([.init(text: "lj,ht üjxe", sourceID: "de")]))
    }

    @Test func sharedWordsFollowTheirNeighboursThenTheActiveLayout() {
        #expect(split("мама прывітанне", active: "en") == .runs([.init(text: "мама прывітанне", sourceID: "by")]))
        #expect(split("мама руддщ", active: "by") == .runs([.init(text: "мама руддщ", sourceID: "uk")]))
        #expect(split("мама руддщ world", active: "en") == .runs([.init(text: "мама руддщ ", sourceID: "uk"), .init(text: "world", sourceID: "en")]))
        #expect(split("мама world", active: "en") == .ambiguous)
        #expect(split("мама", active: "de") == .ambiguous)
        #expect(split("ghbdsn мама прывітанне руддщ", active: "en") == .ambiguous)
    }

    @Test func splitRefusesWhatNoLayoutTypesAndTextWithoutLetters() {
        #expect(split("ghbdsn объект", active: "uk") == .impossible)
        #expect(split("helloпривіт", active: "uk") == .impossible)
        #expect(split("123 🙂", active: "uk") == .noLetters)
        #expect(split("", active: "uk") == .noLetters)
    }

    @Test func textNoSingleLayoutCanTypeIsRefused() {
        #expect(choose("объект", active: "uk") == .impossible)
        #expect(choose("ъ із російсько", active: "uk") == .impossible)
        #expect(choose("ещё", active: "uk") == .impossible)
        #expect(choose("hello привіт", active: "en") == .impossible)
        #expect(choose("12 3", active: "en") == .noLetters)
    }
}
