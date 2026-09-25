import AppKit
import SwiftUI
import TapCore

struct MotionGraphView: NSViewRepresentable {
    let model: AppModel
    var scale: MotionGraphScale = .detail
    var duration: Double = 8
    var held = false
    func makeNSView(context: Context) -> MotionGraphNSView { MotionGraphNSView(model: model) }
    func updateNSView(_ view: MotionGraphNSView, context: Context) {
        view.configure(scale: scale, duration: duration, held: held)
    }
}

struct MotionGraphSnapshot {
    let time: Double
    let points: [MotionTrace.Point]
    let minimum: Double

    func visiblePoints(duration: Double) -> [MotionTrace.Point] {
        points.filter { $0.time <= time && time - $0.time <= duration }
    }
}

/// One drawing surface, driven by the existing timer. No per-sample SwiftUI state.
final class MotionGraphNSView: NSView {
    private weak var model: AppModel?
    private var draftThreshold: Double?
    private var backdrop: NSImage?
    private var scale: MotionGraphScale = .detail
    private var duration: Double = 8
    private(set) var heldSnapshot: MotionGraphSnapshot?
    private var hoverX: CGFloat?
    private var tracking: NSTrackingArea?
    private let reactor = NSColor(calibratedRed: 0.404, green: 0.780, blue: 0.922, alpha: 1)
    private let gold = NSColor(calibratedRed: 0.851, green: 0.639, blue: 0.255, alpha: 1)
    private let axisText = NSColor.white.withAlphaComponent(0.65)
    private var plot: NSRect { NSRect(x: 54, y: 36, width: max(1, bounds.width - 74), height: max(1, bounds.height - 110)) }
    override var acceptsFirstResponder: Bool { true }

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Minimum tap strength")
        setAccessibilityHelp("Drag the gold line or use arrow keys. Higher values require stronger taps.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(scale: MotionGraphScale, duration: Double, held: Bool) {
        if self.scale != scale { backdrop = nil; draftThreshold = nil }
        self.scale = scale
        self.duration = duration
        if held, heldSnapshot == nil, let model {
            heldSnapshot = MotionGraphSnapshot(time: ProcessInfo.processInfo.systemUptime,
                                               points: model.motionTrace.points, minimum: model.amplitudeFloor)
            draftThreshold = nil
        } else if !held {
            heldSnapshot = nil
        }
        setAccessibilityHelp(held
            ? "Trace held for inspection. Resume live view to change the threshold."
            : "Drag the gold line or use arrow keys. Higher values require stronger taps.")
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        hoverX = plot.contains(location) ? location.x : nil
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) { hoverX = nil; needsDisplay = true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        model?.graphIsAttached = window != nil
        model?.refreshGraph = { [weak self] in
            guard let self, !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
            self.needsDisplay = true
        }
    }

    private func y(_ amplitude: Double) -> CGFloat {
        plot.minY + scale.position(for: amplitude) * plot.height
    }
    // Fonts are cached because monospacedSystemFont was re-resolved on every
    // frame and a system font-resolution race during appearance changes crashed
    // CoreText once in testing (TapThatX-2026-09-17-152424.ips).
    private static let smallFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

    private func text(_ value: String, x: CGFloat, y: CGFloat, color: NSColor, size: CGFloat = 11) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: size < 10 ? Self.smallFont : Self.labelFont, .foregroundColor: color
        ])
    }
    private func drawBackdrop() {
        let panel = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.039, green: 0.094, blue: 0.149, alpha: 1).setFill()
        panel.fill()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.039, green: 0.094, blue: 0.149, alpha: 1),
            NSColor(calibratedRed: 0.063, green: 0.122, blue: 0.188, alpha: 1)
        ])?.draw(in: panel, angle: 90)
        let grid = NSBezierPath()
        for value in scale.ticks {
            grid.move(to: NSPoint(x: plot.minX, y: y(value)))
            grid.line(to: NSPoint(x: plot.maxX, y: y(value)))
            text(String(format: "%.3f", value), x: 5, y: y(value) - 6, color: axisText, size: 9)
        }
        for index in 0...8 {
            let x = plot.minX + Double(index) / 8 * plot.width
            grid.move(to: NSPoint(x: x, y: plot.minY)); grid.line(to: NSPoint(x: x, y: plot.maxY))
        }
        NSColor.white.withAlphaComponent(0.10).setStroke(); grid.lineWidth = 0.5; grid.stroke()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let snapshot = heldSnapshot ?? MotionGraphSnapshot(time: ProcessInfo.processInfo.systemUptime,
                                                           points: model.motionTrace.points, minimum: model.amplitudeFloor)
        drawSnapshot(snapshot)
    }

    func drawSnapshot(_ snapshot: MotionGraphSnapshot) {
        guard let model else { return }
        // Grid and axis text are unchanged between frames; cache per size/scale.
        if backdrop?.size != bounds.size {
            let image = NSImage(size: bounds.size)
            image.lockFocus(); drawBackdrop(); image.unlockFocus()
            backdrop = image
        }
        backdrop?.draw(in: bounds)
        let time = snapshot.time
        let points = snapshot.visiblePoints(duration: duration)
        let waveform = NSBezierPath()
        let adaptive = NSBezierPath()
        var previous: MotionTrace.Point?
        for point in points {
            let x = plot.maxX - (time - point.time) / duration * plot.width
            let p = NSPoint(x: x, y: y(point.peak))
            let t = NSPoint(x: x, y: y(point.threshold))
            if previous == nil || point.time - previous!.time > 0.1 {
                waveform.move(to: p); adaptive.move(to: t)
            } else { waveform.line(to: p); adaptive.line(to: t) }
            previous = point
        }
        if model.sampleRate < 50 {
            reactor.setFill()
            for point in points {
                let x = plot.maxX - (time - point.time) / duration * plot.width
                NSBezierPath(ovalIn: NSRect(x: x - 2, y: y(point.peak) - 2, width: 4, height: 4)).fill()
            }
        }
        // Static glow: one wider low-alpha pass of the same path under the main stroke.
        reactor.withAlphaComponent(0.18).setStroke(); waveform.lineWidth = 5; waveform.stroke()
        reactor.setStroke(); waveform.lineWidth = 1.6; waveform.stroke()
        gold.withAlphaComponent(0.55).setStroke()
        adaptive.setLineDash([3, 4], count: 2, phase: 0); adaptive.lineWidth = 1; adaptive.stroke()
        let value = draftThreshold ?? snapshot.minimum
        let line = NSBezierPath()
        line.move(to: NSPoint(x: plot.minX, y: y(value))); line.line(to: NSPoint(x: plot.maxX, y: y(value)))
        gold.setStroke(); line.lineWidth = 1.5; line.stroke()
        gold.setFill(); NSBezierPath(ovalIn: NSRect(x: plot.maxX - 5, y: y(value) - 5, width: 10, height: 10)).fill()
        text(String(format: "MINIMUM %.4f g%@", value, heldSnapshot == nil ? "  ↕" : " · HELD"),
             x: plot.minX + 8, y: min(plot.maxY - 14, y(value) + 5), color: gold)
        let state: String
        if heldSnapshot != nil { state = "HELD · SNAPSHOT" }
        else if model.paused { state = "PAUSED" }
        else if model.status != "Streaming accelerometer" && model.input != .simulated { state = "WAITING FOR SENSOR" }
        else if model.sampleRate < 50 { state = "RECORDING ONLY · BELOW 50 HZ" }
        else if model.liveWarmingUp { state = "SETTLING · KEEP STILL" }
        else if let recognized = model.lastDoubleTime, time - recognized < 1.2 { state = "DOUBLE-TAP RECOGNIZED" }
        else { state = "LIVE · TAP TO TRY" }
        text(state, x: 16, y: bounds.height - 26, color: reactor)
        if let hoverX, !points.isEmpty {
            let targetTime = time - Double((plot.maxX - hoverX) / plot.width) * duration
            if let point = points.min(by: { abs($0.time - targetTime) < abs($1.time - targetTime) }),
               abs(point.time - targetTime) <= 0.1 {
                let x = plot.maxX - (time - point.time) / duration * plot.width
                let cursor = NSBezierPath()
                cursor.move(to: NSPoint(x: x, y: plot.minY)); cursor.line(to: NSPoint(x: x, y: plot.maxY))
                reactor.withAlphaComponent(0.45).setStroke(); cursor.lineWidth = 1; cursor.stroke()
                reactor.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 3, y: y(point.peak) - 3, width: 6, height: 6)).fill()
                text(String(format: "−%.2fs  PEAK %.4f g  GATE %.4f g", time - point.time, point.peak, point.threshold),
                     x: 16, y: bounds.height - 47, color: reactor)
            } else {
                text("NO SAMPLE HERE · GAP IN SIGNAL", x: 16, y: bounds.height - 47, color: axisText)
            }
        } else {
            let peak = points.map(\.peak).max() ?? 0
            let detail = points.isEmpty ? "NO SAMPLES IN THIS WINDOW" : String(format: "WINDOW PEAK %.4f g%@", peak,
                peak > MotionGraphScale.ceiling ? " · CLIPPED ABOVE 0.100 g" : " · HOVER TO INSPECT")
            text(detail, x: 16, y: bounds.height - 47, color: axisText)
        }
        // The taps/pairs counter moved into the pane's hero header so it can
        // animate with contentTransition(.numericText()).
        text("−\(Int(duration))s", x: plot.minX, y: 12, color: axisText)
        text(scale == .detail ? "MOTION (g) · NONLINEAR" : "MOTION (g) · LINEAR", x: plot.minX + 58, y: 12, color: axisText)
        text(heldSnapshot == nil ? "NOW" : "HELD", x: plot.maxX - 28, y: 12, color: axisText)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard heldSnapshot == nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard location.x >= plot.minX, location.x <= plot.maxX else { return }
        guard abs(location.y - y(model?.amplitudeFloor ?? 0.0175)) < 22 else { return }
        draftThreshold = model?.amplitudeFloor
        mouseDragged(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard draftThreshold != nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        draftThreshold = min(0.07, max(0.005, scale.amplitude(at: Double((location.y - plot.minY) / plot.height))))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let value = draftThreshold else { return }
        draftThreshold = nil
        model?.setAmplitudeFloor(value)
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126, 124: adjust(by: event.modifierFlags.contains(.shift) ? 0.0001 : 0.001)
        case 125, 123: adjust(by: event.modifierFlags.contains(.shift) ? -0.0001 : -0.001)
        case 53: draftThreshold = nil; needsDisplay = true
        default: super.keyDown(with: event)
        }
    }
    private func adjust(by amount: Double) {
        guard heldSnapshot == nil, let model else { return }
        model.setAmplitudeFloor(model.amplitudeFloor + amount)
        needsDisplay = true
    }
    override func accessibilityValue() -> Any? { heldSnapshot?.minimum ?? model?.amplitudeFloor }
    override func accessibilityMinValue() -> Any? { 0.005 }
    override func accessibilityMaxValue() -> Any? { 0.07 }
    override func accessibilityPerformIncrement() -> Bool {
        guard heldSnapshot == nil else { return false }
        adjust(by: 0.001); return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard heldSnapshot == nil else { return false }
        adjust(by: -0.001); return true
    }
}
