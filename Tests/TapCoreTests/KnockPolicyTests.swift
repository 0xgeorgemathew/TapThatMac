import XCTest
@testable import TapCore

final class KnockPolicyTests: XCTestCase {
    // A key 300 ms before onset must still prevent a contact.
    func testTypingSuppressesContactForHalfASecond() {
        XCTAssertEqual(detectedContacts(onset: 2, key: 1.7), 0)
    }

    func testTypingAllowsExactHalfSecondBoundary() {
        XCTAssertEqual(detectedContacts(onset: 2, key: 1.5), 1)
    }

    func testKeyDuringCandidatePreventsConfirmation() {
        XCTAssertEqual(detectedContacts(onset: 2, key: 2.005), 0)
    }

    func testSavedDurationOverrideIsPreserved() throws {
        let settings = try JSONDecoder().decode(DetectorSettings.self,
            from: Data(#"{"maximumPulseDuration":0.035}"#.utf8))
        XCTAssertEqual(settings.maximumPulseDuration, 0.035)
    }

    func testFourRapidConfirmedContactsStartBurstSuppression() throws {
        var settings = DetectorSettings(); settings.suppressTyping = false
        let onsets = [2.0, 2.125, 2.25, 2.375, 2.6, 3.1]
        let samples = (0..<2800).map { i in
            let t = Double(i) / 800
            return AccelerationSample(time: t,
                x: onsets.contains { t >= $0 && t < $0 + 0.01 } ? 0.08 : 0, y: 0, z: 1)
        }
        let result = try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings)
        XCTAssertEqual(result.knockTimes.count, 4)
    }

    func testReleaseMustFallBelowFortyPercentOfOriginalTrigger() {
        var detector = KnockDetector(); detector.settings.suppressTyping = false
        var confirmedBeforeRelease = false
        var total = 0
        for i in 0..<1760 {
            let t = Double(i) / 800
            let x: Double = t < 2 ? 0 : t < 2.005 ? 0.08 : t < 2.01 ? 0.16 : t < 2.02 ? 0.05 : 0
            if detector.ingest(.init(time: t, x: x, y: 0, z: 1), lastKeyTime: nil) {
                if t < 2.02 { confirmedBeforeRelease = true }
                total += 1
            }
        }
        XCTAssertFalse(confirmedBeforeRelease)
        XCTAssertEqual(total, 1)
    }

    func testExactReleaseRatioAndDurationBoundaries() {
        let nonzero = PulseReleaseCandidate(onset: 1, initialMagnitude: 1)
        XCTAssertEqual(nonzero.state(feature: 0.4, at: 1.08, maximumDuration: 0.08), .released)
        let pulse = PulseReleaseCandidate(onset: 0, initialMagnitude: 1)
        XCTAssertEqual(pulse.state(feature: 0.4, at: 0.08, maximumDuration: 0.08), .released)
        XCTAssertEqual(pulse.state(feature: 0.4001, at: 0.08, maximumDuration: 0.08), .pending)
        XCTAssertEqual(pulse.state(feature: 0, at: 0.081, maximumDuration: 0.08), .expired)
        XCTAssertEqual(pulse.state(feature: 0, at: 0.036, maximumDuration: 0.035), .expired)
    }

    func testLaterPeakDoesNotRelaxReleaseMagnitude() {
        let pulse = PulseReleaseCandidate(onset: 0, initialMagnitude: 1)
        XCTAssertEqual(pulse.state(feature: 2, at: 0.01, maximumDuration: 0.08), .pending)
        XCTAssertEqual(pulse.state(feature: 0.6, at: 0.02, maximumDuration: 0.08), .pending)
        XCTAssertEqual(pulse.state(feature: 0.4, at: 0.03, maximumDuration: 0.08), .released)
    }

    func testMinimumSpacingAllowsExactBoundaryButNotEarlierContact() {
        var gate = ContactConfirmationGate()
        XCTAssertTrue(gate.accept(onset: 0, confirmedAt: 0.01))
        XCTAssertFalse(gate.accept(onset: 0.119, confirmedAt: 0.129))
        // A rejected spaced echo must not move the spacing reference.
        var boundary = ContactConfirmationGate()
        XCTAssertTrue(boundary.accept(onset: 0, confirmedAt: 0.01))
        XCTAssertTrue(boundary.accept(onset: 0.12, confirmedAt: 0.13))
    }

    func testBurstHistoryIncludesExactHalfSecondBoundary() {
        var gate = ContactConfirmationGate()
        for onset in [0.0, 0.125, 0.25] {
            XCTAssertTrue(gate.accept(onset: onset, confirmedAt: onset + 0.01))
        }
        XCTAssertFalse(gate.accept(onset: 0.5, confirmedAt: 0.51))
    }

    func testOlderOnsetsLeaveTheRollingBurstWindow() {
        var gate = ContactConfirmationGate()
        for onset in [0.0, 0.125, 0.25, 0.501] {
            XCTAssertTrue(gate.accept(onset: onset, confirmedAt: onset + 0.01))
        }
    }

    func testIgnoreDoesNotExtendAndLateReleaseCannotRescueIgnoredOnset() {
        var gate = ContactConfirmationGate()
        for onset in [0.0, 0.125, 0.25] {
            XCTAssertTrue(gate.accept(onset: onset, confirmedAt: onset + 0.01))
        }
        XCTAssertFalse(gate.accept(onset: 0.5, confirmedAt: 0.51))
        XCTAssertFalse(gate.accept(onset: 0.8, confirmedAt: 0.81))
        XCTAssertFalse(gate.accept(onset: 1.2, confirmedAt: 1.22))
        // Fourth confirmation at .51 starts 700 ms ignore; new onset1.21 is allowed.
        XCTAssertTrue(gate.accept(onset: 1.21, confirmedAt: 1.22))
        XCTAssertTrue(gate.accept(onset: 1.34, confirmedAt: 1.35))
        XCTAssertTrue(gate.accept(onset: 1.47, confirmedAt: 1.48))
    }

    func testCrossPathDuplicatesAndUnspacedEchoesDoNotConsumeBurstBudget() {
        var gate = ContactConfirmationGate()
        for onset in [0.0, 0.125, 0.25] {
            XCTAssertTrue(gate.accept(onset: onset, confirmedAt: onset + 0.01))
            XCTAssertFalse(gate.accept(onset: onset + 0.005, confirmedAt: onset + 0.02))
            XCTAssertFalse(gate.accept(onset: onset + 0.115, confirmedAt: onset + 0.12))
        }
        // The above echoes count neither toward spacing nor the rolling budget.
        XCTAssertFalse(gate.accept(onset: 0.5, confirmedAt: 0.51))
        XCTAssertTrue(gate.accept(onset: 1.21, confirmedAt: 1.22))
    }

    func testResetClearsBurstIgnoreHistoryAndSpacing() {
        var gate = ContactConfirmationGate()
        for onset in [0.0, 0.125, 0.25, 0.375] {
            _ = gate.accept(onset: onset, confirmedAt: onset + 0.01)
        }
        gate.reset()
        XCTAssertTrue(gate.accept(onset: 0, confirmedAt: 0.01))
        XCTAssertTrue(gate.accept(onset: 0.125, confirmedAt: 0.135))
        XCTAssertTrue(gate.accept(onset: 0.25, confirmedAt: 0.26))
    }

    func testFutureKeyMarkerBlocksAndExactTypingBoundaryAllowsDelivery() {
        XCTAssertTrue(KnockPolicy.typingBlocks(at: 2, lastKeyTime: 2.1))
        XCTAssertTrue(KnockPolicy.typingBlocks(at: 2.499, lastKeyTime: 2))
        XCTAssertFalse(KnockPolicy.typingBlocks(at: 2.5, lastKeyTime: 2))
        XCTAssertFalse(KnockPolicy.typingBlocks(at: 2, lastKeyTime: nil))
    }

    func testReplayUsesSameTypingBoundaryAsDetector() throws {
        let samples = (0..<2000).map { i in
            let time = Double(i) / 800
            return AccelerationSample(time: time, x: time >= 2 && time < 2.01 ? 0.08 : 0, y: 0, z: 1)
        }
        for (key, expected) in [(1.7, 0), (1.5, 1), (2.005, 0)] {
            let replay = try RecordingReplay.evaluate(samples: samples, keyTimes: [key], settings: DetectorSettings())
            XCTAssertEqual(replay.knockTimes.count, expected)
            XCTAssertEqual(detectedContacts(onset: 2, key: key), expected)
        }
    }

    private func detectedContacts(onset: Double, key: Double) -> Int {
        var detector = KnockDetector()
        var count = 0
        for i in 0..<2000 {
            let time = Double(i) / 800
            let active = time >= onset && time < onset + 0.01
            if detector.ingest(.init(time: time, x: active ? 0.08 : 0, y: 0, z: 1),
                               lastKeyTime: time >= key ? key : nil) { count += 1 }
        }
        return count
    }
}
