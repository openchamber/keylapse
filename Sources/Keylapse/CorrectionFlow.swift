import Cocoa
import KeylapseCore

/// One correction, from the shortcut to the replaced text: read the selection, work out which
/// layout typed it, ask where to when there is more than one answer, replace it.
///
/// Nothing selected is a silent no-op, checked before the chooser and before any layout error.
final class CorrectionFlow: NSObject, NSWindowDelegate {
    private enum Phase {
        case idle
        /// A quiet copy is finding out what is selected.
        case reading
        /// The Correct to chooser is on screen.
        case choosing(DestinationPanel, (String?) -> Void)
        /// The chooser has closed and the editor is coming back to the front.
        case returning
        case replacing
    }

    let corrector = SelectionCorrector()
    private let inputs: InputSources
    private var phase = Phase.idle
    private var clickAwayMonitors: [Any] = []

    var onFinished: ((Result<Void, Error>) -> Void)?
    /// The flow ended without doing or saying anything (nothing selected, chooser dismissed).
    /// Only diagnostics listen.
    var onSilentStop: ((Error) -> Void)?
    /// The chooser has given the keyboard up.
    var onChooserClosed: (() -> Void)?

    static let nothingSelected = AppError.message("Select the text you want to fix first.")

    init(inputs: InputSources) {
        self.inputs = inputs
        super.init()
        corrector.completion = { [weak self] result in
            self?.phase = .idle
            self?.onFinished?(result)
        }
    }

    var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    var chooser: DestinationPanel? {
        if case .choosing(let panel, _) = phase { return panel }
        return nil
    }

    func start() {
        guard isIdle, let front = NSWorkspace.shared.frontmostApplication else { return }
        // The text is read before anything is asked or changed. An app that hands it over is
        // read directly; any other is asked by a quiet copy, which also tells whether anything
        // is selected at all.
        switch corrector.selection(in: front.processIdentifier) {
        case .none:
            onSilentStop?(Self.nothingSelected)
        case .text(let text):
            correct(text, in: front)
        case .unknown:
            phase = .reading
            corrector.probeSelection { [weak self] text in
                guard let self else { return }
                self.phase = .idle
                guard let text, NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else {
                    self.onSilentStop?(Self.nothingSelected)
                    return
                }
                self.correct(text, in: front)
            }
        }
    }

    /// The selection is known to hold this text. Which layout typed it comes from its letters,
    /// and from the active layout only when the letters fit several; if that cannot be known
    /// the user is told now, before any chooser. With one possible destination the text is
    /// corrected straight away, otherwise the chooser asks where to.
    private func correct(_ text: String, in app: NSRunningApplication) {
        do {
            let supported = try inputs.supportedSources()
            let source = try inputs.typedSource(of: text, among: supported)
            let destinations = supported.filter { $0.id != source.id }
            if destinations.count == 1 {
                try replace(text, from: source, to: destinations[0])
                return
            }
            let activeID = inputs.currentID
            let selectionUnchanged = corrector.selectionCheck(for: app.processIdentifier)
            presentDestinations(destinations) { [weak self] id in
                guard let self else { return }
                guard let target = supported.first(where: { $0.id == id }) else {
                    self.onSilentStop?(AppError.message("Correction cancelled."))
                    return
                }
                self.phase = .returning
                self.resume(deadline: ProcessInfo.processInfo.systemUptime + 0.5, app: app) {
                    guard self.inputs.currentID == activeID, selectionUnchanged() else {
                        throw AppError.message("The app, layout or selection changed; correction was cancelled.")
                    }
                    try self.replace(text, from: source, to: target)
                }
            }
        } catch { fail(error) }
    }

    /// Waits for the editor to be in front again after the chooser, then goes on.
    private func resume(deadline: TimeInterval, app: NSRunningApplication, then: @escaping () throws -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            guard let self else { return }
            if !app.isActive && ProcessInfo.processInfo.systemUptime < deadline {
                self.resume(deadline: deadline, app: app, then: then)
                return
            }
            self.phase = .idle
            do {
                guard app.isActive else { throw AppError.message("The app, layout or selection changed; correction was cancelled.") }
                try then()
            } catch { self.fail(error) }
        }
    }

    /// Corrects the selection from the layout it was typed on to the one it was meant for, and
    /// leaves the meant one active so typing can go on, unless the user changed layout meanwhile.
    private func replace(_ text: String, from source: KeyboardSource, to target: KeyboardSource) throws {
        let available = try inputs.supportedSources()
        guard available.contains(where: { $0.id == source.id }), available.contains(where: { $0.id == target.id }) else {
            throw AppError.message("The available layouts changed. Try correcting the text again.")
        }
        let pair = try inputs.layoutPair(source, target)
        let originalID = inputs.currentID
        corrector.didReplace = { [weak self] in
            guard let self, self.inputs.currentID == originalID, originalID != target.id else { return }
            do { try self.inputs.select(target.id) } catch { self.onFinished?(.failure(error)) }
        }
        phase = .replacing
        corrector.correct(text, using: pair)
    }

    private func fail(_ error: Error) {
        phase = .idle
        onFinished?(.failure(error))
    }

    // MARK: Chooser

    func presentDestinations(_ sources: [KeyboardSource], completion: @escaping (String?) -> Void) {
        let panel = DestinationPanel.make(choices: sources.map { (id: $0.id, title: $0.displayName) },
                                          target: self, action: #selector(chooseDestination))
        panel.delegate = self
        panel.cancel = { [weak self] in self?.finishChoosing(nil) }
        phase = .choosing(panel, completion)
        panel.place(near: NSWorkspace.shared.frontmostApplication.flatMap { corrector.selectionRect(for: $0.processIdentifier) })
        panel.makeKeyAndOrderFront(nil)
        panel.selectFirstChoice()
        // A click anywhere else puts the chooser away, like any menu: in another app (global
        // monitor) or in one of Keylapse's own windows (local monitor). The click itself goes on
        // to whatever was clicked.
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        clickAwayMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in self?.finishChoosing(nil) },
            NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
                if let self, event.window !== self.chooser { self.finishChoosing(nil) }
                return event
            },
        ].compactMap { $0 }
    }

    func cancelChooser() { finishChoosing(nil) }

    @objc private func chooseDestination(_ sender: NSButton) { finishChoosing(sender.identifier?.rawValue) }

    private func finishChoosing(_ id: String?, closing: Bool = true) {
        guard case .choosing(let panel, let completion) = phase else { return }
        phase = .idle
        clickAwayMonitors.forEach(NSEvent.removeMonitor)
        clickAwayMonitors = []
        if closing { panel.close() }
        onChooserClosed?()
        completion(id)
    }

    /// The chooser's red button.
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSPanel === chooser { finishChoosing(nil, closing: false) }
    }
}
