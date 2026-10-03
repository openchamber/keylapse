import Cocoa
import ServiceManagement
import SwiftUI
import KeylapseCore

enum SettingsPalette {
    static let text = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let group = Color.white.opacity(0.10)
    static let divider = Color.white.opacity(0.12)
    /// Follows the accent colour chosen in System Settings.
    static let accent = Color.accentColor
    /// Marks keys that were refused while recording.
    static let refusal = Color(red: 1, green: 0.33, blue: 0.3)
}

struct KeylapseSettingsView: View {
    @ObservedObject var model: SettingsModel

    var needsSetup: Bool {
        !model.accessibility || !model.inputMonitoring || model.needsFnSetup
    }

    /// Rows the Layouts list shows before it starts scrolling on its own.
    /// Rows the Layouts list shows at once (odd, so the active one sits in the middle).
    static var visibleLayoutRows = 3
    /// Before the left column has been measured.
    static let defaultLayoutRowHeight: CGFloat = 60

    /// Three rows share the height of the Setup + Behavior block, so both columns end together.
    private var layoutRowHeight: CGFloat {
        let available = model.leftBlockHeight - model.layoutsHeadingHeight - 8
        guard model.leftBlockHeight > 0, model.layoutsHeadingHeight > 0, available > 0 else { return Self.defaultLayoutRowHeight }
        return ((available - CGFloat(Self.visibleLayoutRows - 1)) / CGFloat(Self.visibleLayoutRows)).rounded(.down)
    }
    /// Extra inset of the header block on both sides; the tick rail lives in the right one.
    static let headerInset: CGFloat = 30
    /// Title row (42) + column spacing (10) + the Setup heading's top padding (14).
    static let layoutsTop: CGFloat = 66
    /// Every shortcut row is this tall, whatever its hint says, so the window never jumps.
    static let shortcutRowHeight: CGFloat = 66

    var body: some View {
        Group {
            if model.showsWelcome { welcome } else { settings }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(SettingsPalette.text)
        .tint(SettingsPalette.accent)
        .preferredColorScheme(.dark)
    }

    private var settings: some View {
          VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        FlowerGlyph()
                            .frame(width: Flower.size, height: Flower.size)
                            .accessibilityHidden(true)
                        Text("Keylapse")
                            .font(.system(size: 34, weight: .light))
                    }
                    if !needsSetup {
                      VStack(alignment: .leading, spacing: 0) {
                        setupSummary
                        VStack(alignment: .leading, spacing: 8) {
                            heading("Behavior")
                            compactBehavior("Switch on key release", value: model.switchesOnRelease, available: model.canSwitchOnRelease, set: model.setSwitchOnRelease)
                                .help(model.canSwitchOnRelease ? "Switch when you release Fn instead of when you press it."
                                      : model.switchesOnRelease ? "Modifier keys always switch on release, so shortcuts like Option-E keep working."
                                      : "A key combination switches as soon as it is pressed.")
                            compactBehavior("Launch at login", value: model.launchAtLogin, set: model.setLaunchAtLogin)
                            compactBehavior("Correct on menu bar click", value: model.clickIconToCorrect, set: model.setClickIconToCorrect)
                                .help("Select text, then click the flower in the menu bar to correct it. Right-click opens the menu.")
                        }
                        .padding(.top, 24)
                      }
                      .background(HeightReader { model.leftBlockHeight = $0 })
                      .padding(.top, 14)
                    }
                }
                .frame(width: 220, alignment: .leading)

                // Starts level with the Setup heading and ends with the last Behavior row, so the
                // two columns read as one block under the title.
                VStack(alignment: .trailing, spacing: 8) {
                    heading("Layouts")
                        .background(HeightReader { model.layoutsHeadingHeight = $0 })
                    layoutList
                    if model.enabled.filter(\.supportsCorrection).count < 2 {
                        note("Text correction needs two supported layouts.")
                    }
                }
                .padding(.top, Self.layoutsTop)
                .padding(.trailing, Self.headerInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if needsSetup { setup }

            section("Shortcuts") {
                group {
                    shortcutRow("Switch layouts", target: .switchKey, trigger: model.shortcut.switchTrigger)
                    divider
                    shortcutRow("Correct selected text", target: .correction, trigger: model.shortcut.correction)
                }
                HStack(alignment: .firstTextBaseline) {
                    note("To change a shortcut, click its keys, then press the key or combination you want. Esc keeps the current one.")
                    Spacer(minLength: 12)
                    // Always laid out, so the line does not move when it appears.
                    Button("Reset", action: model.resetShortcut)
                        .buttonStyle(QuietButtonStyle())
                        .help("Back to Fn and Control + Fn")
                        .opacity(model.shortcut == .standard ? 0 : 1)
                        .disabled(model.shortcut == .standard)
                        .accessibilityHidden(model.shortcut == .standard)
                }
            }
          }
    }

    /// Up to four layouts are listed outright. More become a loop: the rows are laid out three
    /// times over and the scroll position is quietly moved back a copy whenever it nears either
    /// end, so the list can always put the active layout in the middle, whichever one it is.
    /// Instead of a scrollbar, a rail of short ticks on the right marks every layout: the
    /// active one is longer and brighter, hovering stretches the ticks nearby, and clicking one
    /// makes that layout active.
    private var layoutList: some View {
        let count = model.enabled.count
        let overflowing = count > Self.visibleLayoutRows
        let visible = min(count, Self.visibleLayoutRows)
        let height = CGFloat(visible) * layoutRowHeight + CGFloat(max(visible - 1, 0))
        let copies = overflowing ? 3 : 1
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(0..<copies, id: \.self) { copy in
                        ForEach(Array(model.enabled.enumerated()), id: \.element.id) { index, option in
                            if index > 0 || copy > 0 { SettingsPalette.divider.frame(height: 1).accessibilityHidden(true) }
                            layoutRow(option, active: option.id == model.current?.id)
                                .id(Self.rowID(option.id, copy: copy))
                                .accessibilityHidden(copy != (overflowing ? 1 : 0))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background {
                    ScrollOffsetObserver(loop: overflowing ? LoopGeometry(count: count, pitch: layoutRowHeight + 1, visibleHeight: height) : nil,
                                         target: targetRow) { offset in
                        if abs(model.layoutScrollOffset - offset) > 0.5 { model.layoutScrollOffset = offset }
                    }
                }
            }
            .onChange(of: model.current?.id) { id in
                if let id { model.scrollTo(id) }
            }
            .onAppear {
                if let id = model.current?.id { model.scrollTo(id, instant: true) }
            }
            .frame(height: height)
            .mask {
                // In a loop both edges always hide rows, so both fade.
                LinearGradient(stops: [
                    .init(color: .black.opacity(overflowing ? 0 : 1), location: 0),
                    .init(color: .black, location: 0.2),
                    .init(color: .black, location: 0.8),
                    .init(color: .black.opacity(overflowing ? 0 : 1), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .trailing) {
                if overflowing {
                    TickRail(count: count, activeIndex: model.enabled.firstIndex { $0.id == model.current?.id },
                             highlighted: model.railHighlight, hover: { model.railHighlight = $0 }) { index in
                        model.selectLayout(model.enabled[index].id)
                    }
                    .offset(x: 30)
                    .accessibilityLabel("Layouts")
                }
            }
        }
    }

    private static func rowID(_ id: String, copy: Int) -> String { "\(copy)/\(id)" }

    /// The pending scroll request as a row index, for the AppKit-side scroller.
    private var targetRow: ScrollTarget? {
        guard let request = model.scrollRequest, let index = model.enabled.firstIndex(where: { $0.id == request.id }) else { return nil }
        return ScrollTarget(index: index, token: request.token, instant: request.instant)
    }

    /// Layouts read like widget entries: the language large, the variant beneath.
    /// The active layout is bright with an accent dot; the rest step back. Clicking one makes it active.
    private func layoutRow(_ option: LayoutOption, active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Spacer()
            if active {
                Circle()
                    .fill(SettingsPalette.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(option.language)
                    .font(.system(size: layoutRowHeight >= 54 ? 22 : 19, weight: .light))
                // Variant and the correction note share one line so every row is two lines tall.
                HStack(spacing: 6) {
                    if !option.supportsCorrection {
                        tag("Switching only", colour: SettingsPalette.secondary)
                            .help("Text correction isn’t supported for this layout yet.")
                    }
                    if option.variant != nil && !option.supportsCorrection {
                        Text("·").foregroundStyle(SettingsPalette.secondary)
                    }
                    if let variant = option.variant {
                        Text(variant)
                            .font(.system(size: layoutRowHeight >= 54 ? 12 : 11, weight: .medium))
                            .foregroundStyle(SettingsPalette.secondary)
                    }
                }
            }
        }
        .foregroundStyle(active ? SettingsPalette.text : SettingsPalette.text.opacity(0.7))
        .frame(height: layoutRowHeight)
        .contentShape(Rectangle())
        .onTapGesture { if !active { model.selectLayout(option.id) } }
        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .help(active ? "" : "Switch to \(option.title)")
        .accessibilityElement(children: .combine)
        .accessibilityValue(active ? "Active" : "")
        .accessibilityAddTraits(.isButton)
    }

    /// Once everything is ready there is nothing to do here, so Setup becomes a quiet status list.
    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Setup")
            ready("Accessibility")
            ready("Input Monitoring")
            // Always listed so the column never changes height; dimmed while no shortcut uses Fn.
            ready("Fn key action", applies: model.shortcut.needsFnSystemAction)
        }
    }

    private func ready(_ title: String, applies: Bool = true) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .regular))
        }
        .foregroundStyle(SettingsPalette.secondary)
        .opacity(applies ? 1 : 0.45)
        .help(applies ? "" : "Applies while Fn on its own is a shortcut.")
        .accessibilityElement(children: .combine)
        .accessibilityValue(applies ? "Ready" : "Not needed")
    }

    private var setup: some View {
        section("Setup") {
            group {
                permission("Accessibility", granted: model.accessibility, waiting: model.awaiting == .accessibility,
                           current: model.currentStep == .accessibility) { model.grant(.accessibility) }
                divider
                permission("Input Monitoring", granted: model.inputMonitoring, waiting: model.awaiting == .inputMonitoring,
                           current: model.currentStep == .inputMonitoring) { model.grant(.inputMonitoring) }
                divider
                if !model.shortcut.needsFnSystemAction {
                    row { Text("Fn key action"); Spacer() }
                        .opacity(0.45)
                        .help("Applies while a shortcut uses Fn.")
                } else {
                    if model.fnSystemAction == .ready {
                        permission("Fn key action", granted: true, action: model.openFnSettings)
                    } else {
                        row {
                            HStack(spacing: 4) {
                                Text("Set")
                                Image(systemName: "globe")
                                Text("Fn key to “Do Nothing”")
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Set Fn key to Do Nothing")
                            .opacity(model.currentStep == .fnKey || model.awaiting == .fnKey ? 1 : 0.5)
                            Spacer()
                            if model.awaiting == .fnKey {
                                SettingsRowReplica(kind: .fnKey, on: model.hintSwitchOn) { model.grant(.fnKey) }
                            } else {
                                stepButton("Open Settings", current: model.currentStep == .fnKey) { model.grant(.fnKey) }
                            }
                        }
                        .help("In macOS Keyboard settings, set the Fn key action to Do Nothing.")
                    }
                }
            }
            note("Your text stays on your Mac. Nothing is sent.")
        }
    }

    /// Same quiet style as the Setup list: a mini switch on the left, like the checkmarks above it.
    /// The label is white whenever the option applies; it steps back only while it does not.
    func compactBehavior(_ title: String, value: Bool, available: Bool = true, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: Binding(get: { value }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(SettingsPalette.accent)
                .disabled(!available)
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(available ? SettingsPalette.text : SettingsPalette.secondary)
                .onTapGesture { if available { set(!value) } }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    func permission(_ title: String, granted: Bool, waiting: Bool = false, current: Bool = false, action: @escaping () -> Void) -> some View {
        row {
            Text(title)
                .opacity(granted || waiting || current ? 1 : 0.5)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, SettingsPalette.accent)
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityHidden(true)
            } else if waiting {
                SettingsRowReplica(on: model.hintSwitchOn, action: action)
            } else {
                stepButton("Grant…", current: current, action: action)
            }
        }
        .accessibilityElement(children: granted ? .ignore : .contain)
        .accessibilityLabel(title)
        .accessibilityValue(granted ? "Ready" : waiting ? "Waiting for System Settings" : "Not granted")
        .help(granted ? "" : waiting ? "Turn on Keylapse in System Settings; this updates by itself" : "Open \(title) in System Settings")
    }

    /// A step's button. The next thing to do is the only prominent control in the window and
    /// its accent glow breathes; steps whose turn has not come are plain.
    @ViewBuilder
    func stepButton(_ title: String, current: Bool, large: Bool = false, action: @escaping () -> Void) -> some View {
        if current {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(large ? .regular : .small)
                .shadow(color: SettingsPalette.accent.opacity(model.hintSwitchOn ? 0.9 : 0.25), radius: model.hintSwitchOn ? 9 : 3)
                .animation(.easeInOut(duration: 0.8), value: model.hintSwitchOn)
        } else {
            Button(title, action: action)
                .buttonStyle(QuietButtonStyle(large: large))
        }
    }

    func heading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(SettingsPalette.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SettingsPalette.secondary)
            .lineSpacing(3)
            .padding(.horizontal, 2)
    }

    private func tag(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colour)
    }

    /// A section is a small-caps heading over one translucent group of rows.
    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(title)
            VStack(alignment: .leading, spacing: 8, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Rows share one rounded translucent surface, separated by hairlines.
    func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var divider: some View {
        SettingsPalette.divider.frame(height: 1).padding(.leading, 12).accessibilityHidden(true)
    }

    func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The hint under a shortcut's name: how to press it, plus what macOS does with the same
    /// keys or when it fires; while recording, what is expected; after a refusal, why.
    private func detail(for target: SettingsModel.RecordingTarget, trigger: Trigger) -> String {
        if model.recording == target {
            return model.recordingHint ?? "Press the key or combination to use. Esc keeps the current one."
        }
        // A shortcut with Fn in it does nothing for Keylapse while macOS keeps the key for
        // itself; the row must not look ready when it is not.
        if model.needsFnSetup && trigger.usesFn {
            return "Not working yet: set Fn to “Do Nothing” above,\nor click the keys to use others."
        }
        var lines: [String] = []
        switch trigger {
        case .modifiers(let chord):
            lines.append(chord.keys.count == 1 ? "Press \(chord.title) on its own" : "Press \(chord.title) together")
            if target == .switchKey && !chord.isFnAlone {
                lines.append("Switches when released, so shortcuts like Option-E keep working.")
            }
        case .combo(let combo):
            lines.append("Press \(KeyNames.title(combo))")
        }
        if let notice = model.systemNotice(for: trigger) { lines.append(notice) }
        return lines.joined(separator: "\n")
    }

    /// The drawn keys are the control: click them, then press the key or combination to use instead.
    /// Every key of a combination is drawn, joined by plus signs.
    /// `pulsing` gives them the breathing accent edge of the next step on the welcome page.
    /// `quiet` draws them plain even while that shortcut is being recorded elsewhere on the page.
    func recordableKeys(_ keys: [SettingsKeycap.Key], target: SettingsModel.RecordingTarget, pulsing: Bool = false, quiet: Bool = false) -> some View {
        let active = model.recording == target && !quiet
        let hovered = model.hoveredKeys == target && !quiet
        let refused = model.rejected == target && !quiet
        let breathing = pulsing && !active && !refused
        return Button {
            active ? model.stopRecording() : model.startRecording(target)
        } label: {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsPalette.secondary)
                            .accessibilityHidden(true)
                    }
                    SettingsKeycap(key)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(refused ? SettingsPalette.refusal : active ? SettingsPalette.accent
                                              : breathing ? SettingsPalette.accent.opacity(model.hintSwitchOn ? 1 : 0.25) : .white.opacity(hovered ? 0.6 : 0),
                                              lineWidth: active || refused || breathing ? 2 : 1)
                        }
                        // Waiting for a key press glows, and breathes wherever the beat is running.
                        .shadow(color: SettingsPalette.accent.opacity(active && !refused ? (model.hintSwitchOn ? 0.95 : 0.4) : breathing && model.hintSwitchOn ? 0.8 : 0),
                                radius: active ? 9 : 7)
                        .animation(.easeInOut(duration: 0.8), value: model.hintSwitchOn)
                        .brightness(hovered && !active ? 0.12 : 0)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hovered)
            .animation(refused ? .easeInOut(duration: 0.14).repeatCount(5, autoreverses: true) : .easeOut(duration: 0.3), value: refused)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            model.hoveredKeys = inside ? target : (model.hoveredKeys == target ? nil : model.hoveredKeys)
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityHint(active ? "Waiting for a key press" : "Click, then press the key or combination to use instead")
        .help(active ? "Press the key or combination you want, or Esc to keep the current one" : "Click, then press the key or combination you want")
    }

    /// One shortcut row: the action and how to press it on the left, the keys on the right.
    /// The row is a fixed height and the hint has room for two lines, so nothing shifts.
    private func shortcutRow(_ title: String, target: SettingsModel.RecordingTarget, trigger: Trigger) -> some View {
        let refused = model.rejected == target
        let waitsForFn = model.needsFnSetup && trigger.usesFn && model.recording != target
        return row {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .opacity(waitsForFn ? 0.5 : 1)
                Text(detail(for: target, trigger: trigger))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(refused ? SettingsPalette.refusal : SettingsPalette.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .frame(height: 28, alignment: .topLeading)
                    .animation(.easeOut(duration: 0.2), value: refused)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            recordableKeys(SettingsKeycap.Key.keys(for: trigger), target: target)
                .fixedSize()
                .opacity(waitsForFn ? 0.5 : 1)
        }
        .frame(height: Self.shortcutRowHeight)
    }

}

/// Reports a view's height into the model (no @State under the Command Line Tools).
struct HeightReader: View {
    let report: (CGFloat) -> Void
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { report(geometry.size.height) }
                .onChange(of: geometry.size.height) { report($0) }
        }
    }
}

/// The menu bar flower for the page header, from the same image as everywhere else.
struct FlowerGlyph: View {
    var body: some View {
        Image(nsImage: Flower.image)
            .renderingMode(.template)
            .resizable()
            .interpolation(.none)
            .foregroundStyle(.white)
    }
}

/// A small replica of the row the user is about to find in System Settings: the app icon, the
/// name and a switch that keeps flipping on, so the gesture is shown rather than described.
/// Clicking it opens the pane again.
struct SettingsRowReplica: View {
    /// Which System Settings row is shown: the app's switch in a privacy list, or the
    /// "Press 🌐 key to" menu in Keyboard settings with Do Nothing being chosen.
    enum Kind { case appSwitch, fnKey }
    var kind: Kind = .appSwitch
    let on: Bool
    let action: () -> Void
    var scale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * scale) {
                switch kind {
                case .appSwitch:
                    Image(nsImage: Flower.appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16 * scale, height: 16 * scale)
                    Text("Keylapse")
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundStyle(SettingsPalette.text)
                    Toggle("", isOn: .constant(on))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(scale > 1 ? .small : .mini)
                        .tint(SettingsPalette.accent)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.25), value: on)
                case .fnKey:
                    HStack(spacing: 3 * scale) {
                        Text("Press")
                        Image(systemName: "globe")
                        Text("key to")
                    }
                    .font(.system(size: 11 * scale, weight: .medium))
                    .foregroundStyle(SettingsPalette.text)
                    // The menu's value, lighting up as if it were being picked.
                    HStack(spacing: 3 * scale) {
                        Text("Do Nothing")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8 * scale, weight: .bold))
                    }
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(on ? SettingsPalette.accent : Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 5 * scale, style: .continuous))
                    .animation(.easeInOut(duration: 0.25), value: on)
                }
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .appSwitch ? "Waiting for the Keylapse switch in System Settings" : "Waiting for the Fn key action to be set to Do Nothing")
        .accessibilityHint("Opens System Settings again")
    }
}

/// Row geometry of the looping list: `count` rows of `pitch` points, laid out three times.
struct LoopGeometry: Equatable {
    let count: Int
    let pitch: CGFloat
    let visibleHeight: CGFloat
    var copyHeight: CGFloat { CGFloat(count) * pitch }
    var contentHeight: CGFloat { copyHeight * 3 }

    /// Scroll offset that centres row `index` of copy `copy`.
    func offset(centring index: Int, copy: Int) -> CGFloat {
        let centre = (CGFloat(copy * count + index) + 0.5) * pitch
        return min(max(centre - visibleHeight / 2, 0), contentHeight - visibleHeight)
    }

    /// The same view one copy up or down, kept inside the middle band so there is always a
    /// copy's worth of rows above and below.
    func normalised(_ y: CGFloat) -> CGFloat {
        var y = y
        while y < copyHeight * 0.5 { y += copyHeight }
        while y >= copyHeight * 1.5 { y -= copyHeight }
        return y
    }
}

struct ScrollTarget: Equatable {
    let index: Int
    let token: Int
    let instant: Bool
}

/// Reports the vertical scroll offset of the enclosing scroll view. SwiftUI's own geometry
/// preferences do not update on scroll on macOS, so this listens to the AppKit clip view.
/// With a `loop`, it also drives the scrolling: a target row is reached by the shortest way,
/// forward past the last row into the first copy if that is nearer, and once the animation
/// ends the position is moved a copy up or down without any visible change. Manual scrolling
/// wraps the same way.
private struct ScrollOffsetObserver: NSViewRepresentable {
    var loop: LoopGeometry?
    var target: ScrollTarget?
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        view.loop = loop
        view.pendingTarget = target
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.loop = loop
        if let target, target != view.appliedTarget { view.pendingTarget = target; view.applyTargetIfPossible() }
    }

    final class ObserverView: NSView {
        var onChange: ((CGFloat) -> Void)?
        var loop: LoopGeometry?
        var pendingTarget: ScrollTarget?
        var appliedTarget: ScrollTarget?
        private var animating = false
        private var observation: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let clipView = enclosingScrollView?.contentView else { return }
            clipView.postsBoundsChangedNotifications = true
            observation = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self, weak clipView] _ in
                guard let self, let clipView else { return }
                var origin = clipView.bounds.origin
                if let loop = self.loop, !self.animating {
                    let wrapped = loop.normalised(origin.y)
                    if wrapped != origin.y { origin.y = wrapped; clipView.setBoundsOrigin(origin) }
                }
                self.onChange?(origin.y)
                self.applyTargetIfPossible()
            }
            onChange?(clipView.bounds.origin.y)
            DispatchQueue.main.async { [weak self] in self?.applyTargetIfPossible() }
        }

        /// The rows may not be laid out yet when a target arrives; try again once they are.
        override func layout() {
            super.layout()
            applyTargetIfPossible()
        }

        func applyTargetIfPossible() {
            guard !animating, let target = pendingTarget, let loop, let clipView = enclosingScrollView?.contentView,
                  clipView.documentView?.frame.height ?? 0 >= loop.contentHeight - 2 else { return }
            appliedTarget = target
            pendingTarget = nil
            let current = clipView.bounds.origin.y
            // Nearest of the three copies of the row, so the last row rolls on into the first.
            let destination = (0..<3).map { loop.offset(centring: target.index, copy: $0) }.min { abs($0 - current) < abs($1 - current) } ?? current
            if target.instant || abs(destination - current) < 0.5 {
                clipView.setBoundsOrigin(NSPoint(x: 0, y: loop.normalised(destination)))
                return
            }
            animating = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: destination))
            }, completionHandler: { [weak self, weak clipView] in
                guard let self, let clipView else { return }
                self.animating = false
                let y = loop.normalised(clipView.bounds.origin.y)
                if y != clipView.bounds.origin.y { clipView.setBoundsOrigin(NSPoint(x: 0, y: y)) }
                self.applyTargetIfPossible()
            })
        }

        deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    }
}

/// A column of short horizontal ticks, one per item, in place of a scrollbar. The active
/// item's tick is longer and solid; hovering stretches the tick under the pointer and lets
/// the stretch fall off over its neighbours; a click selects.
private struct TickRail: View {
    let count: Int
    let activeIndex: Int?
    let highlighted: Int?
    let hover: (Int?) -> Void
    let select: (Int) -> Void

    private static let pitch: CGFloat = 12
    private static let base: CGFloat = 10
    private static let active: CGFloat = 14
    private static let focus: CGFloat = 20
    private static let falloff: [CGFloat] = [1, 0.6, 0.35, 0.15]

    private func width(_ index: Int) -> CGFloat {
        let base = index == activeIndex ? Self.active : Self.base
        guard let highlighted else { return base }
        let factor = abs(index - highlighted) < Self.falloff.count ? Self.falloff[abs(index - highlighted)] : 0
        return (base + (Self.focus - base) * factor).rounded()
    }

    private func opacity(_ index: Int) -> Double {
        if index == activeIndex { return 1 }
        return index == highlighted ? 0.8 : 0.3
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(opacity(index)))
                    .frame(width: width(index), height: 2)
                    .frame(height: Self.pitch, alignment: .center)
                    .animation(.easeOut(duration: 0.2), value: highlighted)
            }
        }
        .frame(width: 28, alignment: .trailing)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hover(max(0, min(count - 1, Int(point.y / Self.pitch))))
            case .ended:
                hover(nil)
            }
        }
        .onTapGesture { if let highlighted { select(highlighted) } }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(activeIndex.map { "\($0 + 1) of \(count)" } ?? "")
    }
}

/// A drawn Mac keycap. Fn shows the globe; modifiers show their symbol and name like the real keys;
/// any other key shows what is printed on it.
struct SettingsKeycap: View {
    enum Key {
        case modifier(HeldModifier)
        case plain(String)

        /// One cap per key: the modifiers in Mac order, then the key itself. A side-specific
        /// modifier carries an L or R mark.
        static func keys(for trigger: Trigger) -> [Key] {
            switch trigger {
            case .modifiers(let chord):
                return chord.keys.map(Key.modifier)
            case .combo(let combo):
                return combo.modifiers.ordered.map { .modifier(HeldModifier($0, combo.side(of: $0))) }
                    + [.plain(KeyNames.name(for: combo.keyCode))]
            }
        }
    }

    let key: Key
    init(_ key: Key) { self.key = key }

    private var symbol: String {
        switch key {
        case .modifier(let held): return held.family == .fn ? "fn" : held.family.symbol
        case .plain: return ""
        }
    }

    private var label: String? {
        switch key {
        case .modifier(let held): return held.family == .fn ? nil : held.family.title.lowercased()
        case .plain: return nil
        }
    }

    /// "L" or "R" when the side of the modifier matters.
    private var sideMark: String? {
        if case .modifier(let held) = key, let side = held.side.title { return String(side.prefix(1)) }
        return nil
    }

    /// Plain keys print their name in the middle instead of corner markings.
    private var centred: String? {
        if case .plain(let name) = key { return name }
        return nil
    }

    var accessibilityLabel: String {
        switch key {
        case .modifier(let held): return "\(held.title) key"
        case .plain(let name): return "\(name) key"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
            .overlay {
                if let centred {
                    Text(centred)
                        .font(.system(size: centred.count > 2 ? 9 : 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(3)
                }
            }
            .overlay(alignment: .topLeading) {
                if let sideMark {
                    Text(sideMark)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 5).padding(.leading, 5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if centred == nil {
                    Text(symbol)
                        .font(.system(size: label == nil ? 11 : 13, weight: .semibold))
                        .padding(.top, 4).padding(.trailing, 5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if centred == nil {
                    Group {
                        if let label {
                            Text(label)
                                .font(.system(size: 8, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .allowsTightening(true)
                                .frame(maxWidth: 28, alignment: .leading)
                        }
                        else { Image(systemName: "globe").font(.system(size: 12, weight: .semibold)) }
                    }
                    .padding(.bottom, 5).padding(.leading, 5)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}
