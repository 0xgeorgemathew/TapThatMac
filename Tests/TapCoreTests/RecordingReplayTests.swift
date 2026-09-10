import XCTest
@testable import TapCore

final class RecordingReplayTests: XCTestCase {
    func testQuietRecordingHasNoDoubleKnocks() throws {
        let result = try RecordingReplay.evaluate(samples: samples(), keyTimes: [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0)
    }

    func testTwoBriefImpactsProduceOneDoubleKnock() throws {
        let result = try RecordingReplay.evaluate(samples: samples(impacts: [2, 2.25]), keyTimes: [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 1)
    }

    func testThreeImpactsProduceTripleWithoutDoubleInAppMode() throws {
        let result = try RecordingReplay.evaluate(samples: samples(impacts: [2, 2.25, 2.5]), keyTimes: [], settings: settings, recognizesTriples: true)
        XCTAssertEqual(result.tripleKnockTimes.count, 1)
        XCTAssertTrue(result.doubleKnockTimes.isEmpty)
    }

    func testRealVerificationRecordingsWithTripleRecognition() throws {
        let url = Bundle.module.url(forResource: "verification-round1", withExtension: "json")!
        let dataset = try JSONDecoder().decode(ReplayDataset.self, from: Data(contentsOf: url))
        for recording in dataset.captures {
            let result = try RecordingReplay.evaluate(samples: recording.samples, keyTimes: recording.keyTimes ?? [], settings: settings, recognizesTriples: true)
            XCTAssertEqual(result.doubleKnockTimes.count, recording.expectedDoubleKnocks)
            XCTAssertTrue(result.tripleKnockTimes.isEmpty)
        }
    }

    func testSingleImpactDoesNotProduceDoubleKnock() throws {
        let result = try RecordingReplay.evaluate(samples: samples(impacts: [2]), keyTimes: [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0)
    }

    func testTypingSuppressesNearbyImpacts() throws {
        let result = try RecordingReplay.evaluate(samples: samples(impacts: [2, 2.25]), keyTimes: [1.98, 2.23], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0)
    }

    func testWarmupDoesNotTrigger() throws {
        let result = try RecordingReplay.evaluate(samples: samples(impacts: [0.2, 0.45]), keyTimes: [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0)
    }

    func testReplayRejectsEmptyAndUnorderedSamples() {
        XCTAssertThrowsError(try RecordingReplay.evaluate(samples: [], keyTimes: [], settings: settings))
        var input = samples()
        input.swapAt(10, 11)
        XCTAssertThrowsError(try RecordingReplay.evaluate(samples: input, keyTimes: [], settings: settings))
    }

    func testDatasetRequiresGroundTruthInsteadOfUsingDetectorCount() throws {
        let json = """
        {"captures":[{"label":"Desk knocks","purpose":"Calibration","simulated":false,"samples":[],"knocks":12}]}
        """
        let dataset = try JSONDecoder().decode(ReplayDataset.self, from: Data(json.utf8))
        XCTAssertNil(dataset.captures[0].expectedDoubleKnocks)
    }

    func testSustainedShakeMustNotTrigger() throws {
        let input = (0..<4000).map { index in
            let t = Double(index) / 1000
            let shaking = t >= 2 && t < 3.8
            return AccelerationSample(time: t, x: shaking ? 0.08 * sin(2 * .pi * 5 * (t - 2)) : 0, y: 0, z: 1)
        }
        let result = try RecordingReplay.evaluate(samples: input, keyTimes: [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0, "Smooth periodic movement is not an intentional double-tap")
    }

    func testSingleRingingImpactDoesNotBecomeDoubleTap() throws {
        let input = (0..<4000).map { index in
            let t = Double(index) / 1000
            let dt = t - 2
            let x = dt >= 0 ? 0.15 * exp(-dt / 0.12) * cos(2 * .pi * 70 * dt) : 0
            return AccelerationSample(time: t, x: x, y: 0, z: 1)
        }
        let result = try RecordingReplay.evaluate(samples: input, keyTimes: [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0)
    }

    func testRecordedTypingHasNoFalseDoubleTaps() throws {
        let dataset = try loadRecordings()
        let recording = dataset.captures.last!
        XCTAssertEqual(recording.label, "Typing")
        let result = try RecordingReplay.evaluate(samples: recording.samples, keyTimes: recording.keyTimes ?? [], settings: settings)
        XCTAssertEqual(result.doubleKnockTimes.count, 0)
    }

    func testPreviouslyRecognizedRealTapRecordingsRemainDetectable() throws {
        let dataset = try loadRecordings()
        // Recording 4 was already missed by the baseline. Counts and exact tap
        // times are not independently annotated, so do not force a count of 1.
        for index in [0, 1, 2, 3, 5] {
            let recording = dataset.captures[index]
            let result = try RecordingReplay.evaluate(samples: recording.samples, keyTimes: recording.keyTimes ?? [], settings: settings)
            XCTAssertFalse(result.doubleKnockTimes.isEmpty, "Lost tap recording \(index)")
        }
    }

    private func loadRecordings() throws -> ReplayDataset {
        let url = Bundle.module.url(forResource: "calibration-labeled", withExtension: "json")!
        return try JSONDecoder().decode(ReplayDataset.self, from: Data(contentsOf: url))
    }

    func testFreshDeskTapAndIncidentalMovementRecordings() throws {
        let url = Bundle.module.url(forResource: "verification-round1", withExtension: "json")!
        let dataset = try JSONDecoder().decode(ReplayDataset.self, from: Data(contentsOf: url))
        for (index, recording) in dataset.captures.enumerated() {
            let result = try RecordingReplay.evaluate(samples: recording.samples, keyTimes: recording.keyTimes ?? [], settings: settings)
            XCTAssertEqual(result.doubleKnockTimes.count, recording.expectedDoubleKnocks, "Recording \(index): \(recording.label)")
        }
    }

    private var settings: DetectorSettings {
        var settings = DetectorSettings(); settings.sensitivity = 2
        return settings
    }

    private func samples(impacts: [Double] = []) -> [AccelerationSample] {
        (0..<4000).map { index in
            let t = Double(index) / 1000
            let impact = impacts.contains { t >= $0 && t < $0 + 0.012 }
            return AccelerationSample(time: t, x: impact ? 0.08 : 0, y: 0, z: 1)
        }
    }
}
