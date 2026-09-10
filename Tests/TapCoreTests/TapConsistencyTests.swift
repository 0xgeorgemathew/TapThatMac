import XCTest
@testable import TapCore

final class TapConsistencyTests: XCTestCase {
    // An impact's location changes its strength, polarity and mechanical decay.
    // Every sequence represents the same four deliberate pairs, not extra echoes.
    func testAsymmetricPairsAcrossAxesAndDecay() throws {
        for axis in 0..<3 {
            for decay in [0.015, 0.035, 0.055] {
                for second in [0.015, 0.03, 0.06] {
                    let samples = makePairs(axis: axis, decay: decay, second: second)
                    var settings = DetectorSettings()
                    settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
                    let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
                    XCTAssertEqual(result.knockTimes.count, 8, "axis=\(axis) decay=\(decay) second=\(second)")
                    XCTAssertEqual(result.doubleKnockTimes.count, 4, "axis=\(axis) decay=\(decay) second=\(second)")
                }
            }
        }
    }

    func testPairTimingUsesImpactOnsetsRatherThanDifferentTailLengths() throws {
        var settings = DetectorSettings(); settings.sensitivity = 2
        let samples = (0..<3200).map { index in
            let time = Double(index) / 800
            let active = (time >= 2 && time < 2.012) || (time >= 2.44 && time < 2.472)
            return AccelerationSample(time: time, x: active ? 0.08 : 0, y: 0, z: 1)
        }
        let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
        XCTAssertEqual(result.knockTimes.count, 2)
        XCTAssertEqual(result.doubleKnockTimes.count, 1)
    }

    func testLightModePreservesPreviouslyDetectedChassisCaptures() throws {
        let url = Bundle.module.url(forResource: "calibration-labeled", withExtension: "json")!
        let dataset = try JSONDecoder().decode(ReplayDataset.self, from: Data(contentsOf: url))
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        for index in [1, 2, 5] {
            let c = dataset.captures[index]
            let result = try RecordingReplay.evaluate(samples: c.samples, keyTimes: c.keyTimes ?? [], settings: settings)
            XCTAssertFalse(result.doubleKnockTimes.isEmpty, "Capture \(index)")
        }
    }

    func testOneRingingContactNeverBecomesAPairAcrossFrequencies() throws {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        for frequency in [20.0, 35, 70, 120] {
            for decay in [0.03, 0.06, 0.12, 0.2] {
                let samples = (0..<4000).map { index in
                    let time = Double(index) / 800
                    let t = time - 2
                    let impact = t < 0 ? 0 : 0.15 * exp(-t / decay) * cos(2 * .pi * frequency * t)
                    return AccelerationSample(time: time, x: impact, y: 0, z: 1)
                }
                let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
                XCTAssertTrue(result.doubleKnockTimes.isEmpty, "frequency=\(frequency) decay=\(decay)")
            }
        }
    }

    private func makePairs(axis: Int, decay: Double, second: Double) -> [AccelerationSample] {
        let onsets = [2.0, 2.2, 2.8, 3.0, 3.6, 3.8, 4.4, 4.6]
        return (0..<4800).map { index in
            let time = Double(index) / 800
            var impact = 0.0
            for (i, onset) in onsets.enumerated() {
                let elapsed = time - onset
                if elapsed >= 0 {
                    let strength = i % 2 == 0 ? 0.06 : second
                    impact += strength * min(1, elapsed / 0.003) * exp(-elapsed / decay)
                }
            }
            return AccelerationSample(time: time, x: axis == 0 ? impact : 0,
                y: axis == 1 ? -impact : 0, z: 1 + (axis == 2 ? impact : 0))
        }
    }
}
