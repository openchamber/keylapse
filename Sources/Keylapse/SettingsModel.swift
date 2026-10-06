import Cocoa
import ServiceManagement
import KeylapseCore

struct LayoutOption: Identifiable, Equatable {
    let id: String
    let language: String
    let variant: String?
    let supportsCorrection: Bool
    var title: String { variant.map { "\(language) · \($0)" } ?? language }
}

/// Asks the Layouts list to scroll to a layout; the token makes repeated requests distinct.
struct ScrollRequest: Equatable {
    let id: String
    let token: Int
    /// Jump without animation (first appearance).
    var instant = false
}

/// A word for the welcome page to correct: what it looks like typed on the wrong layout, and what it becomes.
struct DemoSample: Equatable {
    let typed: String
    let result: String
    let layoutID: String
    let layoutName: String
    /// The real correction would ask for the layout the word was typed on to be active first.
    let needsSwitch: Bool
}

final class SettingsModel: ObservableObject {
    @Published var enabled: [LayoutOption] = []
    @Published var current: LayoutOption?
    /// Left-click on the menu bar flower corrects the selection; the menu moves to right-click.
    @Published var clickIconToCorrect = false
    @Published var switchOnRelease = false
    @Published var launchAtLogin = false
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var fnSystemAction: FnSystemAction = .unknown
    @Published var shortcut = Shortcut.standard
    /// Tick under the pointer on the Layouts rail. Lives here because @State is a macro the
    /// Command Line Tools cannot expand.
    @Published var railHighlight: Int?
    /// Shortcut row whose keys are under the pointer, for the hover affordance.
    @Published var hoveredKeys: RecordingTarget?
    /// How far the Layouts list is scrolled, to fade only the edges that hide something.
    @Published var layoutScrollOffset: CGFloat = 0
    /// Height of the Setup + Behavior block on the left, measured; the Layouts list matches it.
    @Published var leftBlockHeight: CGFloat = 0
    /// Height of the Layouts heading, measured, to take off the block height.
    @Published var layoutsHeadingHeight: CGFloat = 0
    /// Scrolls the list to a layout (clicks on the rail, previews).
    @Published var scrollRequest: ScrollRequest?
    /// The welcome page shows until the user has pressed Start using Keylapse once.
    @Published var showsWelcome = !UserDefaults.standard.bool(forKey: "onboarded")
    /// A word typed in the wrong layout for the welcome page to correct, if the layouts allow one.
    @Published var demo: DemoSample?
    /// What the welcome page's text field holds right now.
    @Published var demoText = ""
    /// Bumped to put the whole demo word under selection, ready for the shortcut.
    @Published var demoSelectionToken = 0
    /// The permission whose Grant… was clicked and that macOS has not granted yet. While set,
    /// the row shows a small replica of the System Settings row with its switch flipping, so
    /// the user sees what to do there; it clears itself the moment the permission arrives.
    @Published var awaiting: PermissionStep?
    /// The replica's switch, flipped every second or so while waiting.
    @Published var hintSwitchOn = false
    private var hintTimer: Timer?
    enum PermissionStep { case accessibility, inputMonitoring, fnKey }
    /// Whether Grant… for Input Monitoring was ever needed here; otherwise it came with Accessibility.
    private(set) var inputMonitoringAsked = false
    /// A step the user was waiting on has just been completed in System Settings.
    var onStepCompleted: ((PermissionStep) -> Void)?
    /// Lets the app show or hide the floating hint under System Settings.
    var onAwaitingChanged: ((PermissionStep?) -> Void)?
    /// Which key illustration is waiting for a physical key press, if any.
    @Published var recording: RecordingTarget?
    @Published var recordingHint: String?
    /// A row whose last recording was refused; its keys flash red for a moment.
    @Published var rejected: RecordingTarget?
    enum RecordingTarget { case switchKey, correction }
    private var recordingMonitor: Any?
    /// A click anywhere ends a recording, like Esc. Buttons act when the mouse goes up, so the
    /// check runs after the mouse-up has been handled: a click on the recording keys has ended
    /// the recording itself by then, and one that has just started another is skipped.
    private var clickMonitors: [Any] = []
    private var recordingJustStarted = false
    /// Modifier keys held so far during recording, shown on the keycaps as they are pressed.
    /// They become a chord when all are released with nothing else pressed, or the modifiers
    /// of a combination if a key follows.
    @Published var heldWhileRecording: Set<HeldModifier> = []
    private var rejectionToken = 0

    private let inputs: InputSources
    var onError: ((Error) -> Void)?
    /// Whether the event tap is up. Accessibility alone lets an app listen to the keyboard, and
    /// then macOS neither prompts for Input Monitoring nor lists the app there, while the
    /// Input Monitoring flag itself stays off; so a running tap counts as that step done.
    var keyboardIsBeingWatched: (() -> Bool)?
    var openAccessibility: (() -> Void)?
    var openInputMonitoring: (() -> Void)?
    var onSwitchOnReleaseChanged: ((Bool) -> Void)?
    var onShortcutChanged: ((Shortcut) -> Void)?
    /// Keyboard monitoring pauses while a key is being recorded.
    var onRecordingChanged: ((Bool) -> Void)?

    init(inputs: InputSources) {
        self.inputs = inputs
        if showsWelcome { startPulse() }
    }

    /// The one thing to do next. The window makes exactly this stand out, so the user is led
    /// from step to step instead of having to work out the order.
    enum SetupStep { case accessibility, inputMonitoring, fnKey, tryIt, start }
    var currentStep: SetupStep? {
        if !accessibility { return .accessibility }
        if !inputMonitoring { return .inputMonitoring }
        if needsFnSetup { return .fnKey }
        guard showsWelcome else { return nil }
        if demo != nil && !demoSucceeded { return .tryIt }
        return .start
    }

    /// One slow beat drives everything that asks for attention: the next step's glow, the
    /// replica's switch, the floating hint.
    private func startPulse() {
        guard hintTimer == nil else { return }
        hintTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { [weak self] _ in
            self?.hintSwitchOn.toggle()
        }
    }

    private func stopPulseIfIdle() {
        guard !showsWelcome, awaiting == nil, accessibility, inputMonitoring, !needsFnSetup else { return }
        hintTimer?.invalidate()
        hintTimer = nil
        hintSwitchOn = false
    }

    /// Fn setup matters while either shortcut has Fn in it.
    var needsFnSetup: Bool { shortcut.needsFnSystemAction && fnSystemAction != .ready }

    /// Only Fn on its own can choose between press and release: other modifier keys start
    /// shortcuts such as ⌘C, so they always switch on release, and a key combination fires on
    /// the key press. The option is live only for Fn; otherwise it just shows what happens.
    var canSwitchOnRelease: Bool { shortcut.switchTrigger.isFnAlone }
    var switchesOnRelease: Bool {
        switch shortcut.switchTrigger {
        case .modifiers: return shortcut.switchesOnRelease(preference: switchOnRelease)
        case .combo: return false
        }
    }

    static func storedShortcut(_ defaults: UserDefaults = .standard) -> Shortcut {
        guard let data = defaults.data(forKey: "shortcut"), let stored = try? JSONDecoder().decode(Shortcut.self, from: data),
              stored.isValid else { return .standard }
        return stored
    }

    func reloadLayouts() {
        inputs.reload()
        let layouts = inputs.sources.map {
            LayoutOption(id: $0.id, language: $0.languageTitle, variant: $0.variantTitle, supportsCorrection: $0.supportsCorrection)
        }
        if enabled != layouts { enabled = layouts }
        let active = layouts.first { $0.id == inputs.currentID }
        if current != active { current = active }
        if showsWelcome { refreshDemo() }
    }

    /// "hello" as it comes out when typed on another layout, read from the real macOS tables:
    /// руддщ on Ukrainian, so the welcome page can show a correction on text that is really wrong.
    /// Needs English and one more supported layout. The word does not follow the active layout
    /// (switching layouts would keep rewriting it, and on another Latin layout it would read
    /// hello and count as already fixed): it is the first layout in the list whose letters
    /// alone say which layout typed it, so the correction works whatever is active.
    private func refreshDemo() {
        let supported = inputs.sources.filter(\.supportsCorrection)
        guard let english = supported.first(where: { $0.languageCode == "en" }) else { setDemo(nil); return }
        let layouts = supported.map(\.layout)
        let samples: [(source: KeyboardSource, typed: String)] = supported.filter { $0.languageCode != "en" }.compactMap { other in
            guard let pair = try? inputs.layoutPair(english, other),
                  let typed = try? pair.convert("hello"), typed != "hello" else { return nil }
            return (other, typed)
        }
        let unmistakable = samples.first { TypedLayout.split($0.typed, layouts: layouts, activeID: "") == .runs([.init(text: $0.typed, sourceID: $0.source.id)]) }
        guard let sample = unmistakable ?? samples.first else { setDemo(nil); return }
        setDemo(DemoSample(typed: sample.typed, result: "hello", layoutID: sample.source.id, layoutName: sample.source.languageTitle,
                           needsSwitch: (try? inputs.typedRuns(of: sample.typed, among: supported)) == nil))
    }

    private func setDemo(_ sample: DemoSample?) {
        guard demo != sample else { return }
        let wasTyped = demo.map { demoText == $0.typed } ?? true
        demo = sample
        // Keep what the user has done with the word; only a fresh sample replaces untouched text.
        if let sample, wasTyped || demoText.isEmpty { demoText = sample.typed }
    }

    var demoSucceeded: Bool {
        guard let demo else { return false }
        return demoText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == demo.result
    }

    func resetDemo() {
        guard let demo else { return }
        demoText = demo.typed
        selectDemoWord()
    }

    func selectDemoWord() { demoSelectionToken += 1 }

    /// Back to the welcome page, as on the first launch; permissions and preferences stay.
    func showWelcome() {
        UserDefaults.standard.set(false, forKey: "onboarded")
        showsWelcome = true
        startPulse()
        reloadLayouts()
    }

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        showsWelcome = false
        stopWaiting()
        stopPulseIfIdle()
    }

    /// Opens the macOS pane for a permission and starts waiting for it.
    func grant(_ step: PermissionStep) {
        // Told before the pane opens, so the app can note whether System Settings was already up.
        if awaiting != step {
            awaiting = step
            onAwaitingChanged?(step)
        }
        switch step {
        case .accessibility: openAccessibility?()
        case .inputMonitoring:
            inputMonitoringAsked = true
            openInputMonitoring?()
        case .fnKey: openFnSettings()
        }
        startWaiting(step)
    }

    private func startWaiting(_ step: PermissionStep) {
        if awaiting != step {
            awaiting = step
            onAwaitingChanged?(step)
        }
        startPulse()
    }

    func stopWaiting() {
        guard awaiting != nil else { return }
        awaiting = nil
        onAwaitingChanged?(nil)
        stopPulseIfIdle()
    }

    /// Makes a layout the active one in macOS and brings it into view.
    func selectLayout(_ id: String) {
        do { try inputs.select(id) } catch { onError?(error) }
        reloadLayouts()
        scrollTo(id)
    }

    func scrollTo(_ id: String, instant: Bool = false) {
        scrollRequest = ScrollRequest(id: id, token: (scrollRequest?.token ?? 0) + 1, instant: instant)
    }

    func refreshState() {
        let defaults = UserDefaults.standard
        let clickCorrects = defaults.bool(forKey: "clickIconToCorrect")
        let release = defaults.bool(forKey: "switchOnRelease")
        let stored = Self.storedShortcut(defaults)
        let login = SMAppService.mainApp.status == .enabled
        let trusted = AXIsProcessTrusted()
        let monitoring = CGPreflightListenEventAccess() || (trusted && (keyboardIsBeingWatched?() ?? false))
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        func setting(_ key: String) -> Int? {
            (CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber)?.intValue
        }
        let fnAction = FnSystemAction.resolve(type: setting("AppleFnUsageType"), legacy: setting("AppleFnUsage"))
        if fnSystemAction != fnAction { fnSystemAction = fnAction }
        if clickIconToCorrect != clickCorrects { clickIconToCorrect = clickCorrects }
        if switchOnRelease != release { switchOnRelease = release }
        if shortcut != stored { shortcut = stored }
        if launchAtLogin != login { launchAtLogin = login }
        if accessibility != trusted { accessibility = trusted }
        if inputMonitoring != monitoring { inputMonitoring = monitoring }
        // Setup on the settings page pulses too while a step is left.
        if !trusted || !monitoring || needsFnSetup { startPulse() } else { stopPulseIfIdle() }
        if let step = awaiting,
           (step == .accessibility && trusted) || (step == .inputMonitoring && monitoring) || (step == .fnKey && fnAction == .ready) {
            stopWaiting()
            onStepCompleted?(step)
        }
    }

    func openFnSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    var onClickIconToCorrectChanged: ((Bool) -> Void)?

    func setClickIconToCorrect(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "clickIconToCorrect")
        clickIconToCorrect = value
        onClickIconToCorrectChanged?(value)
    }

    func setSwitchOnRelease(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "switchOnRelease")
        switchOnRelease = value
        onSwitchOnReleaseChanged?(value)
    }

    func resetShortcut() {
        stopRecording()
        setShortcut(.standard)
    }

    /// Set while recording after Use other keys: the point is to do without Fn, so keys with
    /// Fn in them are refused as long as macOS keeps Fn for itself.
    private var recordingWithoutFn = false

    func startRecording(_ target: RecordingTarget, withoutFn: Bool = false) {
        stopRecording()
        recordingWithoutFn = withoutFn
        recording = target
        recordingJustStarted = true
        DispatchQueue.main.async { [weak self] in self?.recordingJustStarted = false }
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mouseUp: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        clickMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in self?.stopRecording() },
            NSEvent.addLocalMonitorForEvents(matching: mouseUp) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.recording != nil, !self.recordingJustStarted else { return }
                    self.stopRecording()
                }
                return event
            },
        ].compactMap { $0 }
        recordingHint = nil
        rejected = nil
        heldWhileRecording = []
        onRecordingChanged?(true)
        // Fallback for when the event tap is not running (no Accessibility access yet):
        // keys the window itself receives. Combinations the system claims never arrive here.
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self, self.recording != nil else { return event }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            _ = self.record(ObservedKey(keyCode: event.keyCode, isKeyDown: event.type == .keyDown, flags: flags))
            return nil
        }
    }

    func stopRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
        guard recording != nil else { return }
        recordingWithoutFn = false
        recording = nil
        recordingHint = nil
        heldWhileRecording = []
        onRecordingChanged?(false)
    }

    /// Handles one key from either the event tap or the window. Returns true to swallow it.
    /// Modifier keys pressed and released together become a chord; a regular key pressed
    /// while modifiers are down becomes a combination; Esc on its own keeps the current shortcut.
    @discardableResult
    func record(_ key: ObservedKey) -> Bool {
        guard let target = recording else { return false }
        // Caps Lock is a switch, not a key that is held: macOS turns capitals on with it whatever
        // Keylapse does. Pressing it while recording gets an answer instead of silence.
        if !key.isKeyDown && key.keyCode == 57 {
            reject(target, "Caps Lock can’t be a shortcut. Press another key.")
            return true
        }
        if key.isKeyDown {
            if key.keyCode == 53 && key.modifiers.subtracting(.fn).isEmpty {
                stopRecording()
                return true
            }
            // Return on its own accepts the keys shown, as in any dialog; it keeps the current
            // shortcut like Esc. After Use other keys the current one still has Fn in it, and
            // accepting it would lead nowhere, so that is said instead.
            if (key.keyCode == 36 || key.keyCode == 76) && key.modifiers.subtracting(.fn).isEmpty {
                let current = target == .switchKey ? shortcut.switchTrigger : shortcut.correction
                if recordingWithoutFn, current.usesFn, fnSystemAction != .ready {
                    reject(target, "macOS keeps Fn for itself. Press keys without Fn.")
                } else {
                    stopRecording()
                }
                return true
            }
            let combo = KeyCombo(keyCode: key.keyCode, modifiers: key.modifiers, sides: key.sides)
            guard combo.isValid else {
                reject(target, "One key alone won’t do. Hold ⌃, ⌥ or ⌘ with it.")
                return true
            }
            finish(target, with: .combo(combo))
            return true
        }
        if key.held.isEmpty {
            // Caps Lock and such change nothing we track.
            guard !heldWhileRecording.isEmpty else { return true }
            let chord = ModifierChord(heldWhileRecording)
            heldWhileRecording = []
            finish(target, with: .modifiers(chord))
            return true
        }
        // The hint stays put while keys are held: a line that rewrote itself on every modifier
        // could not be read anyway. The keys speak for themselves on release.
        heldWhileRecording.formUnion(key.held)
        return true
    }

    private func finish(_ target: RecordingTarget, with trigger: Trigger) {
        var candidate = shortcut
        switch target {
        case .switchKey: candidate.switchTrigger = trigger
        case .correction: candidate.correction = trigger
        }
        guard candidate.isValid else {
            reject(target, "\(KeyNames.title(trigger)) is already the other shortcut. Press something different.")
            return
        }
        if recordingWithoutFn, trigger.usesFn, fnSystemAction != .ready {
            reject(target, "macOS keeps Fn for itself. Press keys without Fn.")
            return
        }
        setShortcut(candidate)
        stopRecording()
        // On the welcome page Use other keys means doing without Fn. A new switch key alone
        // does not get there while the correction keys still have Fn in them, so those are
        // asked for next, in the same row.
        if showsWelcome, target == .switchKey, needsFnSetup, !shortcut.switchTrigger.usesFn { startRecording(.correction, withoutFn: true) }
    }

    /// Keeps recording, says why the keys were refused, and flashes the row's keys red.
    private func reject(_ target: RecordingTarget, _ message: String) {
        recordingHint = message
        heldWhileRecording = []
        rejected = target
        rejectionToken += 1
        let token = rejectionToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.rejectionToken == token else { return }
            self.rejected = nil
        }
    }

    /// What macOS itself does with the chosen combination, if anything. Shown under the row.
    func systemNotice(for trigger: Trigger) -> String? {
        guard let combo = trigger.combo, let use = combo.systemUse else { return nil }
        return "\(KeyNames.title(combo)) is used by \(use); Keylapse takes it over while it runs."
    }

    private func setShortcut(_ value: Shortcut) {
        guard value.isValid, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "shortcut")
        shortcut = value
        onShortcutChanged?(value)
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { onError?(error) }
        refreshState()
    }
}
