import AppKit
import XCTest
import TapCore
@testable import TapThatX

final class MotionGraphViewTests: XCTestCase {
    func testSnapshotRetainsPeaksAndTimeWindowWhileSourceAdvances() {
        var trace = MotionTrace()
        for index in 0...10 {
            trace.append(time: Double(index), amplitude: Double(index) / 1000, threshold: 0.006)
        }
        let snapshot = MotionGraphSnapshot(time: 9, points: trace.points, minimum: 0.006)
        for index in 11...500 {
            trace.append(time: Double(index), amplitude: 0.1, threshold: 0.02)
        }
        XCTAssertEqual(snapshot.visiblePoints(duration: 2).map(\.time), [7, 8, 9])
        XCTAssertEqual(snapshot.visiblePoints(duration: 8).map(\.time), Array(1...9).map(Double.init))
        XCTAssertEqual(snapshot.visiblePoints(duration: 2).last?.peak, 0.009)
        XCTAssertEqual(snapshot.minimum, 0.006)
    }

    @MainActor
    func testHoldSurvivesScaleAndWindowChangesAndBlocksThresholdEdits() throws {
        _ = NSApplication.shared
        let model = AppModel(startServices: false)
        let view = MotionGraphNSView(model: model)
        view.configure(scale: .detail, duration: 8, held: true)
        let held = try XCTUnwrap(view.heldSnapshot)
        view.configure(scale: .linear, duration: 2, held: true)
        XCTAssertEqual(view.heldSnapshot?.time, held.time)
        XCTAssertEqual(view.heldSnapshot?.minimum, held.minimum)
        XCTAssertFalse(view.accessibilityPerformIncrement())
        XCTAssertFalse(view.accessibilityPerformDecrement())
        XCTAssertEqual(model.amplitudeFloor, held.minimum)
        view.configure(scale: .detail, duration: 8, held: false)
        XCTAssertNil(view.heldSnapshot)
    }

    /// Optional native rendering for visual inspection, using generated signals.
    @MainActor
    func testRenderGraphPreviews() throws {
        guard let directory = ProcessInfo.processInfo.environment["MOTION_GRAPH_PREVIEW_DIR"] else {
            throw XCTSkip("Set MOTION_GRAPH_PREVIEW_DIR to render native graph previews")
        }
        _ = NSApplication.shared
        let model = AppModel(startServices: false)
        let view = MotionGraphNSView(model: model)
        var trace = MotionTrace()
        for index in 0..<380 {
            let time = Double(index) * 0.021
            let baseline = 0.001 + abs(sin(Double(index) * 1.7)) * 0.0015
            let peak = [90, 105, 220, 235].contains(index) ? 0.009 : baseline
            trace.append(time: time, amplitude: peak, threshold: 0.0065,
                         impulseAmplitude: peak * 0.65, impulseThreshold: 0.00375)
        }
        let snapshot = MotionGraphSnapshot(time: 8, points: trace.points, minimum: 0.006)
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for scale in MotionGraphScale.allCases {
            view.frame = NSRect(x: 0, y: 0, width: 664, height: 340)
            view.configure(scale: scale, duration: 8, held: true)
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            view.drawSnapshot(snapshot)
            image.unlockFocus()
            let data = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: url.appendingPathComponent("graph-\(scale == .detail ? "detail" : "linear").png"))
        }
    }
}
