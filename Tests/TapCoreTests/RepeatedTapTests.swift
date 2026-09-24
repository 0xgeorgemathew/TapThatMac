import XCTest
@testable import TapCore

final class RepeatedTapTests: XCTestCase {
    func testRepeatedPairsDoNotLoseFirstTapAfterPreviousPair() {
        var router = GestureRouter()
        for start in [1.0, 1.5, 2.0, 2.5] {
            XCTAssertTrue(router.knock(at: start).isEmpty)
            XCTAssertEqual(router.knock(at: start + 0.2), [.double])
            router.consumeOpening(at: start + 0.2)
        }
    }

    func testOpeningStillRejectsImmediateEcho() {
        var router = GestureRouter()
        router.consumeOpening(at: 1)
        XCTAssertTrue(router.knock(at: 1.04).isEmpty)
        XCTAssertNil(router.advance(to: 1.6))
    }

    func testLightThresholdDoesNotTurnRingingOrSmoothShakingIntoPairs() throws {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        for ringing in [true, false] {
            let samples = (0..<4000).map { index in
                let time = Double(index) / 800
                let elapsed = time - 2
                let x = elapsed < 0 ? 0 : (ringing
                    ? 0.15 * exp(-elapsed / 0.12) * cos(2 * .pi * 70 * elapsed)
                    : 0.08 * sin(2 * .pi * 5 * elapsed))
                return AccelerationSample(time: time, x: x, y: 0, z: 1)
            }
            let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
            XCTAssertTrue(result.doubleKnockTimes.isEmpty)
        }
    }

    func testSharpImpactsWithDecayRemainDetectableAtLightThreshold() throws {
        for floor in [0.008] {
            var settings = DetectorSettings()
            settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: floor)
            let onsets = [2.0, 2.22, 2.8, 3.02, 3.6, 3.82, 4.4, 4.62]
            let samples = (0..<4800).map { index in
                let time = Double(index) / 800
                let x = onsets.reduce(0.0) { sum, onset in
                    let elapsed = time - onset
                    return sum + (elapsed >= 0 ? 0.06 * exp(-elapsed / 0.035) : 0)
                }
                return AccelerationSample(time: time, x: x, y: 0, z: 1)
            }
            let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
            XCTAssertEqual(result.knockTimes.count, onsets.count, "Floor \(floor)")
            XCTAssertEqual(result.doubleKnockTimes.count, 4, "Floor \(floor)")
        }
    }

    func testSharpLightPairBelowBroadMotionFloorIsDetected() throws {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        let samples = (0..<3200).map { index in
            let time = Double(index) / 800
            let contact = [2.0, 2.25].contains { time >= $0 && time < $0 + 0.008 }
            return AccelerationSample(time: time, x: contact ? 0.006 : 0, y: 0, z: 1)
        }
        let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
        XCTAssertEqual(result.knockTimes.count, 2)
        XCTAssertEqual(result.doubleKnockTimes.count, 1)
    }

    func testChassisEchoesAroundOneHundredMillisecondsAreCoalesced() throws {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        let contacts = [2.0, 2.096, 2.3, 2.396]
        let samples = (0..<3200).map { index in
            let time = Double(index) / 800
            let contact = contacts.contains { time >= $0 && time < $0 + 0.008 }
            return AccelerationSample(time: time, x: contact ? 0.012 : 0, y: 0, z: 1)
        }
        let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
        XCTAssertEqual(result.knockTimes.count, 2)
        XCTAssertEqual(result.doubleKnockTimes.count, 1)
    }
}
