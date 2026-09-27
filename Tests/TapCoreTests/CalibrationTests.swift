import XCTest
@testable import TapCore

final class CalibrationTests: XCTestCase {
    private func trial(_ step: CalibrationStep, contacts: [Double]? = nil, amplitude: Double? = nil) -> CalibrationTrial {
        var recorder = CalibrationRecorder(step: step, started: 10)
        let times = contacts ?? (step.activity.expectedContacts == 0 ? [] : step.activity.expectedContacts == 2 ? [2.8, 3.05] : [2.8])
        let strength = amplitude ?? (step.activity == .lightTap || step.activity == .lightPair ? 0.018 : 0.08)
        if step.activity.expectedContacts > 0 { recorder.cue(at: 12.5); recorder.endResponse(at: 14) }
        for i in 0..<Int(step.duration * 800) {
            let t = Double(i) / 800
            let active = times.contains { t >= $0 && t < $0 + 0.012 }
            recorder.append(AccelerationSample(time: 10 + t, x: active ? strength : 0, y: 0, z: 1), receivedAt: 10 + t + 0.04)
        }
        var trial = recorder.finish(at: 10 + step.duration + 0.2)
        trial.confirmed = true
        return trial
    }

    func testCleanStreamReportsCoverageAndRateWithoutAssumingContactTruth() {
        let t = trial(.init(.lightTap, .training))
        XCTAssertTrue(t.quality.usable)
        XCTAssertEqual(t.quality.measuredRate, 800, accuracy: 0.001)
        XCTAssertEqual(t.cueTime, 12.5)
        XCTAssertEqual(t.responseEnd, 14)
        XCTAssertEqual(t.quality.maximumDeliveryDelay, 0.04, accuracy: 0.0001)
    }

    func testInvalidSamplesAndIncompleteStreamsCannotPassCollection() {
        var recorder = CalibrationRecorder(step: .init(.quiet, .training), started: 0)
        recorder.append(.init(time: 0, x: 0, y: 0, z: 1), receivedAt: 0)
        recorder.append(.init(time: 0, x: 0, y: 0, z: 1), receivedAt: 0)
        recorder.append(.init(time: 1, x: .nan, y: 0, z: 1), receivedAt: 1)
        recorder.append(.init(time: 2, x: 0, y: 0, z: 1), receivedAt: 2.5)
        let result = recorder.finish(at: 3)
        XCTAssertFalse(result.quality.usable)
        XCTAssertTrue(result.quality.issues.contains { $0.contains("out of order") })
        XCTAssertTrue(result.quality.issues.contains { $0.contains("Invalid sensor") })
        XCTAssertTrue(result.quality.issues.contains { $0.contains("interrupted") })
        XCTAssertTrue(result.quality.issues.contains { $0.contains("delayed") })
        XCTAssertEqual(result.samples.count, 2)
    }

    func testDelayedCueAndTypingInvalidateTapTrial() {
        var recorder = CalibrationRecorder(step: .init(.lightTap, .training), started: 0)
        recorder.cue(at: 3); recorder.endResponse(at: 6); recorder.key(at: 3.2)
        let result = recorder.finish(at: 7)
        XCTAssertTrue(result.quality.issues.contains { $0.contains("prompt was delayed") })
        XCTAssertTrue(result.quality.issues.contains { $0.contains("too long") })
        XCTAssertTrue(result.quality.issues.contains { $0.contains("Typing overlapped") })
    }

    func testPreStartAndPostEndSamplesAreExcluded() {
        var recorder = CalibrationRecorder(step: .init(.quiet, .training), started: 10)
        recorder.append(.init(time: 9, x: 0, y: 0, z: 1), receivedAt: 10)
        recorder.append(.init(time: 21, x: 0, y: 0, z: 1), receivedAt: 21)
        XCTAssertTrue(recorder.finish(at: 21).samples.isEmpty)
    }

    func testUnconfirmedTrialCannotBecomeGroundTruth() {
        var t = trial(.init(.lightTap, .training)); t.confirmed = false
        XCTAssertThrowsError(try CalibrationEvaluator.score(t, floor: 0.008))
    }

    func testMissingContactAndOutsideWindowReplacementFailEvenWithSameCount() throws {
        let absent = trial(.init(.lightTap, .training), contacts: [])
        let misplaced = trial(.init(.lightTap, .training), contacts: [4.5])
        XCTAssertFalse(try CalibrationEvaluator.score(absent, floor: 0.008).passed)
        let result = try CalibrationEvaluator.score(misplaced, floor: 0.008)
        XCTAssertEqual(result.matched, 0); XCTAssertEqual(result.unexpected, 1)
    }

    func testExtraContactsAndNegativeSinglesAreRejected() throws {
        let extra = trial(.init(.lightTap, .training), contacts: [2.8, 3.05])
        XCTAssertFalse(try CalibrationEvaluator.score(extra, floor: 0.008).passed)
        let negative = trial(.init(.everydayMotion, .verification), contacts: [3])
        XCTAssertFalse(try CalibrationEvaluator.score(negative, floor: 0.008).passed)
    }

    func testCompleteFourGestureTrainingProducesSettingsThatPreserveEveryGesture() throws {
        let data = CalibrationStep.sequence.map { trial($0) }
        let settings = try XCTUnwrap(CalibrationEvaluator.candidateSettings(from: data))
        XCTAssertTrue(try data.allSatisfy { try CalibrationEvaluator.score($0, settings: settings).passed })
    }

    func testMissingAndDuplicateStepsCannotQualify() {
        let data = CalibrationStep.sequence.map { trial($0) }
        XCTAssertThrowsError(try CalibrationEvaluator.candidate(from: Array(data.dropFirst())))
        XCTAssertThrowsError(try CalibrationEvaluator.candidate(from: data + [data[0]]))
    }

    func testNoCandidateWhenEachGestureContainsAnExtraAmbientImpact() throws {
        let data = CalibrationStep.sequence.map { step in
            let expected = step.activity.expectedContacts == 2 ? [2.8, 3.05] : [2.8]
            return trial(step, contacts: [2.0] + expected, amplitude: 0.08)
        }
        XCTAssertNil(try CalibrationEvaluator.candidate(from: data))
    }

    func testPairsMustHaveValidTimingNotJustTwoContacts() throws {
        let badPair = trial(.init(.knockPair, .verification), contacts: [2.7, 3.4])
        let score = try CalibrationEvaluator.score(badPair, floor: 0.008)
        XCTAssertEqual(score.matched, 2); XCTAssertEqual(score.pairs, 0); XCTAssertFalse(score.passed)
    }

    func testSessionRoundTripPreservesProvenanceAndUnconfirmedAttempts() throws {
        var session = CalibrationSession(context: .init(surface: "Desk", placement: "Stand", device: "Synthetic test",
            os: "Test", input: "Test", requestedRate: 800, initialSettings: DetectorSettings()))
        var unconfirmed = trial(.init(.lightTap, .training)); unconfirmed.confirmed = false
        session.trials = [unconfirmed]
        let decoded = try JSONDecoder().decode(CalibrationSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.id, session.id); XCTAssertEqual(decoded.context.placement, "Stand")
        XCTAssertFalse(decoded.trials[0].confirmed); XCTAssertFalse(decoded.verificationPassed)
    }

    func testVerificationCannotPassWithoutIndependentRecordings() {
        let training = CalibrationStep.sequence.filter { $0.partition == .training }.map { trial($0) }
        XCTAssertThrowsError(try CalibrationEvaluator.verify(training, frozenFloor: 0.008))
    }

    func testCalibrationAcceptsTheLiveMinimumAndFitsWeakDeskContacts() throws {
        let light = trial(.init(.lightTap, .training), amplitude: 0.003)
        XCTAssertTrue(try CalibrationEvaluator.score(light, floor: 0.002).passed)
        let data = CalibrationStep.sequence.map { trial($0, amplitude: 0.003) }
        let settings = try XCTUnwrap(CalibrationEvaluator.candidateSettings(from: data))
        XCTAssertLessThan(settings.amplitudeFloor, 0.005)
        XCTAssertTrue(try data.allSatisfy { try CalibrationEvaluator.score($0, settings: settings).passed })
    }

    func testLegacySurfaceMovementSequenceRemainsReplayable() {
        let standard = CalibrationStep.sequence(includingSurfaceBumps: false)
        let tableAware = CalibrationStep.sequence(includingSurfaceBumps: true)
        XCTAssertEqual(standard, CalibrationStep.legacySequence)
        XCTAssertEqual(tableAware.count, standard.count + 2)
        XCTAssertEqual(tableAware.filter { $0.activity == .surfaceBump }.map(\.partition), [.training, .verification])
    }

    func testOlderContextDefaultsToNoSurfaceMovementExercise() throws {
        let context = CalibrationContext(surface: "Desk", placement: "Stand", device: "Test", os: "Test",
            input: "Test", requestedRate: 800, initialSettings: DetectorSettings(), includesSurfaceBumps: true)
        let encoded = try JSONEncoder().encode(context)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "includesSurfaceBumps")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(CalibrationContext.self, from: oldData).includesSurfaceBumps)
    }

    func testOlderDetectorSettingsReceiveSafeShapeDefaults() throws {
        let data = try XCTUnwrap(#"{"sensitivity":2,"suppressTyping":false}"#.data(using: .utf8))
        let settings = try JSONDecoder().decode(DetectorSettings.self, from: data)
        XCTAssertEqual(settings.minimumRiseRate, 1)
        XCTAssertEqual(settings.impulseMinimumRiseRate, 3)
        XCTAssertEqual(settings.maximumPulseDuration, 0.035)
        XCTAssertEqual(settings.maximumTapInterval, 0.45)
        XCTAssertFalse(settings.suppressTyping)
    }

    func testCalibrationLearnsAComfortableLightPairCadence() throws {
        let data = CalibrationStep.sequence.map { step in
            step.activity.expectedContacts == 2
                ? trial(step, contacts: [2.8, 3.42])
                : trial(step)
        }
        let settings = try XCTUnwrap(CalibrationEvaluator.candidateSettings(from: data))
        XCTAssertEqual(settings.maximumTapInterval, 0.7)
        XCTAssertTrue(try data.allSatisfy { try CalibrationEvaluator.score($0, settings: settings).passed })
    }

    func testCalibratedPulseShapeCanRejectSlowSurfaceMotion() throws {
        let step = CalibrationStep(.surfaceBump, .training)
        var recorder = CalibrationRecorder(step: step, started: 10)
        for index in 0..<Int(step.duration * 800) {
            let elapsed = Double(index) / 800
            let local = elapsed - 2.8
            let motion: Double
            if (0..<0.012).contains(local) { motion = 0.018 * local / 0.012 }
            else if (0.012..<0.024).contains(local) { motion = 0.018 * (1 - (local - 0.012) / 0.012) }
            else { motion = 0 }
            recorder.append(.init(time: 10 + elapsed, x: motion, y: 0, z: 1), receivedAt: 10 + elapsed + 0.02)
        }
        var trial = recorder.finish(at: 10 + step.duration + 0.2)
        trial.confirmed = true

        var permissive = DetectorSettings()
        permissive.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        permissive.minimumRiseRate = 1
        permissive.impulseMinimumRiseRate = 1
        XCTAssertGreaterThan(try CalibrationEvaluator.score(trial, settings: permissive).unexpected, 0)

        var rejecting = permissive
        rejecting.minimumRiseRate = 4
        rejecting.impulseMinimumRiseRate = 4
        XCTAssertTrue(try CalibrationEvaluator.score(trial, settings: rejecting).passed)
    }
}
