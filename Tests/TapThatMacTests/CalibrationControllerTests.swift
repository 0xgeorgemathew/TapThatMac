import XCTest
import AppKit
import TapCore
@testable import TapThatMac

final class CalibrationControllerTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "TapThatMacTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
    private func controller() -> CalibrationController {
        let directory = directory!
        let c = CalibrationController(directory: { directory })
        c.begin(context: .init(surface: "Laptop", placement: "Synthetic test", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        return c
    }

    func testOperatingModeMigrationPreservesSavedAndLegacyIntent() {
        XCTAssertEqual(OperatingModeMigration.restore(savedMode: "Test", wasPaused: false, actionsEnabled: true), .test)
        XCTAssertEqual(OperatingModeMigration.restore(savedMode: nil, wasPaused: true, actionsEnabled: false), .paused)
        XCTAssertEqual(OperatingModeMigration.restore(savedMode: nil, wasPaused: false, actionsEnabled: false), .test)
        XCTAssertEqual(OperatingModeMigration.restore(savedMode: nil, wasPaused: false, actionsEnabled: true), .active)
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
        XCTAssertFalse(c.canRetrySave)
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

    func testRetrySaveRetainsAndAcceptsTheCapturedRecordingExactlyOnce() throws {
        let c = controller(); record(c)
        let capturedID = try XCTUnwrap(c.review?.id)
        XCTAssertFalse(c.canRetrySave)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        c.confirm()
        XCTAssertTrue(c.canRetrySave)
        XCTAssertEqual(c.review?.id, capturedID)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        c.retrySave()
        XCTAssertEqual(c.stage, .ready)
        XCTAssertEqual(c.completedCount, 1)
        XCTAssertNil(c.review); XCTAssertNil(c.saveError)
        XCTAssertFalse(c.canRetrySave)
        c.retrySave()
        let disk = try JSONDecoder().decode(CalibrationSession.self, from: Data(contentsOf: XCTUnwrap(c.archiveURL)))
        XCTAssertEqual(disk.trials.count, 1)
        XCTAssertEqual(disk.trials.first?.id, capturedID)
        XCTAssertTrue(disk.trials.first?.confirmed == true)
    }

    @MainActor
    func testOpeningAppliedCompletionPreparesFreshCalibrationWithoutRemovingArchive() throws {
        let c = controller()
        for index in CalibrationStep.sequence.indices {
            record(c, at: 100 + Double(index) * 20); c.confirm()
        }
        let archive = try XCTUnwrap(c.archiveURL)
        let saved = try Data(contentsOf: archive)
        c.prepareForPresentation()
        XCTAssertEqual(c.stage, .complete, "Completion must stay visible until application finishes")
        c.markApplied()
        // Restore the saved profile through the real model using isolated preferences.
        let profile = CalibrationProfile(session: try XCTUnwrap(c.session), settings: try XCTUnwrap(c.candidateSettings))
        defaults.set(try JSONEncoder().encode([profile]), forKey: "calibrationProfiles")
        defaults.set(profile.id.uuidString, forKey: "activeCalibrationProfileID")
        _ = NSApplication.shared
        let model = AppModel(startServices: false, calibration: c, modeDefaults: defaults, settingsDefaults: defaults)
        defer { model.shutdown() }
        XCTAssertEqual(model.activeCalibrationProfile, profile)
        let sensitivity = model.sensitivity
        c.prepareForPresentation()
        XCTAssertEqual(c.stage, .idle)
        XCTAssertEqual(model.activeCalibrationProfile, profile)
        XCTAssertEqual(model.calibrationProfiles, [profile])
        XCTAssertEqual(model.sensitivity, sensitivity)
        XCTAssertEqual(defaults.data(forKey: "calibrationProfiles"), try JSONEncoder().encode([profile]))
        XCTAssertEqual(defaults.string(forKey: "activeCalibrationProfileID"), profile.id.uuidString)
        XCTAssertNil(c.session); XCTAssertNil(c.review)
        XCTAssertFalse(c.applied)
        XCTAssertEqual(try Data(contentsOf: archive), saved)
        c.begin(context: .init(surface: "Desk", placement: "Test", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        XCTAssertEqual(c.stage, .ready)
        XCTAssertNotEqual(c.archiveURL, archive)
        XCTAssertEqual(c.completedCount, 0)
    }

    func testOpeningUnfinishedCalibrationPreservesItsReviewAndCheckpoint() throws {
        let c = controller(); record(c)
        let review = try XCTUnwrap(c.review?.id)
        let session = try XCTUnwrap(c.session?.id)
        let archive = c.archiveURL
        c.prepareForPresentation()
        XCTAssertEqual(c.stage, .review)
        XCTAssertEqual(c.review?.id, review)
        XCTAssertEqual(c.session?.id, session)
        XCTAssertEqual(c.archiveURL, archive)
    }

    @MainActor
    func testCalibrationBlocksAndRestoresTheSelectedMode() {
        _ = NSApplication.shared
        let c = controller()
        let model = AppModel(startServices: false, calibration: c, modeDefaults: defaults)
        model.operatingMode = .active
        model.accessibilityPermission = true
        XCTAssertEqual(model.actionBlockReason, "Calibration in progress")
        XCTAssertTrue(c.cancel(at: 100))
        XCTAssertEqual(model.operatingMode, .active)
        XCTAssertNil(model.actionBlockReason)
        model.shutdown()
        XCTAssertTrue(model.isShutdown)
    }

    @MainActor
    func testWindowVisibilityDoesNotChangeActionEligibility() {
        _ = NSApplication.shared
        let model = AppModel(startServices: false, modeDefaults: defaults)
        model.operatingMode = .active
        model.accessibilityPermission = true
        let before = model.actionBlockReason
        let hiddenWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        model.setupWindow = hiddenWindow
        XCTAssertFalse(model.setupWindow?.isVisible ?? true)
        XCTAssertEqual(model.actionBlockReason, before)
        model.shutdown()
    }

    @MainActor
    func testShutdownFinishesCaptureAndIsSafeToRepeat() {
        _ = NSApplication.shared
        let model = AppModel(startServices: false, modeDefaults: defaults)
        model.diagnostics.startCapture(label: "test", purpose: "test", simulated: false, expectedDoubleKnocks: 0)
        XCTAssertNotNil(model.diagnostics.current)
        model.shutdown()
        XCTAssertNil(model.diagnostics.current)
        model.shutdown()
        XCTAssertTrue(model.isShutdown)
    }

    func testNewSessionsNeverOverwriteEarlierRecordings() throws {
        let c = controller(); let first = try XCTUnwrap(c.archiveURL)
        XCTAssertTrue(c.cancel(at: 100))
        c.begin(context: .init(surface: "Desk", placement: "Test", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        XCTAssertNotEqual(first, c.archiveURL); XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testDeskCalibrationBuildsVerifiedProfileAndRequiresExplicitApplication() throws {
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
        XCTAssertTrue(disk.verificationPassed); XCTAssertEqual(disk.trials.count, c.steps.count)
    }

    func testMissingGestureCannotProduceAnApplicableSetting() {
        let c = controller()
        for index in CalibrationStep.sequence.indices {
            guard c.stage == .ready else { break }
            record(c, at: 100 + Double(index) * 20, contacts: c.step?.activity != .lightTap)
            c.confirm()
        }
        XCTAssertEqual(c.stage, .failed); XCTAssertFalse(c.session?.verificationPassed ?? true)
        XCTAssertFalse(c.applied)
    }

    func testSettingsFreezeBeforeVerificationAndAMissedVerificationDoesNotRefit() throws {
        let c = controller()
        var time = 100.0
        while c.step?.partition == .training, c.stage == .ready {
            record(c, at: time); c.confirm(); time += 20
        }
        XCTAssertEqual(c.stage, .ready)
        XCTAssertFalse(c.session?.verificationPassed ?? true)
        let frozen = try XCTUnwrap(c.candidateSettings)
        while c.stage == .ready {
            record(c, at: time, contacts: false); c.confirm(); time += 20
        }
        XCTAssertEqual(c.stage, .failed)
        XCTAssertEqual(c.candidateSettings, frozen)
        XCTAssertFalse(c.session?.verificationPassed ?? true)
    }

    func testUnwantedContactInVerificationCannotQualifyAProfile() {
        let c = controller()
        var time = 100.0
        while c.stage == .ready {
            guard let step = c.step else { break }
            record(c, at: time)
            if step.partition == .verification, step.activity.expectedContacts == 0 {
                // Add an actual impact using a separately recorded positive-shaped trial below.
                c.retry()
                c.record(at: time + 20)
                for index in 0..<Int(step.duration * 800) {
                    let t = Double(index) / 800
                    c.append([.init(time: time + 20 + t, x: (2.8..<2.812).contains(t) ? 0.08 : 0, y: 0, z: 1)],
                             receivedAt: time + 20 + t)
                }
                c.tick(at: time + 20 + step.duration + 0.25)
                time += 20
            }
            c.confirm(); time += 20
        }
        XCTAssertEqual(c.stage, .failed)
        XCTAssertFalse(c.session?.verificationPassed ?? true)
    }
}
