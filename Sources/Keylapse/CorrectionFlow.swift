import Cocoa
import KeylapseCore

/// One correction, from the shortcut to the replaced text: read the selection, work out which
/// layout typed each word, ask where to when there is more than one answer, replace it.
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

    /// One way to correct the selection: where each run goes, by the layout it was typed on.
    private struct Plan {
        let id: String
        let title: String
        let destination: (KeyboardSource) -> KeyboardSource
    }

    /// The selection is known to hold this text. Which layout typed each word comes from its
    /// letters, and from the active layout only when the letters fit several; if that cannot be
    /// known the user is told now, before any chooser. Text typed on one layout goes to one of
    /// the others; text typed on two layouts swaps them, or goes whole to a third. With one
    /// possible answer the text is corrected straight away, otherwise the chooser asks.
    private func correct(_ text: String, in app: NSRunningApplication) {
        do {
            let supported = try inputs.supportedSources()
            let runs = try inputs.typedRuns(of: text, among: supported)
            var sources: [KeyboardSource] = []
            for run in runs where !sources.contains(where: { $0.id == run.source.id }) { sources.append(run.source) }
            guard sources.count <= 2 else { throw AppError.message("Select text typed on no more than two layouts.") }
            var plans: [Plan] = []
            if sources.count == 2 {
                let (first, second) = (sources[0], sources[1])
                plans.append(Plan(id: "swap", title: "\(first.name(among: supported)) ↔ \(second.name(among: supported))",
                                  destination: { $0.id == first.id ? second : first }))
            }
            for other in supported where !sources.contains(where: { $0.id == other.id }) {
                plans.append(Plan(id: other.id, title: other.name(among: supported), destination: { _ in other }))
            }
            if plans.count == 1 {
                try replace(runs, by: plans[0])
                return
            }
            let activeID = inputs.currentID
            let selectionUnchanged = corrector.selectionCheck(for: app.processIdentifier)
            presentDestinations(plans.map { (id: $0.id, title: $0.title) }) { [weak self] id in
                guard let self else { return }
                guard let plan = plans.first(where: { $0.id == id }) else {
                    self.onSilentStop?(AppError.message("Correction cancelled."))
                    return
                }
                self.phase = .returning
                self.resume(deadline: ProcessInfo.processInfo.systemUptime + 0.5, app: app) {
                    guard self.inputs.currentID == activeID, selectionUnchanged() else {
                        throw AppError.message("The app, layout or selection changed; correction was cancelled.")
                    }
                    try self.replace(runs, by: plan)
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

    /// Corrects each run from the layout it was typed on to the one the plan sends it to, and
    /// leaves the last run's destination active so typing can go on, unless the user changed
    /// layout meanwhile.
    private func replace(_ runs: [InputSources.TypedRun], by plan: Plan) throws {
        let available = try inputs.supportedSources()
        var converted = ""
        var target: KeyboardSource?
        for run in runs {
            let destination = plan.destination(run.source)
            guard available.contains(where: { $0.id == run.source.id }), available.contains(where: { $0.id == destination.id }) else {
                throw AppError.message("The available layouts changed. Try correcting the text again.")
            }
            converted += try inputs.layoutPair(run.source, destination).convert(run.text)
            target = destination
        }
        guard let target else { throw ConversionError.noLetters }
        let originalID = inputs.currentID
        corrector.didReplace = { [weak self] in
            guard let self, self.inputs.currentID == originalID, originalID != target.id else { return }
            do { try self.inputs.select(target.id) } catch { self.onFinished?(.failure(error)) }
        }
        phase = .replacing
        corrector.replace(runs.map(\.text).joined(), with: converted)
    }

    private func fail(_ error: Error) {
        phase = .idle
        onFinished?(.failure(error))
    }

    // MARK: Chooser

    func presentDestinations(_ choices: [(id: String, title: String)], completion: @escaping (String?) -> Void) {
        let panel = DestinationPanel.make(choices: choices, target: self, action: #selector(chooseDestination))
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
