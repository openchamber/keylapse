import Cocoa

/// The Correct to chooser: a small glass list of layouts. Takes keyboard focus without
/// activating Keylapse or losing the editor's selection.
final class DestinationPanel: NSPanel {
    private(set) var choices: [DestinationChoiceButton] = []
    var cancel: (() -> Void)?
    private var selectedIndex = 0

    /// A chooser listing these layouts; each row sends `action` to `target` with the layout's
    /// id as the button's identifier.
    static func make(choices: [(id: String, title: String)], target: AnyObject, action: Selector) -> DestinationPanel {
        let labelWidth = choices.map {
            ($0.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
        }.max() ?? 0
        let width = min(360, max(180, ceil(labelWidth) + 52))
        let titleHeight: CGFloat = 30
        let panel = DestinationPanel(contentRect: NSRect(x: 0, y: 0, width: width,
                                                         height: titleHeight + CGFloat(min(340, 14 + choices.count * 28))),
                                     styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Correct to"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // Only the red close button; the title sits to its right inside the glass.
        for button in [NSWindow.ButtonType.miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        let glass = GlassView()
        panel.contentView = glass
        let title = NSTextField(labelWithString: panel.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: 30, y: glass.bounds.height - titleHeight + 8, width: width - 60, height: 16)
        title.autoresizingMask = [.minYMargin]
        glass.addSubview(title)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: glass.bounds.height - titleHeight))
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        glass.addSubview(scroll)
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        for choice in choices {
            let button = DestinationChoiceButton(title: choice.title, target: target, action: action)
            button.isBordered = false
            button.focusRingType = .none
            button.setAccessibilityLabel(choice.title)
            button.identifier = NSUserInterfaceItemIdentifier(choice.id)
            button.widthAnchor.constraint(equalToConstant: width - 16).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            rows.addArrangedSubview(button)
            panel.choices.append(button)
        }
        scroll.documentView = rows
        rows.setFrameSize(rows.fittingSize)
        return panel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func selectFirstChoice() {
        selectChoice(at: 0)
    }

    private func selectChoice(at index: Int) {
        guard !choices.isEmpty else { return }
        selectedIndex = (index + choices.count) % choices.count
        for (offset, button) in choices.enumerated() {
            button.isSelectedChoice = offset == selectedIndex
        }
        let button = choices[selectedIndex]
        makeFirstResponder(button)
        button.scrollToVisible(button.bounds)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            switch event.keyCode {
            case 125: selectChoice(at: selectedIndex + 1); return
            case 126: selectChoice(at: selectedIndex - 1); return
            case 48: selectChoice(at: selectedIndex + (event.modifierFlags.contains(.shift) ? -1 : 1)); return
            case 36, 76:
                if choices.indices.contains(selectedIndex) { choices[selectedIndex].performClick(nil) }
                return
            case 53: cancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

final class DestinationChoiceButton: NSButton {
    var isSelectedChoice = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(isSelectedChoice ? "Selected" : "")
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedChoice || isHighlighted {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.2 : 0.13).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        if isSelectedChoice {
            Flower.drawSmallGlyph(centre: NSPoint(x: 13, y: bounds.midY))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: isSelectedChoice ? NSColor.white : NSColor.white.withAlphaComponent(0.62),
            .paragraphStyle: paragraph
        ])
        let height = text.size().height
        text.draw(in: NSRect(x: 28, y: (bounds.height - height) / 2, width: bounds.width - 36, height: height))
    }
}

/// A brief message by the text the user was trying to fix: the same glass as the chooser,
/// marked with the flower. It never takes focus, so the editor keeps its selection.
enum NoticePanel {
    static func show(_ message: String, near selection: NSRect?) {
        let width: CGFloat = 340
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let textWidth = width - 58
        let textHeight = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 400)).height ?? 18)
        let height = max(44, textHeight + 26)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let glass = GlassView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        panel.contentView = glass
        let flower = NSImageView(frame: NSRect(x: 14, y: height - 13 - Flower.smallSize, width: Flower.smallSize, height: Flower.smallSize))
        flower.image = Flower.smallImage
        flower.contentTintColor = .white
        flower.imageScaling = .scaleProportionallyUpOrDown
        glass.addSubview(flower)
        label.frame = NSRect(x: 42, y: (height - textHeight) / 2, width: textWidth, height: textHeight)
        glass.addSubview(label)
        panel.setAccessibilityLabel("Keylapse: \(message)")
        panel.place(near: selection)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { panel.close() }
    }
}

extension NSPanel {
    /// Just under the selected text, where the correction will land, so the eyes stay on it;
    /// above the text when there is no room below. Apps that do not report where their
    /// selection is get it at the pointer, and failing that in the middle.
    func place(near selection: NSRect?) {
        let gap: CGFloat = 6
        let size = frame.size
        func kept(_ origin: NSPoint, in area: NSRect) -> NSPoint {
            NSPoint(x: min(max(origin.x, area.minX), area.maxX - size.width), y: min(max(origin.y, area.minY), area.maxY - size.height))
        }
        if let text = selection,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: text.midX, y: text.midY)) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            var origin = NSPoint(x: text.minX, y: text.minY - gap - size.height)
            if origin.y < area.minY { origin.y = text.maxY + gap }
            setFrameOrigin(kept(origin, in: area))
            return
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            setFrameOrigin(kept(NSPoint(x: mouse.x - 20, y: mouse.y - size.height - 12), in: screen.visibleFrame))
            return
        }
        center()
    }
}
