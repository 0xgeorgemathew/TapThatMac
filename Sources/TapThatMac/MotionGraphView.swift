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
    var taps: [TapMark] = []

    func visiblePoints(duration: Double) -> [MotionTrace.Point] {
        points.filter { $0.time <= time && time - $0.time <= duration }
    }
}

/// One drawing surface, driven by the model's refresh timer (20 Hz while
/// visible). No per-sample SwiftUI state.
///
/// The picture, back to front: a recessed well with a faint grid; a column
/// for every recent tap, with a bracket over each recognized pair; the motion
/// trace as a glowing cyan line over a fading fill; the light-tap impulse in
/// violet; the dashed adaptive gate; and the gold threshold with a draggable
/// value pill. The newest sample breathes at the right edge.
final class MotionGraphNSView: NSView {
    private weak var model: AppModel?
    private var draftThreshold: Double?
    private var scale: MotionGraphScale = .detail
    private var duration: Double = 8
    private(set) var heldSnapshot: MotionGraphSnapshot?
    private var hoverPoint: NSPoint?
    private var hoveringThreshold = false
    private var tracking: NSTrackingArea?
    private var plot: NSRect {
        NSRect(x: 46, y: 28, width: max(1, bounds.width - 62), height: max(1, bounds.height - 66))
    }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

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
        if self.scale != scale { draftThreshold = nil }
        self.scale = scale
        self.duration = duration
        if held, heldSnapshot == nil, let model {
            heldSnapshot = MotionGraphSnapshot(time: ProcessInfo.processInfo.systemUptime,
                                               points: model.motionTrace.points, minimum: model.amplitudeFloor,
                                               taps: model.recentTaps)
            draftThreshold = nil
        } else if !held {
            heldSnapshot = nil
        }
        setAccessibilityHelp(held
            ? "Trace held for inspection. Resume live view to change the threshold."
            : "Drag the gold line or use arrow keys. Higher values require stronger taps.")
        needsDisplay = true
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        hoverPoint = plot.insetBy(dx: 0, dy: -6).contains(location) ? location : nil
        let nearLine = heldSnapshot == nil && isNearThreshold(location)
        if nearLine != hoveringThreshold { hoveringThreshold = nearLine }
        (nearLine ? NSCursor.resizeUpDown : NSCursor.arrow).set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        hoveringThreshold = false
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        model?.graphIsAttached = window != nil
        model?.refreshGraph = { [weak self] in
            guard let self, !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
            self.needsDisplay = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Geometry

    private func y(_ amplitude: Double) -> CGFloat {
        plot.minY + scale.position(for: amplitude) * plot.height
    }

    private func x(_ time: Double, now: Double) -> CGFloat {
        plot.maxX - (now - time) / duration * plot.width
    }

    private func isNearThreshold(_ location: NSPoint) -> Bool {
        guard location.x >= plot.minX - 4, location.x <= plot.maxX + 8 else { return false }
        return abs(location.y - y(model?.amplitudeFloor ?? 0.0175)) < 12
    }

    // MARK: Type
    // Fonts are cached: resolving system fonts on every frame raced CoreText
    // during an appearance change once (TapThatMac-2026-09-17-152424.ips).

    private static let tickFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    private static let capsFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let tipFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    private func attributed(_ string: String, _ font: NSFont, _ color: NSColor, caps: Bool = false) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if caps { attributes[.kern] = 0.9 }
        guard caps else { return NSAttributedString(string: string, attributes: attributes) }
        // Caps for words, never for units: "PEAK 0.0238 g", "BELOW 50 Hz".
        let upper = string.uppercased()
            .replacingOccurrences(of: #"(\d) G\b"#, with: "$1 g", options: .regularExpression)
            .replacingOccurrences(of: "HZ", with: "Hz")
        return NSAttributedString(string: upper, attributes: attributes)
    }

    /// Draws text with its vertical center at `y`. `align` is .left, .right or .center about `x`.
    @discardableResult
    private func text(_ string: NSAttributedString, x: CGFloat, centerY: CGFloat, align: NSTextAlignment = .left) -> NSRect {
        let size = string.size()
        let originX: CGFloat = switch align {
        case .right: x - size.width
        case .center: x - size.width / 2
        default: x
        }
        let rect = NSRect(x: originX, y: centerY - size.height / 2, width: size.width, height: size.height)
        string.draw(at: rect.origin)
        return rect
    }

    private func capsule(_ rect: NSRect, fill: NSColor, stroke: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        fill.setFill(); path.fill()
        if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let snapshot = heldSnapshot ?? MotionGraphSnapshot(time: ProcessInfo.processInfo.systemUptime,
                                                           points: model.motionTrace.points,
                                                           minimum: model.amplitudeFloor, taps: model.recentTaps)
        drawSnapshot(snapshot)
    }

    func drawSnapshot(_ snapshot: MotionGraphSnapshot) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            render(snapshot)
        }
    }

    private func render(_ snapshot: MotionGraphSnapshot) {
        guard let model else { return }
        let now = snapshot.time
        let points = snapshot.visiblePoints(duration: duration)
        let held = heldSnapshot != nil
        let focused = window?.firstResponder === self

        drawWell(focused: focused)
        drawGrid(now: now)
        drawTaps(snapshot.taps, now: now)

        // Motion and impulse traces, split wherever the stream had a gap.
        var segments: [[NSPoint]] = []
        let impulse = NSBezierPath()
        let impulseGate = NSBezierPath()
        let gate = NSBezierPath()
        var previous: MotionTrace.Point?
        for point in points {
            let px = x(point.time, now: now)
            let p = NSPoint(x: px, y: y(point.peak))
            let g = NSPoint(x: px, y: y(point.threshold))
            if let last = previous, point.time - last.time <= 0.1, !segments.isEmpty {
                segments[segments.count - 1].append(p)
                gate.line(to: g)
            } else {
                segments.append([p])
                gate.move(to: g)
            }
            if let peak = point.impulsePeak, let threshold = point.impulseThreshold {
                let ip = NSPoint(x: px, y: y(peak)), ig = NSPoint(x: px, y: y(threshold))
                if previous?.impulsePeak == nil || point.time - (previous?.time ?? 0) > 0.1 {
                    impulse.move(to: ip); impulseGate.move(to: ig)
                } else {
                    impulse.line(to: ip); impulseGate.line(to: ig)
                }
            }
            previous = point
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot.insetBy(dx: -2, dy: -2)).addClip()

        // Fill under the motion trace, fading to nothing at the baseline.
        let fill = NSBezierPath()
        for segment in segments where segment.count > 1 {
            fill.move(to: NSPoint(x: segment[0].x, y: plot.minY))
            segment.forEach { fill.line(to: $0) }
            fill.line(to: NSPoint(x: segment[segment.count - 1].x, y: plot.minY))
            fill.close()
        }
        if !fill.isEmpty {
            NSGradient(colors: [Palette.signal.withAlphaComponent(0.26), Palette.signal.withAlphaComponent(0.0)])?
                .draw(in: fill, angle: -90)
        }

        Palette.gate.withAlphaComponent(0.42).setStroke()
        gate.setLineDash([3, 4], count: 2, phase: 0); gate.lineWidth = 1; gate.stroke()

        Palette.impulse.withAlphaComponent(0.85).setStroke()
        impulse.lineWidth = 1; impulse.lineJoinStyle = .round; impulse.stroke()
        Palette.impulse.withAlphaComponent(0.55).setStroke()
        impulseGate.setLineDash([1, 4], count: 2, phase: 0); impulseGate.lineWidth = 1
        impulseGate.lineCapStyle = .round; impulseGate.stroke()

        let trace = NSBezierPath()
        for segment in segments {
            trace.move(to: segment[0])
            segment.dropFirst().forEach { trace.line(to: $0) }
        }
        trace.lineJoinStyle = .round
        Palette.signal.withAlphaComponent(0.2).setStroke(); trace.lineWidth = 4.5; trace.stroke()
        Palette.signal.setStroke(); trace.lineWidth = 1.5; trace.stroke()

        if model.sampleRate < 50 {
            Palette.signal.setFill()
            for segment in segments {
                for p in segment { NSBezierPath(ovalIn: NSRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill() }
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        drawThreshold(draftThreshold ?? snapshot.minimum, held: held)
        if !held, let last = points.last, now - last.time < 0.3 {
            drawNowDot(at: NSPoint(x: x(last.time, now: now), y: y(last.peak)), now: now)
        }
        drawHeader(points: points, now: now, held: held)
        drawAxis(held: held)
        if let hoverPoint { drawInspector(at: hoverPoint, points: points, now: now) }
    }

    private func drawWell(focused: Bool) {
        let well = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        Palette.well.setFill(); well.fill()
        (focused ? Palette.signal.withAlphaComponent(0.7) : Palette.hairline).setStroke()
        well.lineWidth = focused ? 1.5 : 1
        well.stroke()
    }

    private func drawGrid(now: Double) {
        let grid = NSBezierPath()
        for value in scale.ticks {
            let gy = y(value)
            grid.move(to: NSPoint(x: plot.minX, y: gy)); grid.line(to: NSPoint(x: plot.maxX, y: gy))
            var label = value == 0 ? "0" : value >= 0.01 ? String(format: "%.2f", value) : String(format: "%.3f", value)
            if value == scale.ticks.last { label += " g" }
            text(attributed(label, Self.tickFont, Palette.faint), x: plot.minX - 8, centerY: gy, align: .right)
        }
        let step = duration <= 2 ? 0.5 : 1
        var t = 0.0
        while t <= duration + 0.001 {
            let gx = plot.maxX - t / duration * plot.width
            grid.move(to: NSPoint(x: gx, y: plot.minY)); grid.line(to: NSPoint(x: gx, y: plot.maxY))
            t += step
        }
        Palette.grid.setStroke(); grid.lineWidth = 1; grid.stroke()
    }

    /// A faint column per tap; a bracket and a DOUBLE-TAP pill over each pair.
    private func drawTaps(_ taps: [TapMark], now: Double) {
        let visible = taps.filter { $0.time <= now && now - $0.time <= duration }
        guard !visible.isEmpty else { return }
        for tap in visible {
            let tx = x(tap.time, now: now)
            let age = now - tap.time
            // A fresh tap flashes, then settles to a quiet column.
            let fresh = max(0, 1 - age / 0.6)
            let column = NSRect(x: tx - 1, y: plot.minY, width: 2, height: plot.height)
            NSGradient(colors: [Palette.signal.withAlphaComponent(0.0),
                                Palette.signal.withAlphaComponent(0.16 + 0.3 * fresh)])?.draw(in: column, angle: 90)
            let dot = NSRect(x: tx - 3, y: plot.maxY - 3, width: 6, height: 6)
            Palette.signal.withAlphaComponent(tap.paired ? 1 : 0.6).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        // Pair brackets: consecutive paired taps.
        var index = 0
        while index + 1 < visible.count {
            let first = visible[index], second = visible[index + 1]
            if first.paired && second.paired && second.time - first.time < 0.6 {
                let x1 = x(first.time, now: now), x2 = x(second.time, now: now)
                let bracketY = plot.maxY + 9
                let bracket = NSBezierPath()
                bracket.move(to: NSPoint(x: x1, y: plot.maxY + 3))
                bracket.line(to: NSPoint(x: x1, y: bracketY))
                bracket.line(to: NSPoint(x: x2, y: bracketY))
                bracket.line(to: NSPoint(x: x2, y: plot.maxY + 3))
                Palette.signal.withAlphaComponent(0.7).setStroke()
                bracket.lineWidth = 1; bracket.lineJoinStyle = .round; bracket.stroke()
                let label = attributed("Double", Self.capsFont, Palette.onSignal, caps: true)
                let size = label.size()
                let pill = NSRect(x: (x1 + x2) / 2 - size.width / 2 - 6, y: bracketY - 1,
                                  width: size.width + 12, height: 14)
                capsule(pill, fill: Palette.signal)
                text(label, x: pill.midX, centerY: pill.midY, align: .center)
                index += 2
            } else {
                index += 1
            }
        }
    }

    private func drawThreshold(_ value: Double, held: Bool) {
        let ly = y(value)
        let emphasized = hoveringThreshold || draftThreshold != nil
        let line = NSBezierPath()
        line.move(to: NSPoint(x: plot.minX, y: ly)); line.line(to: NSPoint(x: plot.maxX, y: ly))
        if emphasized {
            Palette.gate.withAlphaComponent(0.25).setStroke(); line.lineWidth = 6; line.stroke()
        }
        Palette.gate.setStroke(); line.lineWidth = emphasized ? 2 : 1.5; line.stroke()

        let label = attributed(String(format: "%.4f g", value) + (held ? "" : "  ↕"), Self.valueFont, Palette.onSignal)
        let size = label.size()
        let pill = NSRect(x: plot.maxX - size.width - 14, y: ly - 9, width: size.width + 14, height: 18)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = Palette.gate.withAlphaComponent(emphasized ? 0.6 : 0.3)
        shadow.shadowBlurRadius = emphasized ? 10 : 6
        shadow.set()
        capsule(pill, fill: Palette.gate)
        NSGraphicsContext.restoreGraphicsState()
        text(label, x: pill.midX, centerY: pill.midY, align: .center)
    }

    /// The newest sample: a dot with a slow breathing halo.
    private func drawNowDot(at point: NSPoint, now: Double) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let phase = reduceMotion ? 0.5 : (now.truncatingRemainder(dividingBy: 1.6)) / 1.6
        let halo = 4 + 8 * phase
        Palette.signal.withAlphaComponent(0.35 * (1 - phase)).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)).fill()
        Palette.canvas.setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
        Palette.signal.setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 2.75, y: point.y - 2.75, width: 5.5, height: 5.5)).fill()
    }

    private func drawHeader(points: [MotionTrace.Point], now: Double, held: Bool) {
        guard let model else { return }
        let top = bounds.height - 16
        let state: (String, NSColor)
        if held { state = ("Held", Palette.gate) }
        else if model.paused { state = ("Paused", Palette.faint) }
        else if model.status != "Streaming accelerometer" && model.input != .simulated { state = ("Waiting for sensor", Palette.danger) }
        else if model.sampleRate < 50 { state = ("Recording only · below 50 Hz", Palette.warn) }
        else if model.liveWarmingUp { state = ("Settling · keep still", Palette.warn) }
        else if let recognized = model.lastDoubleTime, now - recognized < 1.2 { state = ("Double-tap recognized", Palette.signal) }
        else { state = ("Live · tap to try", Palette.signal) }
        state.1.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: top - 3, width: 6, height: 6)).fill()
        text(attributed(state.0, Self.capsFont, state.1, caps: true), x: 28, centerY: top)

        let peak = points.map(\.peak).max() ?? 0
        let detail = points.isEmpty ? "No samples in this window"
            : String(format: "Peak %.4f g", peak) + (peak > MotionGraphScale.ceiling ? " · clipped" : "")
        text(attributed(detail, Self.capsFont, Palette.faint, caps: true), x: bounds.width - 16, centerY: top, align: .right)
    }

    private func drawAxis(held: Bool) {
        let axisY: CGFloat = 14
        let half = Int(duration / 2)
        text(attributed("−\(Int(duration)) s", Self.tickFont, Palette.faint), x: plot.minX, centerY: axisY)
        text(attributed("−\(half) s", Self.tickFont, Palette.faint), x: plot.midX, centerY: axisY, align: .center)
        text(attributed(held ? "Held" : "Now", Self.capsFont, Palette.faint, caps: true),
             x: plot.maxX, centerY: axisY, align: .right)
    }

    /// Hover: a cursor line, a ringed dot on the trace, and a small card.
    private func drawInspector(at location: NSPoint, points: [MotionTrace.Point], now: Double) {
        guard !points.isEmpty else { return }
        let targetTime = now - Double((plot.maxX - location.x) / plot.width) * duration
        guard let point = points.min(by: { abs($0.time - targetTime) < abs($1.time - targetTime) }),
              abs(point.time - targetTime) <= 0.1 else { return }
        let px = x(point.time, now: now), py = y(point.peak)
        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: px, y: plot.minY)); cursor.line(to: NSPoint(x: px, y: plot.maxY))
        Palette.ink.withAlphaComponent(0.25).setStroke()
        cursor.setLineDash([2, 3], count: 2, phase: 0); cursor.lineWidth = 1; cursor.stroke()
        Palette.canvas.setFill()
        NSBezierPath(ovalIn: NSRect(x: px - 5, y: py - 5, width: 10, height: 10)).fill()
        Palette.signal.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: px - 4, y: py - 4, width: 8, height: 8)); ring.lineWidth = 2; ring.stroke()

        var lines: [NSAttributedString] = [
            attributed(String(format: "−%.2f s", now - point.time), Self.capsFont, Palette.faint),
            attributed(String(format: "Motion  %.4f g", point.peak), Self.tipFont, Palette.signal),
            attributed(String(format: "Gate     %.4f g", point.threshold), Self.tipFont, Palette.gate),
        ]
        if let peak = point.impulsePeak {
            lines.append(attributed(String(format: "Impulse %.4f g", peak), Self.tipFont, Palette.impulse))
        }
        let width = (lines.map { $0.size().width }.max() ?? 0) + 20
        let lineHeight: CGFloat = 15
        let height = CGFloat(lines.count) * lineHeight + 12
        var originX = px + 12
        if originX + width > bounds.maxX - 8 { originX = px - 12 - width }
        let originY = min(max(plot.minY, py - height / 2), plot.maxY - height)
        let card = NSRect(x: originX, y: originY, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        Palette.discTop.setFill()
        NSBezierPath(roundedRect: card, xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.restoreGraphicsState()
        Palette.hairline.setStroke()
        NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
        for (index, line) in lines.enumerated() {
            text(line, x: card.minX + 10, centerY: card.maxY - 6 - lineHeight * (CGFloat(index) + 0.5))
        }
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard heldSnapshot == nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard isNearThreshold(location) else { return }
        draftThreshold = model?.amplitudeFloor
        mouseDragged(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard draftThreshold != nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        draftThreshold = min(DetectorSettings.maximumAmplitudeFloor,
                             max(DetectorSettings.minimumAmplitudeFloor,
                                 scale.amplitude(at: Double((location.y - plot.minY) / plot.height))))
        NSCursor.resizeUpDown.set()
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let value = draftThreshold else { return }
        draftThreshold = nil
        model?.setAmplitudeFloor(value)
        // A soft detent: the threshold has been set.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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
    override func accessibilityMinValue() -> Any? { DetectorSettings.minimumAmplitudeFloor }
    override func accessibilityMaxValue() -> Any? { DetectorSettings.maximumAmplitudeFloor }
    override func accessibilityPerformIncrement() -> Bool {
        guard heldSnapshot == nil else { return false }
        adjust(by: 0.001); return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        guard heldSnapshot == nil else { return false }
        adjust(by: -0.001); return true
    }
}
