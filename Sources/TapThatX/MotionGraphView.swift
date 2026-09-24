import AppKit
import SwiftUI
import TapCore

struct MotionGraphView: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> MotionGraphNSView { MotionGraphNSView(model: model) }
    func updateNSView(_ view: MotionGraphNSView, context: Context) { view.needsDisplay = true }
}

/// One drawing surface, driven by the existing timer. No per-sample SwiftUI state.
final class MotionGraphNSView: NSView {
    private weak var model: AppModel?
    private var draftThreshold: Double?
    private var backdrop: NSImage?
    private let ceiling = 0.1
    private let reactor = NSColor(calibratedRed: 0.404, green: 0.780, blue: 0.922, alpha: 1)
    private let gold = NSColor(calibratedRed: 0.851, green: 0.639, blue: 0.255, alpha: 1)
    private let axisText = NSColor.white.withAlphaComponent(0.45)
    private var plot: NSRect { NSRect(x: 48, y: 36, width: max(1, bounds.width - 68), height: max(1, bounds.height - 82)) }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        model?.graphIsAttached = window != nil
        model?.refreshGraph = { [weak self] in
            guard let self, !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
            self.needsDisplay = true
        }
    }

    private func y(_ amplitude: Double) -> CGFloat {
        plot.minY + min(1, max(0, amplitude / ceiling)) * plot.height
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
        for index in 0...4 {
            let value = Double(index) * ceiling / 4
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
        // Grid and axis text are unchanged between frames; rasterize once per size.
        if backdrop?.size != bounds.size {
            let image = NSImage(size: bounds.size)
            image.lockFocus(); drawBackdrop(); image.unlockFocus()
            backdrop = image
        }
        backdrop?.draw(in: bounds)
        let time = ProcessInfo.processInfo.systemUptime
        let points = model.motionTrace.points.filter { time - $0.time <= 8 }
        let waveform = NSBezierPath()
        let adaptive = NSBezierPath()
        var previous: MotionTrace.Point?
        for point in points {
            let x = plot.maxX - (time - point.time) / 8 * plot.width
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
                let x = plot.maxX - (time - point.time) / 8 * plot.width
                NSBezierPath(ovalIn: NSRect(x: x - 2, y: y(point.peak) - 2, width: 4, height: 4)).fill()
            }
        }
        // Static glow: one wider low-alpha pass of the same path under the main stroke.
        reactor.withAlphaComponent(0.18).setStroke(); waveform.lineWidth = 5; waveform.stroke()
        reactor.setStroke(); waveform.lineWidth = 1.6; waveform.stroke()
        gold.withAlphaComponent(0.55).setStroke()
        adaptive.setLineDash([3, 4], count: 2, phase: 0); adaptive.lineWidth = 1; adaptive.stroke()
        let value = draftThreshold ?? model.amplitudeFloor
        let line = NSBezierPath()
        line.move(to: NSPoint(x: plot.minX, y: y(value))); line.line(to: NSPoint(x: plot.maxX, y: y(value)))
        gold.setStroke(); line.lineWidth = 1.5; line.stroke()
        gold.setFill(); NSBezierPath(ovalIn: NSRect(x: plot.maxX - 5, y: y(value) - 5, width: 10, height: 10)).fill()
        text(String(format: "MINIMUM %.4f g  ↕", value), x: plot.minX + 8, y: y(value) + 5, color: gold)
        let state: String
        if model.paused { state = "PAUSED" }
        else if model.status != "Streaming accelerometer" && model.input != .simulated { state = "WAITING FOR SENSOR" }
        else if model.sampleRate < 50 { state = "RECORDING ONLY · BELOW 50 HZ" }
        else if model.liveWarmingUp { state = "SETTLING · KEEP STILL" }
        else if let recognized = model.lastDoubleTime, time - recognized < 1.2 { state = "DOUBLE-TAP RECOGNIZED" }
        else { state = "LIVE · TAP TO TRY" }
        text(state, x: 16, y: bounds.height - 26, color: reactor)
        text("\(model.knocks) taps · \(model.recognizedPairs) pairs", x: max(220, bounds.width - 215), y: bounds.height - 26, color: .lightGray)
        text("−8s", x: plot.minX, y: 12, color: axisText)
        text(points.contains { $0.peak > ceiling } ? "Peak exceeds 0.100 g" : "MOTION (g)", x: plot.minX + 58, y: 12, color: axisText)
        text("NOW", x: plot.maxX - 24, y: 12, color: axisText)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        guard abs(location.y - y(model?.amplitudeFloor ?? 0.0175)) < 22 else { return }
        draftThreshold = model?.amplitudeFloor
        mouseDragged(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard draftThreshold != nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        draftThreshold = min(0.07, max(0.005, Double((location.y - plot.minY) / plot.height) * ceiling))
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
        case 126, 124: adjust(by: 0.001)
        case 125, 123: adjust(by: -0.001)
        case 53: draftThreshold = nil; needsDisplay = true
        default: super.keyDown(with: event)
        }
    }
    private func adjust(by amount: Double) {
        guard let model else { return }
        model.setAmplitudeFloor(model.amplitudeFloor + amount)
        needsDisplay = true
    }
    override func accessibilityValue() -> Any? { model?.amplitudeFloor }
    override func accessibilityMinValue() -> Any? { 0.005 }
    override func accessibilityMaxValue() -> Any? { 0.07 }
    override func accessibilityPerformIncrement() -> Bool { adjust(by: 0.001); return true }
    override func accessibilityPerformDecrement() -> Bool { adjust(by: -0.001); return true }
}
