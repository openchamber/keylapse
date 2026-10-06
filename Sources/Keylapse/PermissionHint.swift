import Cocoa
import SwiftUI

/// A small glass tag under the System Settings window while Keylapse waits for a permission:
/// the same replica of the row to find there, with its switch flipping on, and a thin line up
/// towards the window. It follows the window, hides while System Settings is not on screen,
/// and goes away the moment the permission is granted. Never takes focus.
final class PermissionHint {
    private var panel: NSPanel?
    private var timer: Timer?
    private let model: SettingsModel
    /// The Keylapse window, which steps aside when System Settings opens over it.
    private let window: () -> NSWindow?
    private var steppedAside = false
    /// Where the Keylapse window stood before it stepped aside (its top-left corner), and where
    /// it was put; it goes back once System Settings is gone, unless the user has moved it since.
    private var home: NSPoint?
    private var aside: NSPoint?
    /// Re-reads the real state, so the checkmark lands the moment the user flips the switch
    /// instead of at the next two-second refresh.
    private let refresh: () -> Void
    private var ticks = 0
    /// The tick the current wait began on, and whether System Settings has been seen during it.
    private var startTick = 0
    private var seenSettings = false
    /// Where the connector's dot sits across the tag; moves when the tag points at a control.
    private let pointer = HintPointer()
    /// The control in System Settings the user has to change, once found (the Fn step only:
    /// reading another app's window needs Accessibility, which the first step is still asking for).
    private var target: AXUIElement?
    /// Whether System Settings was already open when the wait began; if Keylapse caused it to
    /// open, Keylapse also closes it once the step is done.
    private(set) var settingsWasOpen = false
    private static let size = NSSize(width: 320, height: 112)
    /// Clear room around the tag inside its panel, on the sides and below, for the glow: a glow
    /// cut off by the panel's edge shows as a faint rectangle.
    static let glowMargin: CGFloat = 40
    private static let panelSize = NSSize(width: size.width + 2 * glowMargin, height: size.height + glowMargin)
    /// How far the tag reaches up into the System Settings window: the connector and about half the pill.
    private static let overlap: CGFloat = 62
    private static let gap: CGFloat = 10
    private static let settingsBundleID = "com.apple.systempreferences"

    init(model: SettingsModel, window: @escaping () -> NSWindow?, refresh: @escaping () -> Void) {
        self.model = model
        self.window = window
        self.refresh = refresh
    }

    private static var settingsApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first
    }

    /// The step is done: System Settings goes away if it was opened for it, and Keylapse comes
    /// back to the front with its new checkmark.
    func finish(bringingForward window: NSWindow?) {
        if !settingsWasOpen { Self.settingsApp?.terminate() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show() {
        // A wait that follows another one inherits its answer: the window is there because of us.
        if timer == nil { settingsWasOpen = Self.settingsApp != nil }
        steppedAside = false
        joinedDialog = false
        startTick = ticks
        seenSettings = false
        if panel == nil { panel = Self.makePanel(model: model, pointer: pointer) }
        target = nil
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.follow() }
        follow()
    }

    /// The tag as a PNG, for looking at it without a screen (glass renders as its dark tint).
    func snapshot() -> Data? {
        guard let view = panel?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        returnHome()
    }

    private var joinedDialog = false

    private func joinDialog(_ dialog: NSRect) {
        guard !joinedDialog, let window = window(), window.isVisible,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(dialog) }), window.screen != screen else { return }
        joinedDialog = true
        let area = screen.visibleFrame
        var frame = window.frame
        // Beside the dialog, on the side with more room, tops level.
        let roomLeft = dialog.minX - area.minX, roomRight = area.maxX - dialog.maxX
        frame.origin.x = roomLeft >= roomRight ? dialog.minX - 16 - frame.width : dialog.maxX + 16
        frame.origin.x = min(max(frame.origin.x, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(dialog.maxY - frame.height, area.minY), area.maxY - frame.height)
        if home == nil { home = NSPoint(x: window.frame.minX, y: window.frame.maxY) }
        aside = NSPoint(x: frame.minX, y: frame.maxY)
        window.setFrame(frame, display: true, animate: true)
    }

    /// The "would like to control this computer" dialog, which belongs to a system process.
    private static func accessDialogFrame() -> NSRect? {
        guard let main = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in list where (window["kCGWindowOwnerName"] as? String) == "universalAccessAuthWarn" {
            guard let bounds = window["kCGWindowBounds"] as? [String: CGFloat], let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"], w > 100, h > 60 else { continue }
            return NSRect(x: x, y: main.frame.height - y - h, width: w, height: h)
        }
        return nil
    }

    private func returnHome() {
        defer { home = nil; aside = nil }
        guard let home, let aside, let window = window(), window.isVisible else { return }
        var frame = window.frame
        // Only from where Keylapse itself put it; a window the user has dragged stays put.
        guard abs(frame.minX - aside.x) < 1, abs(frame.maxY - aside.y) < 1 else { return }
        frame.origin = NSPoint(x: home.x, y: home.y - frame.height)
        window.setFrame(frame, display: true, animate: true)
    }

    /// Sits under the System Settings window, right-aligned to it like a callout.
    private func follow() {
        ticks += 1
        if ticks % 4 == 0 { refresh() }
        // The refresh may have found the step done and hidden the hint; do not bring it back.
        guard timer != nil else { return }
        guard let panel, let settings = Self.systemSettingsFrame() else {
            self.panel?.orderOut(nil)
            // macOS shows its Accessibility dialog on the main display, wherever the Keylapse
            // window is. The window goes over to it, so the dialog is not missed on another screen.
            if let dialog = Self.accessDialogFrame() { joinDialog(dialog); return }
            // System Settings was closed without finishing the step (closing its window quits
            // it): the wait is over, and the row offers its buttons again.
            if seenSettings, Self.settingsApp == nil { model.stopWaiting(); return }
            // Merely out of sight: back in place, ready to step aside again.
            if home != nil { returnHome(); steppedAside = false }
            return
        }
        seenSettings = true
        // Behind another app's window System Settings is still "on screen", but the tag, which
        // floats above everything, would then hang over whatever the user switched to. It shows
        // only while System Settings is the app in front, and comes back with it.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsBundleID else {
            panel.orderOut(nil)
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        stepAside(from: settings, on: screen)
        // Straddles the window's bottom edge near its right side, where the pane is empty and the
        // switches are: half over the window, so it cannot be taken for part of the desktop.
        var origin = NSPoint(x: settings.maxX - Self.size.width - 28, y: settings.minY + Self.overlap - Self.size.height)
        var dotX = Self.size.width / 2
        // On the Fn step the tag hangs from the very menu to change, its dot on the menu's lower edge.
        let menu = model.awaiting == .fnKey ? fnMenuFrame() : nil
        // The Keyboard pane takes a moment to load. The tag waits for its menu rather than
        // appearing at the bottom edge and jumping; after 2.5 s it settles for the edge.
        if model.awaiting == .fnKey, menu == nil, AXIsProcessTrusted(), ticks - startTick < 16 {
            panel.orderOut(nil)
            return
        }
        if let menu, settings.insetBy(dx: -1, dy: -1).contains(menu) {
            origin = NSPoint(x: menu.midX - Self.size.width / 2, y: menu.minY + 3 - Self.size.height)
            if let area = screen?.visibleFrame {
                origin.y = max(origin.y, area.minY)
                origin.x = min(max(origin.x, area.minX), area.maxX - Self.size.width)
            }
            dotX = min(max(menu.midX - origin.x, 12), Self.size.width - 12)
        } else if let area = screen?.visibleFrame {
            origin.y = max(origin.y, area.minY)
            origin.x = min(max(origin.x, area.minX), area.maxX - Self.size.width)
        }
        if pointer.dotX != dotX { pointer.dotX = dotX }
        // The menu opens right where the tag hangs. Once it is open the user has found it, and
        // the tag gets out of the way of its items; it comes back if the menu closes unchanged.
        if Self.menuIsOpen(over: settings) { panel.orderOut(nil); return }
        origin.x -= Self.glowMargin
        origin.y -= Self.glowMargin
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// System Settings opens wherever macOS likes, often right over the Keylapse window, hiding
    /// the row the user was just looking at, or on another display altogether. Once per wait
    /// Keylapse puts the two side by side; after that the user is free to put them anywhere.
    private func stepAside(from settings: NSRect, on screen: NSScreen?) {
        guard !steppedAside, let window = window(), window.isVisible, let area = screen?.visibleFrame else { return }
        steppedAside = true
        var frame = window.frame
        let spacing: CGFloat = 16
        // macOS may open System Settings on another display. The two windows belong side by
        // side: with Accessibility Keylapse brings System Settings over to its own display;
        // before that it cannot move another app's window, so it goes over there itself.
        if let home = window.screen, let screen, home != screen {
            if AXIsProcessTrusted(), Self.moveSettings(beside: frame, size: settings.size, in: home.visibleFrame) { return }
        } else if !frame.intersects(settings) {
            return
        }
        let roomLeft = settings.minX - area.minX
        let roomRight = area.maxX - settings.maxX
        if roomLeft >= roomRight {
            frame.origin.x = max(area.minX, settings.minX - spacing - frame.width)
        } else {
            frame.origin.x = min(area.maxX - frame.width, settings.maxX + spacing)
        }
        if !area.intersects(frame) { frame.origin.y = settings.maxY - frame.height }
        frame.origin.y = min(max(frame.origin.y, area.minY), area.maxY - frame.height)
        // The place to go back to is where the user had it, even after a stop by the dialog.
        if home == nil { home = NSPoint(x: window.frame.minX, y: window.frame.maxY) }
        aside = NSPoint(x: frame.minX, y: frame.maxY)
        window.setFrame(frame, display: true, animate: true)
    }

    /// Puts the System Settings window next to the Keylapse window, on the side with more room.
    private static func moveSettings(beside keylapse: NSRect, size: NSSize, in area: NSRect) -> Bool {
        guard let pid = settingsApp?.processIdentifier, let main = NSScreen.screens.first else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let settingsWindow = (value as? [AXUIElement])?.first else { return false }
        let spacing: CGFloat = 16
        var x = keylapse.maxX + spacing
        if area.maxX - keylapse.maxX < keylapse.minX - area.minX { x = keylapse.minX - spacing - size.width }
        x = min(max(x, area.minX), area.maxX - size.width)
        let top = min(max(keylapse.maxY, area.minY + size.height), area.maxY)
        var point = CGPoint(x: x, y: main.frame.height - top)
        guard let position = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(settingsWindow, kAXPositionAttribute as CFString, position) == .success
    }

    /// Whether a pop-up menu is open over the System Settings window. The menu is a window of its
    /// own at the menu level, and a settings pane may draw it from a helper process, so it is
    /// recognised by its level and place, not by its owner.
    private static func menuIsOpen(over settings: NSRect) -> Bool {
        guard let main = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains { window in
            guard (window["kCGWindowLayer"] as? Int) == menuLevel, (window["kCGWindowOwnerPID"] as? Int32) != own,
                  let bounds = window["kCGWindowBounds"] as? [String: CGFloat], let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"] else { return false }
            return NSRect(x: x, y: main.frame.height - y - h, width: w, height: h).intersects(settings)
        }
    }

    /// Where the System Settings window is, in Cocoa coordinates; window bounds need no permission.
    private static func systemSettingsFrame() -> NSRect? {
        // Found by its process, not by its name: the name is translated with the system language.
        guard let main = NSScreen.screens.first, let pid = settingsApp?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in list where (window["kCGWindowOwnerPID"] as? pid_t) == pid && (window["kCGWindowLayer"] as? Int) == 0 {
            guard let bounds = window["kCGWindowBounds"] as? [String: CGFloat], let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"], w > 300, h > 200 else { continue }
            return NSRect(x: x, y: main.frame.height - y - h, width: w, height: h)
        }
        return nil
    }

    /// The Press 🌐 key to menu in the Keyboard pane, in Cocoa coordinates. Found once by walking
    /// the System Settings window, then only its position is re-read, since the pane scrolls.
    private func fnMenuFrame() -> NSRect? {
        if let target, let frame = Self.frame(of: target) { return frame }
        target = nil
        // The walk is the slow part: not on every tick.
        guard ticks % 6 == 0 || ticks - startTick < 16, AXIsProcessTrusted(), let pid = Self.settingsApp?.processIdentifier else { return nil }
        target = Self.fnMenu(in: pid)
        return target.flatMap(Self.frame(of:))
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func frame(of element: AXUIElement) -> NSRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let main = NSScreen.screens.first else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return NSRect(x: origin.x, y: main.frame.height - origin.y - extent.height, width: extent.width, height: extent.height)
    }

    /// Every pop-up menu in the System Settings window with its value, and every label there.
    /// The menus carry no name of their own; the label is a separate text on the same line.
    static func settingsControls(in pid: pid_t) -> (menus: [(element: AXUIElement, value: String)], labels: [(text: String, frame: NSRect)]) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var menus: [(AXUIElement, String)] = []
        var labels: [(String, NSRect)] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 24, visited < 1500 else { return }
            visited += 1
            let role = string(element, kAXRoleAttribute)
            if role == (kAXPopUpButtonRole as String) {
                menus.append((element, string(element, kAXValueAttribute) ?? ""))
                return
            }
            if role == (kAXStaticTextRole as String) {
                if let text = string(element, kAXValueAttribute), let frame = frame(of: element) { labels.append((text, frame)) }
                return
            }
            for child in children(element) { walk(child, depth: depth + 1) }
        }
        walk(app, depth: 0)
        return (menus, labels)
    }

    /// The menu on the same line as the label that names the Fn key.
    static func fnMenu(in pid: pid_t) -> AXUIElement? {
        let controls = settingsControls(in: pid)
        guard let label = controls.labels.first(where: { isFnLabel($0.text) }) else { return nil }
        return controls.menus.first { menu in
            frame(of: menu.element).map { abs($0.midY - label.frame.midY) < 14 } ?? false
        }?.element
    }

    /// The row is labelled with the globe on newer keyboards and with fn on older ones. The globe
    /// comes with a text-style selector attached, so it is looked up as a scalar, not a character.
    static func isFnLabel(_ text: String) -> Bool {
        text.unicodeScalars.contains("\u{1F310}") || text.range(of: #"(?i)\bfn\b"#, options: .regularExpression) != nil
    }

    private static func makePanel(model: SettingsModel, pointer: HintPointer) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        let hosting = NSHostingView(rootView: PermissionHintView(model: model, pointer: pointer))
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hosting
        return panel
    }
}

final class HintPointer: ObservableObject {
    @Published var dotX: CGFloat = 160
}

private struct PermissionHintView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var pointer: HintPointer

    var body: some View {
        VStack(spacing: 0) {
            // A connector reaching up into the System Settings window: a dot where it points, a
            // line down to the tag. All in the accent colour.
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 9)
                    .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: pointer.dotX - 4.5)
            SettingsRowReplica(kind: model.awaiting == .fnKey ? .fnKey : .appSwitch, on: model.hintSwitchOn,
                               action: { model.awaiting.map { model.grant($0) } }, scale: 1.5)
                .padding(10)
                .background {
                    ZStack {
                        GlassBackground()
                        Color.black.opacity(0.55)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .shadow(color: Color.accentColor.opacity(model.hintSwitchOn ? 0.9 : 0.35), radius: model.hintSwitchOn ? 14 : 6)
                .scaleEffect(model.hintSwitchOn ? 1.04 : 1, anchor: .top)
                .animation(.easeInOut(duration: 0.6), value: model.hintSwitchOn)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, PermissionHint.glowMargin)
        .padding(.bottom, PermissionHint.glowMargin)
        .preferredColorScheme(.dark)
    }
}

/// The same frosted glass as the windows, usable as a SwiftUI background.
private struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> GlassView { GlassView() }
    func updateNSView(_ view: GlassView, context: Context) {}
}
