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
        recorder.cue(at: 3); recorder.endResponse(at: 5); recorder.key(at: 3.2)
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

    func testCompleteFreshTrainingAndIndependentVerification() throws {
        let data = CalibrationStep.sequence.map { trial($0) }
        let floor = try XCTUnwrap(CalibrationEvaluator.candidate(from: data))
        XCTAssertTrue(try CalibrationEvaluator.verify(data, frozenFloor: floor))
        // A failed holdout must not change the candidate fitted on training.
        var failed = data
        failed[10] = trial(CalibrationStep.sequence[10], contacts: [])
        XCTAssertEqual(try CalibrationEvaluator.candidate(from: failed), floor)
        XCTAssertFalse(try CalibrationEvaluator.verify(failed, frozenFloor: floor))
    }

    func testMissingAndDuplicateStepsCannotQualify() {
        let data = CalibrationStep.sequence.map { trial($0) }
        XCTAssertThrowsError(try CalibrationEvaluator.candidate(from: Array(data.dropFirst())))
        XCTAssertThrowsError(try CalibrationEvaluator.candidate(from: data + [data[0]]))
        XCTAssertThrowsError(try CalibrationEvaluator.verify(Array(data.dropLast()), frozenFloor: 0.008))
    }

    func testNoCandidateWhenNoiseAndContactsAreIndistinguishable() throws {
        let data = CalibrationStep.sequence.map { step in
            trial(step, contacts: step.activity.expectedContacts == 0 ? [3] : nil, amplitude: 0.08)
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
}
