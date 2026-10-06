import Cocoa
import SwiftUI
import KeylapseCore

/// The first page a new user sees: what Keylapse does, the three setup steps with the reason
/// for each, a word typed in the wrong layout to correct right here, and a Start button.
/// It uses the same glass, groups and keycaps as the settings, so nothing changes style when
/// the settings take its place.
extension KeylapseSettingsView {
    var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The same logo, in the same place, as the settings page that follows: the pixel
            // flower beside the name. Nothing moves in the header when Start swaps the pages.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    FlowerGlyph()
                        .frame(width: Flower.size, height: Flower.size)
                        .accessibilityHidden(true)
                    Text("Keylapse")
                        .font(.system(size: 34, weight: .light))
                }
                Text("Fixes text typed in the wrong layout.")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .padding(.bottom, 4)

            section("Setup") {
                group {
                    step("Accessibility", why: "To replace the text you select.",
                         waitingWhy: "Turn on Keylapse in the list.",
                         granted: model.accessibility, waiting: model.awaiting == .accessibility,
                         current: model.currentStep == .accessibility) { model.grant(.accessibility) }
                    divider
                    // macOS lets an app with Accessibility watch the keyboard too, so this step nearly
                    // always completes by itself. It says so, and asks for a click only if it did not.
                    step("Input Monitoring", why: inputMonitoringWhy,
                         waitingWhy: "Not listed? Click + and add Keylapse.",
                         granted: model.inputMonitoring, waiting: model.awaiting == .inputMonitoring,
                         current: model.currentStep == .inputMonitoring, offersButton: model.accessibility) { model.grant(.inputMonitoring) }
                    divider
                    // The switch key is chosen once Keylapse may watch the keyboard, not before:
                    // a key set earlier could not switch anything and would only look broken.
                    fnStep
                        .disabled(!(model.accessibility && model.inputMonitoring))
                        .allowsHitTesting(model.accessibility && model.inputMonitoring)
                }
                note("Your text stays on your Mac. Nothing is sent.")
            }

            if model.demo != nil {
                section("Try it") { demoGroup }
            }

            HStack(alignment: .center, spacing: 12) {
                compactBehavior("Launch at login", value: model.launchAtLogin, available: !needsSetup, set: model.setLaunchAtLogin)
                    .opacity(needsSetup ? 0.5 : 1)
                Spacer(minLength: 12)
                // Prominent only when it is the next thing to do; until then it is one of the plain buttons.
                // There is nothing to start using until the setup steps are done, so until then
                // the button is not offered; Try it may be skipped.
                stepButton("Start using Keylapse", current: model.currentStep == .start, large: true, action: model.finishWelcome)
                    .disabled(needsSetup)
                    .help(needsSetup ? "Finish the setup steps above first" : "Show the Keylapse window with layouts, behavior and shortcuts")
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                FlowerGlyph()
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)
                note("Click the menu bar flower to come back.")
            }
            .padding(.top, -8)
        }
        .onAppear { if !needsSetup { model.selectDemoWord() } }
        .onChange(of: needsSetup) { incomplete in if !incomplete { model.selectDemoWord() } }
        // Recording takes the keyboard; once it ends the word is selected again, ready for the new keys.
        .onChange(of: model.recording) { target in if target == nil && !needsSetup { model.selectDemoWord() } }
    }

    /// One setup step: its name, why it is needed beneath, and the button or checkmark at the right.
    /// While waiting for macOS the reason gives way to the one thing left to do there, and the
    /// button to a replica of the System Settings row with its switch flipping on.
    private func step(_ title: String, why: String, waitingWhy: String, granted: Bool, waiting: Bool, current: Bool,
                      offersButton: Bool = true, action: @escaping () -> Void) -> some View {
        stepRow(why: waiting ? waitingWhy : why, granted: granted, waiting: waiting, current: current, offersButton: offersButton, action: action) { Text(title) }
            .accessibilityElement(children: granted ? .ignore : .contain)
            .accessibilityLabel(title)
            .accessibilityValue(granted ? "Ready" : waiting ? "Waiting for System Settings" : "Not granted")
            .help(granted ? "" : waiting ? "Turn on Keylapse in System Settings; this updates by itself" : "Open \(title) in System Settings")
    }

    private var inputMonitoringWhy: String {
        if !model.accessibility { return "Usually comes with Accessibility." }
        if model.inputMonitoring && !model.inputMonitoringAsked { return "Came with Accessibility." }
        return "To see the shortcut keys."
    }

    /// A step whose turn has not come steps back to half strength; done, waiting and current ones are full.
    private func stepRow<Title: View>(why: String, granted: Bool, waiting: Bool = false, current: Bool = false,
                                      replica: SettingsRowReplica.Kind = .appSwitch, buttonTitle: String = "Grant…",
                                      alternative: (title: String, action: () -> Void)? = nil, offersButton: Bool = true,
                                      action: @escaping () -> Void, @ViewBuilder title: () -> Title) -> some View {
        row {
            VStack(alignment: .leading, spacing: 3) {
                // The line that says what this step is for is the one that breathes while it is the
                // step's turn (white; accent text was tried and is too dark to read on the glass).
                // The name above is already larger and bolder, so it steps back to let that show.
                let lit = (current || waiting) && !granted
                title()
                    .opacity(lit ? 0.7 : 1)
                Text(why)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(lit ? Color.white : SettingsPalette.secondary)
                    .opacity(lit && !model.hintSwitchOn ? 0.5 : 1)
                    .animation(.easeInOut(duration: 0.8), value: model.hintSwitchOn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(granted || waiting || current ? 1 : 0.5)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, SettingsPalette.accent)
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityHidden(true)
            } else if waiting {
                SettingsRowReplica(kind: replica, on: model.hintSwitchOn, action: action)
            } else if offersButton {
                // The other way through the step, as a button in its own right: this is a choice
                // between two options, not a footnote to the main one.
                if let alternative {
                    Button(alternative.title, action: alternative.action)
                        .buttonStyle(QuietButtonStyle())
                }
                stepButton(buttonTitle, current: current, action: action)
            }
        }
        .padding(.vertical, 8)
    }

    /// The third step is about the key that switches layouts. With Fn it asks for the macOS Fn
    /// action to be Do Nothing, and offers a way out for someone who would rather not give Fn to
    /// Keylapse: Use other keys records a different shortcut right here, after which nothing
    /// in macOS has to change and the step is done.
    @ViewBuilder
    private var fnStep: some View {
        // Which shortcut this row is recording: the switch key, or, while Fn still has to be
        // settled, the correction keys (Try it is off then, so that recording can only be ours).
        let target: SettingsModel.RecordingTarget? = model.recording == .switchKey ? .switchKey
            : model.recording == .correction && model.needsFnSetup ? .correction : nil
        let recording = target != nil
        // Done either way, with Fn or without, the row shows the keys that switch and lets a
        // click change them; only Fn still waiting for macOS shows the two buttons.
        if recording || !model.shortcut.needsFnSystemAction || model.fnSystemAction == .ready {
            // A key can be chosen before the permissions, but it cannot switch anything until
            // Keylapse may watch the keyboard: no checkmark yet, and the row says what it waits for.
            let working = model.accessibility && model.inputMonitoring
            let shown = target ?? .switchKey
            row {
                VStack(alignment: .leading, spacing: 3) {
                    // While recording the row's name is the thing to do, breathing like every
                    // next step, so it is plain that the window is waiting for a key press.
                    Text(target == .correction ? "Now press keys to correct text" : recording ? "Press a key to switch layouts" : "Switch layouts")
                        .opacity(recording && !model.hintSwitchOn ? 0.62 : 1)
                        .animation(.easeInOut(duration: 0.8), value: model.hintSwitchOn)
                    Text(recording ? (model.recordingHint ?? "Modifiers alone work too. Esc cancels.") : working ? "Click the keys to change them." : "Works once Accessibility is granted.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.rejected == shown ? SettingsPalette.refusal : SettingsPalette.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(recording || working ? 1 : 0.5)
                recordableKeys(SettingsKeycap.Key.keys(for: shown == .correction ? model.shortcut.correction : model.shortcut.switchTrigger), target: shown)
                    .fixedSize()
                if !recording && working {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SettingsPalette.accent)
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 8)
        } else {
            // Doing without Fn means both shortcuts without it: the one that still has Fn is
            // recorded first, and the other follows by itself if it has Fn too.
            let other: SettingsModel.RecordingTarget = model.shortcut.switchTrigger.usesFn ? .switchKey : .correction
            // The name says what the key is for, like the finished row; what has to be done in
            // macOS is the line beneath, the one that breathes.
            let purpose = model.shortcut.switchTrigger.usesFn
                ? "Switch layouts with \(KeyNames.title(model.shortcut.switchTrigger))"
                : "Correct text with \(KeyNames.title(model.shortcut.correction))"
            stepRow(why: model.awaiting == .fnKey ? "Choose this in System Settings." : "Set Fn to “Do Nothing” in macOS.",
                    granted: model.fnSystemAction == .ready, waiting: model.awaiting == .fnKey,
                    current: model.currentStep == .fnKey, replica: .fnKey,
                    buttonTitle: "Open Settings", alternative: ("Use other keys", { model.stopWaiting(); model.startRecording(other, withoutFn: true) }),
                    action: { model.grant(.fnKey) }) {
                Text(purpose)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .help(model.fnSystemAction == .ready ? "" : "In macOS Keyboard settings, set the Fn key action to Do Nothing, or use shortcuts without Fn.")
        }
    }

    /// A text field holding hello typed on the other layout, with the correction keys at the
    /// right edge like a Shortcuts row. Below, what to do; after the correction, that it worked.
    private var demoGroup: some View {
        let ready = !needsSetup
        let succeeded = model.demoSucceeded
        // While setup is unfinished the correction keys may be being recorded in the setup row
        // above; this block is off and shows none of it.
        let recordingHere = model.recording == .correction && ready
        return group {
            row {
                DemoField(text: Binding(get: { model.demoText }, set: { model.demoText = $0 }),
                          selectionToken: model.demoSelectionToken, enabled: ready)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Text to correct")
                if succeeded {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SettingsPalette.accent)
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 50)
            divider
            // Built like the Switch layouts row above: the action by its name, what to do
            // beneath, the keys at the right. The name is the one used in Shortcuts and in the
            // menu bar menu, so the user learns what these keys are called.
            row {
                let current = model.currentStep == .tryIt || recordingHere
                VStack(alignment: .leading, spacing: 3) {
                    Text("Correct selected text")
                        .opacity(current ? 0.7 : 1)
                    Text(demoHint(ready: ready, succeeded: succeeded))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.rejected == .correction && ready ? SettingsPalette.refusal
                                         : current || succeeded ? Color.white : SettingsPalette.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .opacity(current && !model.hintSwitchOn ? 0.5 : 1)
                        .animation(.easeInOut(duration: 0.8), value: model.hintSwitchOn)
                        .animation(.easeOut(duration: 0.2), value: succeeded)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // One button for the row's other action: other keys before the correction, the
                // wrong word back after it.
                if recordingHere {
                    Button("Cancel", action: model.stopRecording)
                        .buttonStyle(QuietButtonStyle())
                } else if succeeded {
                    Button("Again", action: model.resetDemo)
                        .buttonStyle(QuietButtonStyle())
                        .help("Put the wrong word back and try again. ⌘Z undoes a correction in any app.")
                } else {
                    Button("Set my own") { model.startRecording(.correction) }
                        .buttonStyle(QuietButtonStyle())
                        .help("Record another shortcut for correcting text")
                }
                // The keys stay after the correction: they are what the user takes away from here.
                recordableKeys(SettingsKeycap.Key.keys(for: model.shortcut.correction), target: .correction,
                               pulsing: model.currentStep == .tryIt, quiet: !ready)
                    .fixedSize()
                    .accessibilityLabel(KeyNames.title(model.shortcut.correction))
            }
            .frame(height: 58)
        }
        .opacity(ready ? 1 : 0.45)
        // It looks inactive until the setup is done, so it is: nothing in it answers a click.
        .disabled(!ready)
        .allowsHitTesting(ready)
    }

    private func demoHint(ready: Bool, succeeded: Bool) -> String {
        guard let demo = model.demo else { return "" }
        if model.recording == .correction && ready { return model.recordingHint ?? "Press a key or combination, or modifiers alone." }
        if !ready { return "Finish the setup above first." }
        if succeeded { return "Fixed. These keys work in every app." }
        // Try it obeys the same rules as a correction anywhere else, so it says when the
        // active layout would make the real correction refuse or ask.
        if demo.needsSwitch { return "Switch to \(demo.layoutName) first, then press the keys." }
        return "Press these keys, or set your own."
    }
}

/// A plain text field on the glass. The window selects the whole word in it whenever the
/// selection token changes, so the shortcut can be pressed straight away.
private struct DemoField: NSViewRepresentable {
    @Binding var text: String
    let selectionToken: Int
    let enabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17, weight: .regular)
        field.textColor = .white
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // Edits report back through the binding first, so a mismatch is always a change from the model.
        if field.stringValue != text { field.stringValue = text }
        field.isEnabled = enabled
        field.textColor = enabled ? .white : NSColor.white.withAlphaComponent(0.62)
        if context.coordinator.appliedToken != selectionToken {
            context.coordinator.appliedToken = selectionToken
            DispatchQueue.main.async {
                guard enabled, let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DemoField
        var appliedToken = 0
        init(_ parent: DemoField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
