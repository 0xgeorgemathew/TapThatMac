import XCTest
@testable import TapCore

/// Physical disturbances that once read as a double-tap.
final class FalseDoubleTests: XCTestCase {
    /// A decaying 12-25 Hz desk or chassis ring dips below the release level
    /// near each zero crossing. With a 5 ms re-arm those dips re-armed the
    /// detector and the next half-cycle counted as a second contact.
    func testLowFrequencyNoisyRingIsNotAPair() throws {
        var seed: UInt64 = 42
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.0017
        }
        for floor in [0.002, 0.005, 0.008] {
            for frequency in [12.0, 15, 20, 25] {
                for decay in [0.15, 0.2, 0.3] {
                    var settings = DetectorSettings()
                    settings.suppressTyping = false
                    settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: floor)
                    settings.maximumTapInterval = 0.7
                    let samples = (0..<4800).map { index -> AccelerationSample in
                        let time = Double(index) / 800, t = time - 2
                        let x = t < 0 ? 0 : 0.05 * exp(-t / decay) * sin(2 * .pi * frequency * t)
                        return AccelerationSample(time: time, x: x + noise(), y: noise(), z: 1 + noise())
                    }
                    let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings,
                                                              burstGuard: KnockPolicy.pairBurstGuard)
                    XCTAssertTrue(result.doubleKnockTimes.isEmpty, "floor=\(floor) f=\(frequency) tau=\(decay)")
                }
            }
        }
    }

    /// A bouncing pen or drumming fingers: contacts ~125 ms apart. The pair is
    /// held briefly, so the third contact cancels it before anything runs.
    func testBurstOfContactsIsNotADouble() {
        for times in [[2.0, 2.15, 2.27, 2.36], [2.0, 2.125, 2.25, 2.375]] {
            var router = GestureRouter(burstGuard: KnockPolicy.pairBurstGuard)
            var events: [GestureEvent] = []
            for time in times { events += router.knock(at: time) }
            var clock = times.last!
            while clock < times.last! + 1 {
                clock += 0.05
                if let event = router.advance(to: clock) { events.append(event) }
            }
            XCTAssertFalse(events.contains(.double), "\(times) -> \(events)")
        }
    }

    func testCleanPairsStillFireAfterTheHold() {
        var router = GestureRouter(burstGuard: KnockPolicy.pairBurstGuard)
        var doubles: [Double] = []
        for time in [2.0, 2.25] { XCTAssertTrue(router.knock(at: time).isEmpty) }
        XCTAssertNil(router.advance(to: 2.25 + KnockPolicy.pairBurstGuard - 0.01), "Held during the guard")
        var clock = 2.25
        while clock < 2.9 {
            clock += 0.01
            if router.advance(to: clock) == .double { doubles.append(clock) }
        }
        for time in [3.0, 3.25] { _ = router.knock(at: time) }
        clock = 3.25
        while clock < 3.9 {
            clock += 0.01
            if router.advance(to: clock) == .double { doubles.append(clock) }
        }
        XCTAssertEqual(doubles.count, 2)
        XCTAssertLessThan(doubles[0] - 2.25, KnockPolicy.pairBurstGuard + 0.02)
    }
}
