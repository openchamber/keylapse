import Cocoa
import KeylapseCore

/// A key event as seen by the event tap, with modifier flags already resolved.
struct ObservedKey {
    let keyCode: UInt16
    /// True for a regular key going down; false for a modifier key changing state.
    let isKeyDown: Bool
    let modifiers: ComboModifiers
    let sides: ComboSides
    /// Every modifier key down after this event, with its side.
    let held: Set<HeldModifier>

    init(keyCode: UInt16, isKeyDown: Bool, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.isKeyDown = isKeyDown
        modifiers = KeyboardMonitor.comboModifiers(of: flags)
        sides = KeyboardMonitor.sides(of: flags)
        held = KeyboardMonitor.held(in: flags)
    }
}

final class KeyboardMonitor {
    static let ownEventTag: Int64 = 0x4B45594C41505345
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = KeyGesture()
    /// Mirrors the Settings choices. Changing the shortcut restarts the tap if its mode must change.
    var shortcut = Shortcut.standard {
        didSet {
            resetGesture()
            restartIfModeChanged(wasIntercepting: oldValue.usesCombos || recorder != nil)
        }
    }
    var switchOnRelease = false { didSet { applyPreferences() } }
    /// While Settings records a shortcut, every key goes here instead of the gesture engine,
    /// and the tap intercepts so that combinations the system claims (⌘Space…) are seen too.
    /// Return true to swallow the event.
    var recorder: ((ObservedKey) -> Bool)? {
        didSet {
            resetGesture()
            restartIfModeChanged(wasIntercepting: shortcut.usesCombos || oldValue != nil)
        }
    }
    var onAction: ((KeyGesture.Action) -> Void)?
    var onFailure: (() -> Void)?
    var running: Bool { tap != nil }

    private var intercepting: Bool { shortcut.usesCombos || recorder != nil }

    private func restartIfModeChanged(wasIntercepting: Bool) {
        if running, intercepting != wasIntercepting { stop(); _ = start() }
    }

    func start() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Modifier taps only need to listen. A key combination must be swallowed so the
        // frontmost app does not also act on it, which needs an active tap.
        let options: CGEventTapOptions = intercepting ? .defaultTap : .listenOnly
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: options, eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                monitor.resetGesture()
                monitor.onFailure?()
                return Unmanaged.passUnretained(event)
            }
            return monitor.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: context) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        resetGesture()
    }

    private func applyPreferences() {
        gesture.switchChord = shortcut.switchTrigger.chord
        gesture.correctionChord = shortcut.correction.chord
        gesture.switchOnRelease = shortcut.switchesOnRelease(preference: switchOnRelease)
    }

    private func resetGesture() {
        gesture = KeyGesture()
        applyPreferences()
    }

    /// Returns true when the event must not reach the app.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEventTag else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let key = ObservedKey(keyCode: keyCode, isKeyDown: type == .keyDown, flags: event.flags)
        if let recorder {
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
            return recorder(key)
        }
        if type == .keyDown {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
            let matched: KeyGesture.Action?
            if let combo = shortcut.switchTrigger.combo, combo.matches(keyCode: keyCode, modifiers: key.modifiers, sides: key.sides) {
                matched = .switchLayout
            } else if let combo = shortcut.correction.combo, combo.matches(keyCode: keyCode, modifiers: key.modifiers, sides: key.sides) {
                matched = .correctSelection
            } else {
                matched = nil
            }
            // Any key ends a modifier gesture; a layout Fn already switched is put back first.
            for action in gesture.otherKeyPressed() { onAction?(action) }
            if let matched {
                resetGesture()
                onAction?(matched)
                return true
            }
        } else {
            for action in gesture.modifiersChanged(key.held) { onAction?(action) }
        }
        return false
    }

    static func comboModifiers(of flags: CGEventFlags) -> ComboModifiers {
        var modifiers: ComboModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.fn) }
        return modifiers
    }

    /// Device-specific bits from IOLLEvent.h (NX_DEVICEL/R…KEYMASK) tell the two keys of a pair apart.
    private static let deviceBits: [(ModifierFamily, CGEventFlags, UInt64, UInt64)] = [
        (.control, .maskControl, 0x0001, 0x2000),
        (.shift, .maskShift, 0x0002, 0x0004),
        (.command, .maskCommand, 0x0008, 0x0010),
        (.option, .maskAlternate, 0x0020, 0x0040)
    ]

    /// Which sides of Control, Option, Shift and Command are down.
    static func sides(of flags: CGEventFlags) -> ComboSides {
        var sides: ComboSides = []
        for key in held(in: flags) where key.family != .fn {
            switch (key.family, key.side) {
            case (.control, .left): sides.insert(.leftControl)
            case (.control, .right): sides.insert(.rightControl)
            case (.option, .left): sides.insert(.leftOption)
            case (.option, .right): sides.insert(.rightOption)
            case (.command, .left): sides.insert(.leftCommand)
            case (.command, .right): sides.insert(.rightCommand)
            case (.shift, .left): sides.insert(.leftShift)
            case (.shift, .right): sides.insert(.rightShift)
            default: break
            }
        }
        return sides
    }

    /// Every modifier key down, with its side. A keyboard that reports no side bits gives `either`.
    static func held(in flags: CGEventFlags) -> Set<HeldModifier> {
        var held: Set<HeldModifier> = []
        if flags.contains(.maskSecondaryFn) { held.insert(HeldModifier(.fn)) }
        for (family, mask, left, right) in deviceBits where flags.contains(mask) {
            let raw = flags.rawValue
            if raw & left != 0 { held.insert(HeldModifier(family, .left)) }
            if raw & right != 0 { held.insert(HeldModifier(family, .right)) }
            if raw & (left | right) == 0 { held.insert(HeldModifier(family, .either)) }
        }
        return held
    }
}
