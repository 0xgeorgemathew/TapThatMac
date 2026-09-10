import AppKit
import SwiftUI
import TapCore

final class RingState: ObservableObject {
    @Published var selected: Command?
    @Published var tapOnly = false
    @Published var automaticLock = false
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

    func openAndLock() {
        open(tapOnly: false, automaticLock: true)
        guard isOpen else { return }
        let token = opening
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.isOpen, self.opening == token else { return }
            self.state.selected = .lock
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isOpen, self.opening == token else { return }
            self.confirm(.lock)
        }
    }

    func open(tapOnly: Bool, automaticLock: Bool = false) {
        guard !isOpen else { return }
        opening += 1; state.automaticLock = automaticLock
        previousApp = NSWorkspace.shared.frontmostApplication
        state.selected = nil; state.tapOnly = tapOnly
        state.choose = { [weak self] command in self?.confirm(command) }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = min(340.0, min(frame.width, frame.height))
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
            if self.state.automaticLock {
                if event.keyCode == 53 { self.dismiss() }
                return nil
            }
            switch event.keyCode {
            case 53: self.dismiss()
            case 36, 76: if let selected = self.state.selected { self.confirm(selected) }
            case 126: self.state.selected = .playPause
            case 124: self.state.selected = .next
            case 125: self.state.selected = .lock
            case 123: self.state.selected = .previous
            case 48: self.advance()
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
    func advance() {
        let commands = Command.allCases
        let next = state.selected.flatMap { commands.firstIndex(of: $0) }.map { ($0 + 1) % commands.count } ?? 0
        state.selected = commands[next]
    }
    func confirm(_ command: Command) {
        guard isOpen else { return }
        dismiss(); onChoose?(command)
    }
    func dismiss(restoreFocus: Bool = true) {
        guard isOpen else { return }
        isOpen = false; opening += 1; state.automaticLock = false
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
        let view = NSVisualEffectView(); view.material = .hudWindow
        view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
private struct Sector: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Double(index) * 90 - 135 + 2
        let end = start + 86
        var path = Path()
        path.addArc(center: center, radius: rect.width / 2 - 7, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: rect.width * 0.215, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
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
                Color.black.opacity(0.2)
                ForEach(Array(Command.allCases.enumerated()), id: \.element) { index, command in
                    let shape = Sector(index: index)
                    Button { state.choose?(command) } label: {
                        ZStack {
                            shape.fill(state.selected == command ? accent.opacity(0.23) : Color.white.opacity(0.045))
                            shape.stroke(state.selected == command ? accent : .white.opacity(0.1), lineWidth: state.selected == command ? 2 : 0.5)
                            VStack(spacing: 8) {
                                Image(systemName: command.symbol).font(.system(size: 23, weight: .medium))
                                Text(command.rawValue).font(.system(size: 11, weight: .semibold))
                            }
                            .scaleEffect(state.selected == command ? 1.08 : 1)
                            .foregroundStyle(state.selected == command ? accent : .white)
                            .position(position(index, size: size))
                        }.contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.automaticLock)
                    .onHover { inside in if inside && !state.automaticLock { state.selected = command } }
                    .accessibilityLabel(command.rawValue)
                    .accessibilityAddTraits(state.selected == command ? [.isSelected] : [])
                }
                VStack(spacing: 7) {
                    Text(state.selected?.rawValue ?? "TapThatX").font(.system(size: 13, weight: .semibold))
                    Text(state.automaticLock ? "Locking…\nEsc to cancel" : (state.tapOnly ? "Tap to move\nDouble to choose" : "Arrows + Return\nEsc to dismiss"))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                }.foregroundStyle(.white).allowsHitTesting(false).frame(width: size * 0.4)
                Circle().stroke(.white.opacity(0.22), lineWidth: 1).padding(1).allowsHitTesting(false)
            }
            .clipShape(Circle())
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: state.selected)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.9)) { appeared = true } }
    }
    private func position(_ index: Int, size: Double) -> CGPoint {
        let angle = (Double(index) * 90 - 90) * Double.pi / 180
        return CGPoint(x: size / 2 + cos(angle) * size * 0.35, y: size / 2 + sin(angle) * size * 0.35)
    }
}
