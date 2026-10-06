import Cocoa
import ServiceManagement
import KeylapseCore

/// Command-line checks against the real macOS input sources and the installed app.
/// They are developer tools, not part of normal use; none of them alter system settings.
///
///   --source-report            print enabled input sources as JSON
///   --check-discovery          layout variants, U.S. ↔ Dvorak, unsupported-source rejection
///   --check-cycle              cycle through enabled sources and restore the original
///   --check-layouts            read tables for every ordered pair of installed languages
///   --self-test                English ↔ Ukrainian regression examples
///   --permission-report <path> write accessibility / input-monitoring / login-item state
///   --check-selection <path>   correct the current TextEdit selection as the shortcut would
///   --check-menu-icon <png>     write the paused menu bar flower (pause bars for the dot) at 2×
///   --check-permission-hint <path> open System Settings and report where the floating hint lands
///   --check-fn-menu <path>      open Keyboard settings and list its pop-up menus, marking the Fn one the hint points at
///   --check-welcome-demo <path> correct the welcome page's own word through the real corrector
///   --check-settings <path> [--preview-…]       render the Settings window to a PNG
///       --preview-welcome [--preview-demo-done] (the first-launch page), --preview-settings-page, --preview-waiting (Grant… clicked),
///       --preview-setup-ready, --preview-fn-conflict, --preview-fn-unknown,
///       --preview-missing-permissions, --preview-destinations, --preview-switch-key <fn|rightOption|leftCommand…>, --preview-combo-shortcut, --preview-recording, --preview-refused, --preview-many-layouts, --preview-rows <n>, --preview-scrolled-to-end (centres the last layout)
enum Diagnostics {
    /// Checks that need no running application. Exits the process when one is requested.
    static func runStandaloneCheckIfRequested() {
        let arguments = CommandLine.arguments
        do {
            if arguments.contains("--source-report") { try sourceReport() }
            else if arguments.contains("--check-discovery") { try checkDiscovery() }
            else if arguments.contains("--check-cycle") { try checkCycle() }
            else if arguments.contains("--check-layouts") { try checkLayouts() }
            else if arguments.contains("--self-test") { try selfTest() }
            else { return }
            exit(0)
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    /// Checks that need the app delegate. Returns true when one took over the launch.
    static func runLaunchCheck(in app: AppDelegate) -> Bool {
        if let path = argument(after: "--check-selection") {
            checkSelection(in: app, reportPath: path)
        } else if let path = argument(after: "--check-menu-icon") {
            // The paused menu bar flower at 2×, as a PNG, to look at.
            let icon = Flower.menuBarIcon(paused: true)
            if let rep = icon.representations.compactMap({ $0 as? NSBitmapImageRep }).max(by: { $0.pixelsWide < $1.pixelsWide }),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("PASS: \(rep.pixelsWide) px")
            } else { print("FAIL: no icon") }
            NSApp.terminate(nil)
        } else if let path = argument(after: "--check-permission-hint") {
            checkPermissionHint(in: app, reportPath: path)
        } else if let path = argument(after: "--check-fn-menu") {
            checkFnMenu(reportPath: path)
        } else if let path = argument(after: "--check-welcome-demo") {
            checkWelcomeDemo(in: app, reportPath: path)
        } else if let path = argument(after: "--permission-report") {
            permissionReport(path: path)
        } else if let path = argument(after: "--check-settings") {
            checkSettings(in: app, snapshotPath: path)
        } else {
            return false
        }
        return true
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private static func writeJSON(_ object: Any, to path: String?) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        if let path { try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
        else { print(String(decoding: data, as: UTF8.self)) }
    }

    // MARK: Standalone

    private static func sourceReport() throws {
        let inputs = InputSources()
        try writeJSON(inputs.sources.map {
            ["id": $0.id, "name": $0.displayName, "correction": $0.supportsCorrection, "current": $0.id == inputs.currentID]
        }, to: nil)
    }

    private static func checkDiscovery() throws {
        let installed = InputSources(includeDisabled: true)
        guard let us = installed.sources.first(where: { $0.id == "com.apple.keylayout.US" }),
              let dvorak = installed.sources.first(where: { $0.id == "com.apple.keylayout.Dvorak" }),
              let ukrainian = installed.sources.first(where: { $0.id == "com.apple.keylayout.Ukrainian" }),
              let ukrainianPC = installed.sources.first(where: { $0.id == "com.apple.keylayout.Ukrainian-PC" }),
              let unsupported = installed.sources.first(where: { !$0.supportsCorrection }) else {
            throw AppError.message("Missing macOS layouts needed for discovery checks")
        }
        guard us.displayName != dvorak.displayName, ukrainian.displayName != ukrainianPC.displayName else {
            throw AppError.message("Layout variants must have distinct names")
        }
        let pair = try installed.layoutPair(us, dvorak)
        guard try pair.convert("hello") == "d.nnr", try pair.reversed.convert("d.nnr") == "hello" else {
            throw AppError.message("Same-language layout conversion failed")
        }
        do {
            _ = try installed.layoutPair(us, unsupported)
            throw AppError.message("Unsupported source accepted for correction")
        } catch let error as AppError {
            guard error.localizedDescription == "Text correction isn’t supported for these layouts yet." else { throw error }
        }
        let enabled = InputSources()
        let before = enabled.sources.map(\.id)
        enabled.reload()
        guard before == enabled.sources.map(\.id), Set(before).count == before.count else {
            throw AppError.message("Unstable or duplicate system input sources")
        }
        print("PASS: distinct layout variants, U.S. ↔ Dvorak, unsupported-source rejection, stable discovery. No system sources changed.")
    }

    private static func checkCycle() throws {
        let inputs = InputSources()
        let original = inputs.currentID
        defer { try? inputs.select(original) }
        let selected = inputs.enabledSources()
        guard !selected.isEmpty else { throw AppError.message("No enabled keyboard input sources") }
        try inputs.select(selected[0].id)
        for index in 1...selected.count {
            try inputs.toggle()
            guard inputs.currentID == selected[index % selected.count].id else {
                throw AppError.message("Layout cycle selected the wrong source")
            }
        }
        print("PASS: cycled through \(selected.count) macOS layouts and restored the original")
    }

    private static func checkLayouts() throws {
        let inputs = InputSources(includeDisabled: true)
        // One installed layout per language, so every language pair is exercised once.
        var representatives: [KeyboardSource] = []
        for source in inputs.sources where source.supportsCorrection && !representatives.contains(where: { $0.languageCode == source.languageCode }) {
            representatives.append(source)
        }
        guard representatives.count >= 2 else { throw AppError.message("Fewer than two correctable layouts installed") }
        var count = 0
        for first in representatives {
            for second in representatives where first.id != second.id {
                let pair = try inputs.layoutPair(first, second)
                // Exercise direction resolution with the real macOS tables for every ordered pair.
                guard let example = pair.forward.first(where: { pair.firstAlphabet.contains($0.key) }) else {
                    throw AppError.message("No mapped letters for \(first.name) → \(second.name)")
                }
                let converted = try pair.convert(String(example.key))
                guard converted == String(example.value) else { throw AppError.message("Wrong conversion direction") }
                let missing = pair.firstAlphabet.subtracting(pair.forward.keys)
                if !missing.isEmpty {
                    print("LIMIT: \(first.name) → \(second.name): unmapped letters \(String(missing.sorted()))")
                }
                count += 1
            }
        }
        print("PASS: \(representatives.count) languages, \(count) ordered layout pairs read and sampled. Dead-key composition and editor input are not covered.")
    }

    private static func selfTest() throws {
        let sources = InputSources()
        guard let en = sources.sources.first(where: { $0.languageCode == "en" && $0.supportsCorrection }),
              let uk = sources.sources.first(where: { $0.languageCode == "uk" && $0.supportsCorrection }) else {
            throw AppError.message("Enable English and Ukrainian layouts for this regression check.")
        }
        let pair = try sources.layoutPair(en, uk)
        let cases = [(pair, "ghbdsn", "привіт"), (pair.reversed, "руддщ", "hello"), (pair, "GhBdsN", "ПрИвіТ"),
                     (pair, "rj;ty", "кожен"), (pair.reversed, "сщву", "code"), (pair, "ghbdsn\n🙂", "привіт\n🙂")]
        for (direction, input, expected) in cases {
            let actual = try direction.convert(input)
            guard actual == expected else { throw AppError.message("\(input): expected \(expected), got \(actual)") }
        }
        let alphabet = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"
        for character in alphabet + alphabet.uppercased() {
            guard let mapped = pair.backward[character], pair.forward[mapped] == character else {
                throw AppError.message("Round-trip mapping failed for \(character)")
            }
        }
        // Text typed on both layouts, word by word, swapped between them.
        let mixed = "ghbdsn цщкдв! 123"
        let runs = try sources.typedRuns(of: mixed, among: [en, uk])
        let swapped = try runs.map { run in try sources.layoutPair(run.source, run.source.id == en.id ? uk : en).convert(run.text) }.joined()
        guard runs.map(\.text) == ["ghbdsn ", "цщкдв! 123"], swapped == "привіт world! 123" else {
            throw AppError.message("\(mixed): expected привіт world! 123, got \(swapped)")
        }
        print("PASS: \(en.name) ↔ \(uk.name), examples, mixed text and all 66 Ukrainian letter cases round-trip")
    }

    // MARK: Launch-time

    private static let modifierKeyCodes: [CGKeyCode] = [54, 55, 56, 60, 58, 61, 59, 62, 63]

    private static func checkSelection(in app: AppDelegate, reportPath: String) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" else {
                fputs("Selection check requires a focused TextEdit test document.\n", stderr)
                exit(1)
            }
            let before = modifierKeyCodes.filter { CGEventSource.keyState(.hidSystemState, key: $0) }
            let clipboardBefore = Clipboard().snapshot()
            app.correction.onFinished = { result in
                let error: String?
                if case .failure(let failure) = result { error = failure.localizedDescription } else { error = nil }
                let report: [String: Any] = [
                    "success": error == nil,
                    "error": error ?? "",
                    "clipboardRestored": Clipboard().snapshot() == clipboardBefore,
                    "modifiersBefore": before,
                    "modifiersAfter": modifierKeyCodes.filter { CGEventSource.keyState(.hidSystemState, key: $0) }
                ]
                do { try writeJSON(report, to: reportPath) }
                catch { fputs("\(error)\n", stderr); exit(1) }
                NSApp.terminate(nil)
            }
            app.correction.onSilentStop = { app.correction.onFinished?(.failure($0)) }
            app.handle(.correctSelection)
        }
    }

    /// Run through LaunchServices from the installed bundle so TCC checks
    /// the app, rather than the terminal launching a bare executable.
    private static func permissionReport(path: String) {
        let report: [String: Any] = [
            "accessibility": AXIsProcessTrusted(),
            "inputMonitoring": CGPreflightListenEventAccess(),
            "keyboardTapWorks": KeyboardMonitor().start(),
            "launchAtLogin": SMAppService.mainApp.status == .enabled,
            "bundlePath": Bundle.main.bundlePath
        ]
        do { try writeJSON(report, to: path) }
        catch {
            fputs("Permission report failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        NSApp.terminate(nil)
    }

    /// Renders the hosted SwiftUI form without screen-recording access.
    /// Does not start keyboard monitoring or change permissions/preferences.
    /// Opens the welcome page, selects its wrong-layout word and runs the real correction on it,
    /// clipboard and all, as the shortcut would. Needs the permissions granted.
    private static func checkWelcomeDemo(in app: AppDelegate, reportPath: String) {
        func report(_ text: String) {
            try? text.write(toFile: reportPath, atomically: true, encoding: .utf8)
            print(text)
            NSApp.terminate(nil)
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = AppDelegate.editingMenu()
        app.buildSettings()
        let model = app.settingsModel
        model.showsWelcome = true
        model.refreshState()
        if CommandLine.arguments.contains("--preview-setup-ready") {
            // Without the permissions the field stays dimmed; this checks the selection alone.
            model.accessibility = true
            model.inputMonitoring = true
            model.fnSystemAction = .ready
        }
        model.reloadLayouts()
        guard let demo = model.demo else { return report("FAIL: no demo word for the enabled layouts") }
        app.correction.onSilentStop = { report("FAIL: \($0.localizedDescription)") }
        app.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        model.selectDemoWord()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            return report("FAIL: Keylapse is not the active app (\(front?.localizedName ?? "none") is), so the correction would go elsewhere")
        }
        guard let editor = app.window?.firstResponder as? NSTextView, editor.selectedRange().length == demo.typed.count else {
            return report("FAIL: the demo word is not selected (first responder \(String(describing: app.window?.firstResponder)); accessibility \(model.accessibility), input monitoring \(model.inputMonitoring), fn \(model.fnSystemAction))")
        }
        // The normal launch wires this up after the diagnostics return, so do it here.
        app.correction.onFinished = { if case .failure(let error) = $0 { report("FAIL: \(error.localizedDescription)") } }
        // With more than two layouts the wrong one has to be active and a destination chosen.
        try? app.inputs.select(demo.layoutID)
        app.handle(.correctSelection)
        var chose = false
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if !chose, let chooser = app.correction.chooser,
               let english = chooser.choices.first(where: { $0.title.hasPrefix("English") }) ?? chooser.choices.first {
                chose = true
                english.performClick(nil)
            }
            if model.demoSucceeded { return report("PASS: \(demo.typed) became \(model.demoText) in the welcome page") }
        }
        report("FAIL: the field still holds \(model.demoText)")
    }

    /// Opens Keyboard settings and writes every pop-up menu found there with its texts and frame;
    /// the one the floating hint would point at is marked. Needs Accessibility granted to the app.
    private static func checkFnMenu(reportPath: String) {
        NSApp.setActivationPolicy(.accessory)
        var lines: [String] = []
        if !AXIsProcessTrusted() { lines.append("FAIL: Enable Keylapse in Privacy & Security") }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier {
            let controls = PermissionHint.settingsControls(in: pid)
            let target = PermissionHint.fnMenu(in: pid)
            for label in controls.labels { lines.append("label \(label.text.debugDescription) \(NSStringFromRect(label.frame))") }
            for menu in controls.menus {
                let mark = target.map { CFEqual($0, menu.element) } == true ? "TARGET" : "menu  "
                lines.append("\(mark) \(menu.value.debugDescription) \(PermissionHint.frame(of: menu.element).map { NSStringFromRect($0) } ?? "no frame")")
            }
            lines.insert(target == nil ? "FAIL: the Fn menu was not found" : "PASS: the Fn menu was found", at: 0)
        } else { lines.append("FAIL: System Settings is not running") }
        try? lines.joined(separator: "\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Opens the Accessibility pane, shows the floating hint as if Grant… had been clicked, and
    /// reports the System Settings window and the hint as macOS lists them. No prompt, no grant.
    private static func checkPermissionHint(in app: AppDelegate, reportPath: String) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        app.buildSettings()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        // Put the Keylapse window right over System Settings, the worst case, to see it step aside.
        let list0 = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        if let b = list0.first(where: { ($0["kCGWindowOwnerName"] as? String) == "System Settings" && ($0["kCGWindowLayer"] as? Int) == 0 })?["kCGWindowBounds"] as? [String: CGFloat],
           let main = NSScreen.screens.first, let window = app.window {
            window.setFrameTopLeftPoint(NSPoint(x: (b["X"] ?? 0) + 60, y: main.frame.height - (b["Y"] ?? 0) + 20))
            window.orderFront(nil)
        }
        app.settingsModel.awaiting = .accessibility
        app.settingsModel.onAwaitingChanged?(.accessibility)
        RunLoop.current.run(until: Date().addingTimeInterval(1.8))
        var lines: [String] = []
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list {
            let owner = window["kCGWindowOwnerName"] as? String ?? ""
            let pid = window["kCGWindowOwnerPID"] as? Int32 ?? 0
            guard owner == "System Settings" || pid == ProcessInfo.processInfo.processIdentifier else { continue }
            let b = window["kCGWindowBounds"] as? [String: CGFloat] ?? [:]
            lines.append("\(owner) layer \(window["kCGWindowLayer"] ?? "") x \(Int(b["X"] ?? 0)) y \(Int(b["Y"] ?? 0)) w \(Int(b["Width"] ?? 0)) h \(Int(b["Height"] ?? 0))")
        }
        app.settingsModel.hintSwitchOn = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        try? app.permissionHint.snapshot()?.write(to: URL(fileURLWithPath: reportPath + ".png"))
        let report = lines.joined(separator: "\n")
        try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        print(report)
        NSApp.terminate(nil)
    }

    private static let offScreen = NSPoint(x: -20000, y: -20000)

    /// "fn", "rightOption", "leftCommand"…, for --preview-switch-key.
    private static func modifier(named name: String) -> HeldModifier? {
        for side in [Side.left, .right] where name.hasPrefix(side.rawValue) {
            return ModifierFamily(rawValue: name.dropFirst(side.rawValue.count).lowercased()).map { HeldModifier($0, side) }
        }
        return ModifierFamily(rawValue: name).map { HeldModifier($0) }
    }

    private static func checkSettings(in app: AppDelegate, snapshotPath: String) {
        let arguments = CommandLine.arguments
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        app.buildSettings()
        let model = app.settingsModel
        if arguments.contains("--preview-welcome") { model.showsWelcome = true; model.reloadLayouts() }
        if arguments.contains("--preview-settings-page") { model.showsWelcome = false }
        if arguments.contains("--preview-demo-done"), let demo = model.demo { model.demoText = demo.result }
        if arguments.contains("--preview-pulse") { model.hintSwitchOn = true }
        if arguments.contains("--preview-recording-switch") { model.recording = .switchKey }
        if arguments.contains("--preview-waiting") { model.awaiting = .accessibility; model.hintSwitchOn = true }
        if arguments.contains("--preview-waiting-fn") { model.awaiting = .fnKey; model.hintSwitchOn = true; model.fnSystemAction = .conflict }
        if arguments.contains("--preview-setup-ready") {
            model.accessibility = true
            model.inputMonitoring = true
            model.fnSystemAction = .ready
        }
        if arguments.contains("--preview-fn-conflict") { model.fnSystemAction = .conflict }
        else if arguments.contains("--preview-fn-unknown") { model.fnSystemAction = .unknown }
        if arguments.contains("--preview-missing-permissions") {
            model.accessibility = false
            model.inputMonitoring = false
        }
        if let key = argument(after: "--preview-switch-key").flatMap(modifier(named:)) {
            model.shortcut.switchTrigger = .modifiers(ModifierChord([key]))
        }
        if let rows = argument(after: "--preview-rows").flatMap(Int.init) { KeylapseSettingsView.visibleLayoutRows = rows }
        if arguments.contains("--preview-many-layouts") {
            // Seven made-up layouts, to see the list scroll with its tick rail.
            model.enabled = [("en", "English", "U.S."), ("uk", "Ukrainian", "Ukrainian-PC"), ("de", "German", nil), ("fr", "French", nil),
                             ("pl", "Polish", "Polish Pro"), ("tr", "Turkish", "Turkish Q"), ("sv", "Swedish", nil)]
                .map { LayoutOption(id: $0.0, language: $0.1, variant: $0.2, supportsCorrection: true) }
            model.current = model.enabled[1]
            model.enabled[6] = LayoutOption(id: "ja", language: "Japanese", variant: "Hiragana", supportsCorrection: false)
        }
        if arguments.contains("--preview-scrolled-to-end") {
            DispatchQueue.main.async { if let id = model.enabled.last?.id { model.scrollTo(id) } }
        }
        if arguments.contains("--preview-combo-shortcut") {
            // Left ⌘Space switches (taken from Spotlight, so the warning shows), right ⌘Space corrects.
            model.shortcut = Shortcut(switchTrigger: .combo(KeyCombo(keyCode: 49, modifiers: .command, sides: .leftCommand)),
                                      correction: .combo(KeyCombo(keyCode: 49, modifiers: .command, sides: .rightCommand)))
        }
        if arguments.contains("--preview-recording") {
            model.recording = .correction
            model.recordingHint = "Release to use Control + Option on its own, or press another key with it."
        }
        if arguments.contains("--preview-refused") {
            model.recording = .correction
            model.rejected = .correction
            model.recordingHint = "Fn is already the other shortcut. Press something different."
        }
        // Rendered off screen, so nothing flashes in front of the user; the window still has to
        // be ordered in for SwiftUI to lay out.
        app.window?.setFrameOrigin(Self.offScreen)
        app.window?.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        if arguments.contains("--preview-destinations") {
            let sources = app.inputs.sources.filter(\.supportsCorrection)
            if sources.count > 1 {
                app.correction.presentDestinations(sources.dropFirst().map { (id: $0.id, title: $0.name(among: sources)) }) { _ in }
                app.correction.chooser?.setFrameOrigin(Self.offScreen)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        app.window?.contentView?.layoutSubtreeIfNeeded()
        guard let content = ((app.correction.chooser as NSWindow?) ?? app.window)?.contentView?.superview,
              content.bounds.width >= 180, content.bounds.height >= 60,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { fatalError("Cannot render settings") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode settings") }
        do { try png.write(to: URL(fileURLWithPath: snapshotPath)) }
        catch { fatalError(error.localizedDescription) }
        let report = "PASS: SwiftUI settings rendered at \(Int(content.bounds.width)) × \(Int(content.bounds.height)) pt. Interactive checks are separate. Layout scroll offset \(Int(model.layoutScrollOffset))."
        try? report.write(toFile: snapshotPath + ".txt", atomically: true, encoding: .utf8)
        print(report)
        NSApp.terminate(nil)
    }
}
