import XCTest
import AppKit
import TapCore
@testable import TapThatX

final class CalibrationControllerTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func controller() -> CalibrationController {
        let directory = directory!
        let c = CalibrationController(directory: { directory })
        c.begin(context: .init(surface: "Laptop", placement: "Synthetic test", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        return c
    }
    private func record(_ c: CalibrationController, at start: Double = 100, contacts: Bool = true) {
        let step = c.step!
        c.record(at: start)
        for tick in 0...Int((step.duration + 0.25) * 20) {
            let elapsed = Double(tick) / 20
            let samples = (0..<40).map { i -> AccelerationSample in
                let t = elapsed - 0.05 + Double(i + 1) / 800
                let times = !contacts || step.activity.expectedContacts == 0 ? [] : step.activity.expectedContacts == 2 ? [2.8, 3.05] : [2.8]
                let active = times.contains { t >= $0 && t < $0 + 0.012 }
                let amplitude = step.activity == .lightTap || step.activity == .lightPair ? 0.018 : 0.08
                return .init(time: start + t, x: active ? amplitude : 0, y: 0, z: 1)
            }
            c.append(samples, receivedAt: start + elapsed)
            c.tick(at: start + elapsed)
        }
    }

    func testActionsStayBlockedAcrossRecordReviewRetryAndBetweenSteps() throws {
        let c = controller()
        XCTAssertTrue(c.blocksActions)
        record(c)
        XCTAssertEqual(c.stage, .review); XCTAssertTrue(c.canConfirm); XCTAssertTrue(c.blocksActions)
        c.retry()
        XCTAssertEqual(c.stage, .ready); XCTAssertEqual(c.completedCount, 0)
        XCTAssertFalse(try XCTUnwrap(c.session?.trials.first).confirmed)
        record(c, at: 120); c.confirm()
        XCTAssertEqual(c.completedCount, 1); XCTAssertTrue(c.blocksActions)
        let disk = try JSONDecoder().decode(CalibrationSession.self, from: Data(contentsOf: XCTUnwrap(c.archiveURL)))
        XCTAssertEqual(disk.trials.count, 2); XCTAssertTrue(disk.trials[1].confirmed)
    }

    func testInterruptedRecordingCannotBeConfirmed() {
        let c = controller(); c.record(at: 100)
        c.interrupt("Window hidden", at: 101)
        XCTAssertEqual(c.stage, .review); XCTAssertFalse(c.canConfirm)
        c.confirm(); XCTAssertEqual(c.completedCount, 0)
        XCTAssertTrue(c.cancel(at: 102)); XCTAssertFalse(c.blocksActions)
    }

    func testCreationFailureDoesNotStartOrEraseExistingSession() throws {
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        let c = CalibrationController(directory: { blocker })
        c.begin(context: .init(surface: "Laptop", placement: "Test", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        XCTAssertEqual(c.stage, .idle); XCTAssertNil(c.session); XCTAssertNotNil(c.saveError)
    }

    func testCheckpointFailureKeepsReviewAndDoesNotAdvance() throws {
        let c = controller(); record(c)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        c.confirm()
        XCTAssertEqual(c.stage, .review); XCTAssertEqual(c.completedCount, 0)
        XCTAssertNotNil(c.review); XCTAssertNotNil(c.saveError); XCTAssertTrue(c.blocksActions)
    }

    @MainActor
    func testAppBlocksActionsAndEnableCloseAcrossCalibration() {
        _ = NSApplication.shared
        let c = controller()
        let model = AppModel(startServices: false, calibration: c)
        model.actionsEnabled = false
        XCTAssertEqual(model.actionBlockReason, "Recording: actions paused")
        model.enableAndCloseSettings()
        XCTAssertFalse(model.actionsEnabled)
        model.previewRing()
        XCTAssertFalse(model.ring.isOpen)
        record(c)
        XCTAssertEqual(model.actionBlockReason, "Recording: actions paused")
        model.shutdown()
    }

    func testNewSessionsNeverOverwriteEarlierRecordings() throws {
        let c = controller(); let first = try XCTUnwrap(c.archiveURL)
        XCTAssertTrue(c.cancel(at: 100))
        c.begin(context: .init(surface: "Desk", placement: "Test", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        XCTAssertNotEqual(first, c.archiveURL); XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testFourGestureFlowBuildsProfileAndRequiresExplicitApplication() throws {
        let c = controller()
        for index in CalibrationStep.sequence.indices {
            record(c, at: 100 + Double(index) * 20)
            XCTAssertTrue(c.canConfirm, c.review?.quality.issues.joined(separator: ";") ?? "no review")
            XCTAssertTrue(c.reviewMatchesExpectedGesture)
            c.confirm()
        }
        XCTAssertEqual(c.stage, .complete); XCTAssertFalse(c.applied)
        XCTAssertTrue(c.session?.verificationPassed == true); XCTAssertFalse(c.blocksActions)
        let disk = try JSONDecoder().decode(CalibrationSession.self, from: Data(contentsOf: XCTUnwrap(c.archiveURL)))
        XCTAssertTrue(disk.verificationPassed); XCTAssertEqual(disk.trials.count, 4)
    }

    func testMissingGestureCannotProduceAnApplicableSetting() {
        let c = controller()
        for index in CalibrationStep.sequence.indices {
            record(c, at: 100 + Double(index) * 20, contacts: index != 2)
            c.confirm()
        }
        XCTAssertEqual(c.stage, .failed); XCTAssertFalse(c.session?.verificationPassed ?? true)
        XCTAssertFalse(c.applied)
    }

    func testCurrentFlowContainsOnlyTheFourRequestedGestures() {
        let c = controller()
        XCTAssertEqual(c.steps.map(\.activity), [.lightTap, .lightPair, .knock, .knockPair])
        XCTAssertTrue(c.steps.allSatisfy { $0.responseDuration == 2.5 })
    }
}
