import AppKit
import SwiftUI
import TapCore

final class RingState: ObservableObject {
    @Published var selected: Command?
    @Published var committing: Command?
    @Published var automaticAction = false
    var choose: ((Command) -> Void)?
}
private final class RingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class RadialPanelController: NSObject, NSWindowDelegate {
    let state = RingState()
    private var panel: RingPanel?
    private var previousApp: NSRunningApplication?
    private var monitors: [Any] = []
    private var opening = 0
    private(set) var isOpen = false
    var onDismiss: (() -> Void)?
    var onChoose: ((Command) -> Void)?

    func openAndPerform(_ command: Command) {
        guard !isOpen else { return }
        open(automaticAction: true)
        guard isOpen else { return }
        let token = opening
        // Let the opening frame appear before moving the highlight.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.isOpen, self.opening == token else { return }
            self.state.selected = command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                guard let self, self.isOpen, self.opening == token else { return }
                self.confirm(command)
            }
        }
    }

    func open(automaticAction: Bool = false) {
        guard !isOpen else { return }
        opening += 1; state.automaticAction = automaticAction
        previousApp = NSWorkspace.shared.frontmostApplication
        state.selected = automaticAction ? .previous : .playPause; state.committing = nil
        state.choose = { [weak self] command in self?.confirm(command) }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = min(460.0, min(frame.width, frame.height))
        let origin = NSPoint(x: frame.midX - size / 2, y: frame.midY - size / 2)
        let panel = RingPanel(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RingView(state: state))
        panel.delegate = self; self.panel = panel; isOpen = true
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
        return hypot(point.x - panel.frame.midX, point.y - panel.frame.midY) <= panel.frame.width / 2
    }
    func advance(by step: Int = 1) {
        guard isOpen, !state.automaticAction, state.committing == nil else { return }
        state.selected = Command.advancing(state.selected, by: step)
    }
    func confirm(_ command: Command) {
        guard isOpen, state.committing == nil else { return }
        state.selected = command
        let token = opening
        let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : .easeInOut(duration: 0.18)
        withAnimation(animation) { state.committing = command }
        // The visible press is part of the requested interaction. Cancellation,
        // focus loss or a reset invalidates the pending action through opening.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.isOpen, self.opening == token else { return }
            self.dismiss()
            self.onChoose?(command)
        }
    }

    func dismiss(restoreFocus: Bool = true) {
        guard isOpen else { return }
        isOpen = false; opening += 1; state.automaticAction = false; state.committing = nil
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        panel?.orderOut(nil); panel = nil; state.selected = nil
        if restoreFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: [])
        }
        previousApp = nil; onDismiss?()
    }
    func windowDidResignKey(_ notification: Notification) { dismiss(restoreFocus: false) }
}

private struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .popover
        view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
private struct Sector: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let sweep = 360.0 / Double(Command.allCases.count)
        let start = Double(index) * sweep - 90 - sweep / 2 + 1
        let end = start + sweep - 2
        var path = Path()
        path.addArc(center: center, radius: rect.width / 2 - 7, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: rect.width * 0.235, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}
private struct RingView: View {
    @ObservedObject var state: RingState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false
    private let accent = Color(red: 0.38, green: 0.83, blue: 0.72)
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            ZStack {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                else { Backdrop() }
                LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.025), .black.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .allowsHitTesting(false)
                ForEach(Array(Command.allCases.enumerated()), id: \.element) { index, command in
                    let shape = Sector(index: index)
                    Button { state.choose?(command) } label: {
                        ZStack {
                            shape.fill(LinearGradient(
                                colors: state.selected == command
                                    ? [.white.opacity(0.22), accent.opacity(0.12)]
                                    : [.white.opacity(0.055), .white.opacity(0.015)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            shape.stroke(LinearGradient(
                                colors: [.white.opacity(state.selected == command ? 0.8 : 0.16),
                                         accent.opacity(state.selected == command ? 0.45 : 0.03)],
                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                            VStack(spacing: 8) {
                                Image(systemName: command.symbol).font(.system(size: 23, weight: .medium))
                                Text(command.rawValue).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).frame(width: 82)
                            }
                            .scaleEffect(state.committing == command ? 0.88 : state.selected == command ? 1.08 : 1)
                            .foregroundStyle(state.selected == command ? accent : .white)
                            .position(position(index, size: size))
                        }.contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.automaticAction || state.committing != nil)
                    .onHover { inside in if inside && !state.automaticAction && state.committing == nil { state.selected = command } }
                    .accessibilityLabel(command.rawValue)
                    .accessibilityAddTraits(state.selected == command ? [.isSelected] : [])
                }
                .opacity(state.committing == nil ? 1 : 0.65)
                Sector(index: 0)
                    .stroke(accent.opacity(0.75), lineWidth: 1.5)
                    .rotationEffect(.degrees(Double(Command.allCases.firstIndex(of: state.selected ?? .playPause) ?? 0) * 360 / Double(Command.allCases.count)))
                    .allowsHitTesting(false)
                Circle()
                    .fill(.black.opacity(reduceTransparency ? 0.5 : 0.07))
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.7))
                    .frame(width: size * 0.44, height: size * 0.44)
                    .allowsHitTesting(false)
                VStack(spacing: 7) {
                    if state.automaticAction || state.committing != nil {
                        Image(systemName: state.committing?.symbol ?? state.selected?.symbol ?? "circle")
                            .font(.system(size: 28, weight: .light))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text(state.selected?.rawValue ?? "TapThatX").font(.system(size: 13, weight: .semibold))
                    Text(state.committing != nil ? "Selected" : state.automaticAction ? "Selecting…" : "Tap to move · Double to choose\nArrows · Return · Esc")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                }.foregroundStyle(.white).allowsHitTesting(false).frame(width: size * 0.4)
                Circle().stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.3)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .padding(1).allowsHitTesting(false)
                Circle().stroke(.white.opacity(0.08), lineWidth: 0.5).padding(4).allowsHitTesting(false)
            }
            .clipShape(Circle())
            .preferredColorScheme(.dark)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: state.selected)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.9)) { appeared = true } }
    }
    private func position(_ index: Int, size: Double) -> CGPoint {
        let angle = (Double(index) * (360 / Double(Command.allCases.count)) - 90) * Double.pi / 180
        return CGPoint(x: size / 2 + cos(angle) * size * 0.35, y: size / 2 + sin(angle) * size * 0.35)
    }
}
