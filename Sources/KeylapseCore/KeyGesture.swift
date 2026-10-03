/// Turns modifier presses into actions for the two modifier-chord shortcuts.
///
/// A gesture starts when the first modifier goes down and ends when every modifier is up.
/// It remembers every key held along the way; on release, that set is compared with the
/// correction chord first, then the switch chord. Any regular key in between cancels it,
/// so Fn-Control-F2 and window-tiling shortcuts cannot accidentally edit text.
///
/// A switch chord of Fn alone switches as soon as Fn goes down (unless `switchOnRelease`);
/// if more keys follow, the layout is put back so a correction starts from the original one.
public struct KeyGesture {
    public enum Action: Equatable { case switchLayout, restoreLayout, correctSelection }
    public var switchChord: ModifierChord?
    public var correctionChord: ModifierChord?
    public var switchOnRelease = false

    private var active = false
    private var held: Set<HeldModifier> = []
    private var cancelled = false
    private var switched = false

    public init(switchChord: ModifierChord? = .fn, correctionChord: ModifierChord? = .controlFn) {
        self.switchChord = switchChord
        self.correctionChord = correctionChord
    }

    public mutating func modifiersChanged(_ now: Set<HeldModifier>) -> [Action] {
        var actions: [Action] = []
        if now.isEmpty {
            if active && !cancelled && !switched {
                if let correction = correctionChord, correction.matches(held) { actions.append(.correctSelection) }
                else if let chord = switchChord, chord.matches(held) { actions.append(.switchLayout) }
            }
            active = false
            held = []
            cancelled = false
            switched = false
            return actions
        }
        let grew = !now.isSubset(of: held)
        active = true
        held.formUnion(now)
        if switched && grew {
            // Fn already switched, now another key joins: undo so a correction starts from the original layout.
            actions.append(.restoreLayout)
            switched = false
        } else if !switched && !cancelled && !switchOnRelease, let chord = switchChord, chord.isFnAlone, chord.matches(now), held == now {
            switched = true
            actions.append(.switchLayout)
        }
        return actions
    }

    public mutating func otherKeyPressed() -> [Action] {
        guard active else { return [] }
        cancelled = true
        if switched {
            switched = false
            return [.restoreLayout]
        }
        return []
    }
}
