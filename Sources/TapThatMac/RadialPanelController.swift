import AppKit
import SwiftUI
import TapCore

final class RingState: ObservableObject {
    @Published var selected: Command?
    @Published var committing: Command?
    @Published var automaticAction = false
    @Published var tapPending = false
    @Published var selectionAngle = 0.0
    @Published var isPresented = true
    var presentedSelectionAngle: Double?
    var choose: ((Command) -> Void)?

    func select(_ command: Command, direction: Int = 0) {
        // Hover and confirmation can repeat the same target mid-flight. Keep
        // its existing endpoint and spring, including the chosen winding.
        guard selected != command else { return }
        guard let index = Command.allCases.firstIndex(of: command) else { return }
        // Logical identity changes immediately; the endpoint is resolved from
        // the visible angle, including when the user reverses mid-flight.
        let origin = presentedSelectionAngle ?? selectionAngle
        selectionAngle = RingSelection.targetAngle(current: origin, index: index,
                                                    count: Command.allCases.count, direction: direction)
        selected = command
    }

    func resetSelection(_ command: Command) {
        tapPending = false
        presentedSelectionAngle = nil
        selected = command
        selectionAngle = Double(Command.allCases.firstIndex(of: command) ?? 0) * 360 / Double(Command.allCases.count)
    }
}
private final class RingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class RadialPanelController: NSObject, NSWindowDelegate {
    private(set) var state = RingState()
    private var panel: RingPanel?
    private var retiringPanel: RingPanel?
    private var previousApp: NSRunningApplication?
    private var monitors: [Any] = []
    private var opening = 0
    private let playSelectionSound: () -> Void
    private(set) var isOpen = false
    private static let shadowMargin: CGFloat = 48
    private var ringDiameter: CGFloat = 440
    var onDismiss: (() -> Void)?
    var onChoose: ((Command) -> Void)?
    private var presentationSelection: ((Command) -> Void)?

    init(playSelectionSound: (() -> Void)? = nil) {
        if let playSelectionSound {
            self.playSelectionSound = playSelectionSound
        } else {
            // Load once before interaction, then let AppKit play asynchronously.
            // Missing/unavailable audio must never prevent a selection.
            let sound = NSSound(named: NSSound.Name("Tink"))
            sound?.volume = 0.3
            self.playSelectionSound = {
                // A fast reopen can confirm before the previous chime ends.
                _ = sound?.stop()
                _ = sound?.play()
            }
        }
        super.init()
    }

    func openAndPerform(_ command: Command) {
        guard !isOpen else { return }
        open(automaticAction: true)
        guard isOpen else { return }
        let token = opening
        // Let the opening frame appear before moving the highlight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.isOpen, self.opening == token else { return }
            self.state.select(command)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                guard let self, self.isOpen, self.opening == token else { return }
                self.confirm(command)
            }
        }
    }

    func open(automaticAction: Bool = false, onChoose selection: ((Command) -> Void)? = nil) {
        guard !isOpen else { return }
        retiringPanel?.orderOut(nil); retiringPanel = nil
        opening += 1; state.automaticAction = automaticAction
        state.isPresented = true
        previousApp = NSWorkspace.shared.frontmostApplication
        state.resetSelection(automaticAction ? .previous : .playPause); state.committing = nil
        state.choose = { [weak self] command in self?.confirm(command) }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        // The panel is larger than the ring so the disc can cast its own soft
        // shadow; only the circle itself takes input.
        let ring = min(440.0, min(frame.width, frame.height) - 2 * Self.shadowMargin)
        let size = ring + 2 * Self.shadowMargin
        ringDiameter = ring
        let origin = NSPoint(x: frame.midX - size / 2, y: frame.midY - size / 2)
        let panel = RingPanel(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RingView(state: state, diameter: ring))
        panel.delegate = self; self.panel = panel; isOpen = true
        presentationSelection = selection ?? onChoose
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            guard let self, self.isOpen else { return event }
            if event.type != .keyDown {
                if event.window !== self.panel || !self.insideCircle(NSEvent.mouseLocation) { self.dismiss(restoreFocus: event.window === self.panel) }
                return event
            }
            if self.state.automaticAction || self.state.committing != nil {
                if event.keyCode == 53 { self.dismiss() }
                return nil
            }
            switch event.keyCode {
            case 53: self.dismiss()
            case 36, 76: if let selected = self.state.selected { self.confirm(selected) }
            case 124, 125: self.advance()
            case 123, 126: self.advance(by: -1)
            case 48: self.advance(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            default: return event
            }
            return nil
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.dismiss(restoreFocus: false)
        }) { monitors.append(monitor) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func insideCircle(_ point: NSPoint) -> Bool {
        guard let panel else { return false }
        return hypot(point.x - panel.frame.midX, point.y - panel.frame.midY) <= ringDiameter / 2
    }
    func advance(by step: Int = 1) {
        guard isOpen, !state.automaticAction, state.committing == nil else { return }
        state.select(Command.advancing(state.selected, by: step), direction: step)
    }
    func confirm(_ command: Command) {
        guard isOpen, state.committing == nil else { return }
        state.select(command)
        let token = opening
        // Capture this presentation's dispatch context before dismissal clears it.
        let selection = presentationSelection
        // Views own their local feedback animations; keep confirmation out of
        // the transaction that drives the moving selection surface.
        state.committing = command
        playSelectionSound()
        // The visible press is part of the requested interaction. Cancellation,
        // focus loss or a reset invalidates the pending action through opening.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.isOpen, self.opening == token else { return }
            self.dismiss()
            selection?(command)
        }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard isOpen else { return }
        // Invalidate execution before the visual exit begins. The retiring
        // window cannot receive input or interfere with a newly opened ring.
        isOpen = false; opening += 1
        presentationSelection = nil
        state.choose = nil
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        let retiring = panel
        panel = nil
        retiringPanel = retiring
        retiring?.delegate = nil
        retiring?.ignoresMouseEvents = true
        state.isPresented = false
        state = RingState()
        let exitToken = opening
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : RingMotion.exitDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, retiring] in
            retiring?.orderOut(nil)
            guard let self, self.opening == exitToken else { return }
            self.retiringPanel = nil
        }
        if restoreFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil; onDismiss?()
    }
    func windowDidResignKey(_ notification: Notification) { dismiss(restoreFocus: false) }
}

/// The outer animated shell. It owns the opening spring and scales the disc
/// as one unit; the items inside settle in a beat later.
private struct RingView: View {
    @ObservedObject var state: RingState
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        RingContent(state: state, size: diameter, reduceMotion: reduceMotion)
            .scaleEffect(reduceMotion ? 1 : !appeared ? 0.92 : state.isPresented ? 1 : 0.97)
            .opacity(appeared && state.isPresented ? 1 : 0)
            .animation(reduceMotion ? nil : RingMotion.opening, value: appeared)
            .animation(reduceMotion ? nil : RingMotion.exit, value: state.isPresented)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { appeared = true }
    }
}
