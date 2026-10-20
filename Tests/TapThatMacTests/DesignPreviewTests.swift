import AppKit
import SwiftUI
import XCTest
import TapCore
@testable import TapThatMac

/// Optional native renders of the main surfaces for visual review.
/// Set DESIGN_PREVIEW_DIR to write PNGs in dark and light appearance.
@MainActor
final class DesignPreviewTests: XCTestCase {
    private func render<V: View>(_ view: V, size: NSSize, name: String, in directory: URL) throws {
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
                .background(Theme.canvas))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    func testRenderDesignPreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["DESIGN_PREVIEW_DIR"] else {
            throw XCTSkip("Set DESIGN_PREVIEW_DIR to render design previews")
        }
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(startServices: false)

        try render(SetupView(model: model), size: NSSize(width: 960, height: 900), name: "live", in: directory)
        model.doubleTapAction = .ring
        try render(ActionsPane(model: model), size: NSSize(width: 720, height: 900), name: "actions-ring", in: directory)
        model.doubleTapAction = .lock
        try render(ActionsPane(model: model), size: NSSize(width: 720, height: 900), name: "actions-lock", in: directory)
        try render(CalibrationPane(model: model, calibration: model.calibration),
                   size: NSSize(width: 860, height: 640), name: "calibration", in: directory)

        // The graph with a realistic trace: a noise floor, a recognized pair
        // and a lone tap, each ringing down after its peak.
        var trace = MotionTrace()
        var generator = SystemRandomNumberGenerator()
        let tapTimes = [2.1, 2.36, 5.4]
        for index in 0..<400 {
            let time = Double(index) * 0.02
            var peak = 0.0009 + Double.random(in: 0...0.0009, using: &generator)
            for tap in tapTimes where time >= tap && time - tap < 0.2 {
                peak += 0.022 * exp(-(time - tap) * 28)
            }
            trace.append(time: time, amplitude: peak, threshold: 0.0045 + peak * 0.2,
                         impulseAmplitude: peak * 0.6, impulseThreshold: 0.003)
        }
        let snapshot = MotionGraphSnapshot(
            time: 8, points: trace.points, minimum: 0.0137,
            taps: [TapMark(time: 2.1, paired: true), TapMark(time: 2.36, paired: true), TapMark(time: 5.4)])
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let size = NSSize(width: 660, height: 300)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let graph = MotionGraphNSView(model: model)
            graph.frame = NSRect(origin: .zero, size: size)
            window.contentView = graph
            let image = NSImage(size: size, flipped: false) { rect in
                window.effectiveAppearance.performAsCurrentDrawingAppearance {
                    Palette.canvas.setFill(); rect.fill()
                }
                graph.drawSnapshot(snapshot)
                return true
            }
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("graph-\(suffix).png"))
        }

        let state = RingState()
        state.resetSelection(.lock)
        state.tapPending = true
        try render(RingContent(state: state, size: 440, reduceMotion: true).padding(40),
                   size: NSSize(width: 520, height: 520), name: "ring", in: directory)
        let chatState = RingState()
        chatState.resetSelection(.approve)
        try render(RingContent(state: chatState, size: 440, reduceMotion: true).padding(40),
                   size: NSSize(width: 520, height: 520), name: "ring-chatgpt", in: directory)
    }
}
