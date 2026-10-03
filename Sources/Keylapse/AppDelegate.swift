import Cocoa
import Carbon
import Combine
import ServiceManagement
import SwiftUI
import KeylapseCore

/// What the menu bar reports. Blocked states and the start-up state give way to
/// Ready once monitoring runs; notices stay until the next event replaces them.
enum AppStatus: Equatable {
    case starting, ready
    case blocked(String)
    case notice(String)

    var text: String {
        switch self {
        case .starting: return "Starting…"
        case .ready: return "Ready"
        case .blocked(let text), .notice(let text): return text
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let inputs = InputSources()
    private(set) lazy var correction = CorrectionFlow(inputs: inputs)
    private(set) lazy var settingsModel = SettingsModel(inputs: inputs)
    private(set) var window: NSWindow?
    private var hosting: NSHostingView<KeylapseSettingsView>?
    private var modelObserver: AnyCancellable?
    private(set) lazy var permissionHint = PermissionHint(model: settingsModel, window: { [weak self] in self?.window },
                                                     refresh: { [weak self] in self?.refreshMonitoring() })

    private let monitor = KeyboardMonitor()
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var timer: Timer?
    private var layoutBeforeFn: String?
    private var paused = false
    private var status = AppStatus.starting

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["switchOnRelease": false, "clickIconToCorrect": false])
        if Diagnostics.runLaunchCheck(in: self) { return }
        // LaunchServices normally reopens an existing app; also guard direct executable launches.
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.openchamber.keylapse")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = Self.editingMenu()
        // An app that has stopped responding must not hold Keylapse, and with it the keyboard,
        // for the six seconds Accessibility waits by default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Flower.menuBarIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applyClickBehaviour(UserDefaults.standard.bool(forKey: "clickIconToCorrect"))
        settingsModel.onClickIconToCorrectChanged = { [weak self] in self?.applyClickBehaviour($0) }
        monitor.shortcut = SettingsModel.storedShortcut()
        monitor.switchOnRelease = UserDefaults.standard.bool(forKey: "switchOnRelease")
        // Out of the event tap's callback first: a correction talks to the app in front, and
        // the tap must not hold up the keyboard while it does.
        monitor.onAction = { [weak self] action in DispatchQueue.main.async { self?.handle(action) } }
        monitor.onFailure = { [weak self] in
            self?.restoreLayout()
            self?.setStatus(.notice("Keyboard monitoring restarted. Try the shortcut again."))
        }
        correction.onFinished = { [weak self] result in
            switch result {
            case .success: self?.setStatus(.notice("Text replaced. Press ⌘Z to undo."))
            case .failure(let error): self?.showError(error)
            }
        }
        // The chooser held the keyboard; on the welcome page it goes back to the window, which
        // would otherwise be left without it and ignore the next click.
        correction.onChooserClosed = { [weak self] in
            if NSApp.isActive, let window = self?.window, window.isVisible { window.makeKey() }
        }
        settingsModel.onSwitchOnReleaseChanged = { [weak self] in self?.monitor.switchOnRelease = $0 }
        settingsModel.onShortcutChanged = { [weak self] in self?.monitor.shortcut = $0; self?.refreshMonitoring() }
        settingsModel.onRecordingChanged = { [weak self] recording in
            guard let self else { return }
            self.monitor.recorder = recording ? { [weak self] key in self?.settingsModel.record(key) ?? false } : nil
        }
        refreshMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshMonitoring() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourcesChanged),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil)
        // macOS announces every change of the active layout, so the window follows at once.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(selectedSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        if settingsModel.showsWelcome || !AXIsProcessTrusted() || settingsModel.needsFnSetup { openSettings() }
    }

    /// With the option on, the status item has no attached menu: a left click corrects the
    /// selection and a right click shows the menu by hand. Otherwise both clicks open the menu.
    private func applyClickBehaviour(_ clickCorrects: Bool) {
        statusItem.menu = clickCorrects ? nil : statusMenu
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || !UserDefaults.standard.bool(forKey: "clickIconToCorrect") {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        handle(.correctSelection)
    }

    /// A menu bar app shows no main menu, but AppKit still routes ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z through
    /// it. Without an Edit menu the welcome page's text field ignores them all, including the
    /// copy and paste the corrector itself sends.
    static func editingMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        let item = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        return main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { monitor.stop(); timer?.invalidate() }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard statusItem != nil else { return }
        refreshMonitoring()
    }
    @objc private func woke() { monitor.stop(); layoutBeforeFn = nil; refreshMonitoring() }

    @objc private func inputSourcesChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutBeforeFn = nil
            self.correction.cancelChooser()
            self.settingsModel.reloadLayouts()
        }
    }

    @objc private func selectedSourceChanged() {
        DispatchQueue.main.async { [weak self] in self?.settingsModel.reloadLayouts() }
    }

    /// Set while the welcome word is being put back under selection for a second attempt.
    private var reselectedDemoWord = false

    func handle(_ action: KeyGesture.Action) {
        guard !paused, correction.isIdle else { return }
        switch action {
        case .switchLayout:
            layoutBeforeFn = inputs.currentID
            do { try inputs.toggle() } catch { showError(error) }
            settingsModel.reloadLayouts()
        case .restoreLayout:
            restoreLayout()
        case .correctSelection:
            // On the welcome page the word is there to be corrected: if a click took the
            // selection off it, the shortcut takes the whole word again rather than doing nothing.
            if NSApp.isActive, settingsModel.showsWelcome, settingsModel.currentStep == .tryIt {
                if let editor = window?.firstResponder as? NSTextView {
                    if editor.selectedRange().length == 0 { editor.selectAll(nil) }
                } else if !reselectedDemoWord {
                    reselectedDemoWord = true
                    settingsModel.selectDemoWord()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.handle(action)
                        self?.reselectedDemoWord = false
                    }
                    return
                }
            }
            correction.start()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === window { settingsModel.stopRecording() }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window {
            settingsModel.stopRecording()
            settingsModel.stopWaiting()
            // Closing the welcome page with every setup step done is the same as Start using
            // Keylapse: next time the window shows the settings, not the welcome again.
            if settingsModel.showsWelcome, settingsModel.currentStep == .tryIt || settingsModel.currentStep == .start {
                settingsModel.finishWelcome()
            }
        }
    }

    private func restoreLayout() {
        if let id = layoutBeforeFn { try? inputs.select(id) }
        layoutBeforeFn = nil
    }

    /// Starts or stops keyboard monitoring to match permissions and the pause state,
    /// and refreshes what Settings shows. Runs on launch, activation and every 2 s.
    private func refreshMonitoring() {
        settingsModel.reloadLayouts()
        defer { settingsModel.refreshState(); updateIcon() }
        if !AXIsProcessTrusted() {
            monitor.stop()
            setStatus(.blocked("Accessibility permission needed"))
        } else if paused {
            monitor.stop()
            setStatus(.blocked("Paused"))
        } else if !monitor.start() {
            setStatus(.blocked("Keyboard access needed"))
        } else if case .notice = status {
            // Keep the latest result visible until something else happens.
        } else {
            setStatus(.ready)
        }
    }

    private var iconShowsPause = false

    /// The menu bar flower follows what is true right now, not the last status message: a
    /// lingering notice (Text replaced…, Keyboard monitoring restarted…) used to freeze it, so
    /// the pause bars could stay after the last setup step until something else happened.
    private func updateIcon() {
        let notWorking = paused || !AXIsProcessTrusted() || !monitor.running || settingsModel.needsFnSetup
        if notWorking != iconShowsPause {
            iconShowsPause = notWorking
            statusItem?.button?.image = Flower.menuBarIcon(paused: notWorking)
        }
    }

    private func setStatus(_ status: AppStatus) {
        self.status = status
        updateIcon()
        // Diagnostics drive the delegate without a menu bar item.
        statusItem?.button?.toolTip = "Keylapse · \(status.text)\n\(KeyNames.summary(monitor.shortcut))"
    }

    private func showError(_ error: Error) {
        setStatus(.notice(error.localizedDescription))
        NSSound.beep()
        NoticePanel.show(error.localizedDescription,
                         near: NSWorkspace.shared.frontmostApplication.flatMap { correction.corrector.selectionRect(for: $0.processIdentifier) })
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        // The app has one window, so its name opens it; there is no separate Settings item.
        let title = menu.addItem(withTitle: "Keylapse \(version)…", action: #selector(openSettings), keyEquivalent: ",")
        title.target = self
        title.toolTip = "Open Keylapse"
        let statusLine = menu.addItem(withTitle: status.text, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(.separator())
        let correct = menu.addItem(withTitle: "Correct Selected Text", action: #selector(correctFromMenu), keyEquivalent: "")
        correct.target = self
        correct.image = Flower.menuBarIcon()
        Self.showShortcut(monitor.shortcut, on: correct)
        item(menu, paused ? "Resume" : "Pause", #selector(togglePause))
        menu.addItem(.separator())
        item(menu, "Show Welcome Page", #selector(showWelcome))
        item(menu, "Quit Keylapse", #selector(quit), "q")
    }

    /// Shows the correction shortcut at the right of the menu item. A key combination becomes a
    /// real key equivalent; a modifier chord has no such thing, so it is written into the title.
    private static func showShortcut(_ shortcut: Shortcut, on item: NSMenuItem) {
        switch shortcut.correction {
        case .combo(let combo):
            let name = KeyNames.name(for: combo.keyCode)
            item.keyEquivalent = combo.keyCode == 49 ? " " : (name.count == 1 ? name.lowercased() : "")
            var mask: NSEvent.ModifierFlags = []
            if combo.modifiers.contains(.control) { mask.insert(.control) }
            if combo.modifiers.contains(.option) { mask.insert(.option) }
            if combo.modifiers.contains(.command) { mask.insert(.command) }
            if combo.modifiers.contains(.shift) { mask.insert(.shift) }
            if combo.modifiers.contains(.fn) { mask.insert(.function) }
            item.keyEquivalentModifierMask = mask
            if item.keyEquivalent.isEmpty { appendHint(KeyNames.title(combo), to: item) }
        case .modifiers:
            appendHint(KeyNames.symbols(shortcut.correction), to: item)
        }
    }

    /// Writes a shortcut after the title in the same secondary colour macOS uses for key equivalents.
    private static func appendHint(_ hint: String, to item: NSMenuItem) {
        let text = NSMutableAttributedString(string: item.title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(string: "    \(hint)", attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        item.attributedTitle = text
    }

    /// Items without an icon get a blank one of the same size so their titles line up.
    private static let blankIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }()

    private func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = Self.blankIcon
    }

    /// The menu closes first; the selection in the editor is untouched by opening it.
    /// Chosen from the menu, so unlike the shortcut it always answers: with nothing selected it says so.
    @objc private func correctFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            if let front = NSWorkspace.shared.frontmostApplication, self.correction.corrector.selection(in: front.processIdentifier) == .none {
                self.showError(CorrectionFlow.nothingSelected)
                return
            }
            self.handle(.correctSelection)
        }
    }

    @objc private func togglePause() { paused.toggle(); refreshMonitoring() }

    /// The first-launch page again, for a reminder of how it works; nothing is reset but the page.
    @objc private func showWelcome() {
        if window == nil { buildSettings() }
        settingsModel.showWelcome()
        openSettings()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        if window == nil { buildSettings() }
        settingsModel.reloadLayouts()
        refreshMonitoring()
        // Asked for from the menu bar of one display, it opens on that display, not on the one
        // where it was last left: same place within the screen, moved across.
        if let window, !window.isVisible, let here = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
           let there = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(window.frame) }), here != there {
            var frame = window.frame
            frame.origin.x += here.visibleFrame.midX - there.visibleFrame.midX
            frame.origin.y += here.visibleFrame.midY - there.visibleFrame.midY
            frame.origin.x = min(max(frame.origin.x, here.visibleFrame.minX), here.visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, here.visibleFrame.minY), here.visibleFrame.maxY - frame.height)
            window.setFrame(frame, display: false)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static let windowFrameName = "KeylapseWindow"

    func buildSettings() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Keylapse"
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isMovableByWindowBackground = true
        w.delegate = self
        settingsModel.onError = { [weak self] in self?.showError($0) }
        settingsModel.keyboardIsBeingWatched = { [weak self] in self?.monitor.running ?? false }
        settingsModel.onAwaitingChanged = { [weak self] step in
            if step == nil { self?.permissionHint.hide() } else { self?.permissionHint.show() }
        }
        settingsModel.onStepCompleted = { [weak self] _ in
            self?.refreshMonitoring()
            self?.permissionHint.finish(bringingForward: self?.window)
        }
        settingsModel.openAccessibility = { [weak self] in self?.grantPermission() }
        settingsModel.openInputMonitoring = { [weak self] in self?.inputMonitoring() }
        settingsModel.reloadLayouts()
        settingsModel.refreshState()
        let hosting = FirstClickHostingView(rootView: KeylapseSettingsView(model: settingsModel))
        w.contentView = GlassView.wrapping(hosting)
        self.hosting = hosting
        window = w
        fitWindow(animated: false)
        // Opens where it was last left; centred only the first time. The saved frame may have
        // another height (welcome page, more layouts), so the content height is fitted again
        // afterwards, keeping the top edge where the user put it.
        if !w.setFrameUsingName(Self.windowFrameName) { w.center() }
        w.setFrameAutosaveName(Self.windowFrameName)
        fitWindow(animated: false)
        // The content height follows the number of layouts and the setup state.
        modelObserver = settingsModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitWindow(animated: true) }
        }
    }

    /// Sizes the window to the SwiftUI content, keeping its top edge in place.
    private func fitWindow(animated: Bool) {
        guard let window, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let height = hosting.fittingSize.height.rounded()
        guard abs(window.frame.height - height) >= 1 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true, animate: animated)
    }

    /// Asking macOS puts Keylapse in the Accessibility list and, the first time, shows the system
    /// dialog whose own button opens System Settings. Opening the pane as well would put two
    /// things about the same step on screen, so the pane is opened here only when that dialog
    /// did not appear (macOS shows it once; after Deny or a second click it stays silent).
    @objc private func grantPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !AXIsProcessTrusted(), !Self.systemAccessDialogIsShowing() else { return }
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    /// The "would like to control this computer" dialog belongs to this system process.
    private static func systemAccessDialogIsShowing() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { ($0["kCGWindowOwnerName"] as? String) == "universalAccessAuthWarn" }
    }
    @objc private func inputMonitoring() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            // macOS lists an app under Input Monitoring only once it has tried to listen. Until
            // Accessibility is granted the monitor never tries, so the list would stay empty and
            // the user would have to add the app by hand. One refused attempt is enough.
            if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                           callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) {
                CFMachPortInvalidate(tap)
            }
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}

/// The window's content answers the click that also brings the window forward, so a button
/// never has to be clicked twice after System Settings or the chooser was in front.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
