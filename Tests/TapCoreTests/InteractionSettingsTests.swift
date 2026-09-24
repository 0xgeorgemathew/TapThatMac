import XCTest
@testable import TapCore
final class InteractionSettingsTests: XCTestCase {
    func testSamplingRangeIncludesOneHz() {
        XCTAssertTrue(SamplingRate.options.contains(1))
        XCTAssertEqual(SamplingRate.intervalMicroseconds(for: 1), 1_000_000)
        XCTAssertEqual(SamplingRate.intervalMicroseconds(for: 200), 5000)
    }
    func testLightTapThreshold() {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.005)
        XCTAssertEqual(settings.amplitudeFloor, 0.005, accuracy: 0.000001)
    }
    func testLightTapPairIsRecognizedAtLowerThreshold() throws {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        let samples = (0..<4000).map { index in
            let t = Double(index) / 1000
            let tap = (t >= 2 && t < 2.012) || (t >= 2.25 && t < 2.262)
            return AccelerationSample(time: t, x: tap ? 0.012 : 0, y: 0, z: 1)
        }
        XCTAssertEqual(try RecordingReplay.evaluate(samples: samples, keyTimes: [], settings: settings).doubleKnockTimes.count, 1)
    }
    func testOneHzMonitoringCanFinishWarmup() {
        var detector = KnockDetector()
        for time in 0...4 {
            _ = detector.ingest(AccelerationSample(time: Double(time), x: 0, y: 0, z: 1), lastKeyTime: nil, maximumSampleGap: 3)
        }
        XCTAssertFalse(detector.warmingUp)
    }
    func testSnappyTripleWindowDoesNotExecuteDoubleEarly() {
        var router = GestureRouter(recognizesTriples: true, tripleInterval: 0.3)
        _ = router.knock(at: 1); _ = router.knock(at: 1.2)
        XCTAssertNil(router.advance(to: 1.49))
        XCTAssertEqual(router.knock(at: 1.49), [.triple])
    }
    func testSnappyDoubleCompletesAfter300Milliseconds() {
        var router = GestureRouter(recognizesTriples: true, tripleInterval: 0.3)
        _ = router.knock(at: 1); _ = router.knock(at: 1.2)
        XCTAssertEqual(router.advance(to: 1.51), .double)
    }
}

final class AssistantControlsTests: XCTestCase {
    func testApprovalRequiresBothControlsAndNeverMatchesSend() {
        XCTAssertNil(AssistantControls.match(.accept, labels: [["Send"]]))
        XCTAssertNil(AssistantControls.match(.accept, labels: [["Approve"]]))
        XCTAssertEqual(AssistantControls.match(.accept, labels: [["Approve"], ["Reject"]]), 0)
        XCTAssertEqual(AssistantControls.match(.reject, labels: [["Approve"], ["Reject"]]), 1)
    }
    func testAmbiguousApprovalsAreRejected() {
        XCTAssertNil(AssistantControls.match(.accept, labels: [["Approve"], ["Approve once"], ["Reject"]]))
    }
    func testDictationIsBlockedByApprovalPrompt() {
        XCTAssertNil(AssistantControls.match(.dictation, labels: [["Approve"], ["Reject"], ["Start dictation"]]))
        XCTAssertEqual(AssistantControls.match(.dictation, labels: [["Start dictation"]]), 0)
    }
    func testOnlyExactChatGPTHostIsAllowed() {
        XCTAssertTrue(AssistantControls.isChatGPTPage("https://chatgpt.com/c/123"))
        XCTAssertFalse(AssistantControls.isChatGPTPage("https://chatgpt.com.evil.example"))
        XCTAssertFalse(AssistantControls.isChatGPTPage("https://example.com/?next=chatgpt.com"))
        XCTAssertFalse(AssistantControls.isChatGPTPage("http://chatgpt.com"))
    }
}

final class BaselineInteractionTests: XCTestCase {
    func testDoubleRespondsOnSecondTapWithoutThirdTapWait() {
        var router = GestureRouter()
        XCTAssertEqual(router.knock(at: 1), [])
        XCTAssertEqual(router.knock(at: 1.2), [.double])
        XCTAssertEqual(router.knock(at: 1.4), [])
        XCTAssertEqual(router.advance(to: 1.86), .single)
        XCTAssertEqual(router.knock(at: 2), [])
        XCTAssertEqual(router.knock(at: 2.2), [.double])
    }
    func testEveryBlockingSettingIsExplicitAndRecordingDoesNotChangeEnabledPreference() {
        func reason(_ flags: [Bool]) -> String? {
            ActionAvailability.blockReason(calibration: flags[0], settingsOpen: flags[1],
                simulated: flags[2], paused: flags[3], inactive: flags[4],
                recording: flags[5], enabled: !flags[6], monitoringOnly: flags[7])
        }
        let ready = Array(repeating: false, count: 8)
        XCTAssertNil(reason(ready))
        for index in ready.indices {
            var blocked = ready; blocked[index] = true
            XCTAssertNotNil(reason(blocked), "Blocker \(index)")
        }
        var recording = ready; recording[5] = true
        XCTAssertEqual(reason(recording), "Recording: actions paused")
        recording[5] = false
        XCTAssertNil(reason(recording))
    }
    func testScreenshotApprovalLabelsAreRecognized() {
        XCTAssertEqual(AssistantControls.match(.accept, labels: [["Deny"], ["Allow once"]]), 1)
        XCTAssertEqual(AssistantControls.match(.reject, labels: [["Deny"], ["Allow once"]]), 0)
        XCTAssertNil(AssistantControls.match(.accept, labels: [["Deny", "Allow once"]]))
    }
}

final class RingNavigationTests: XCTestCase {
    func testDelayedSensorDeliveryDoesNotExpireSecondTap() {
        var router = GestureRouter()
        XCTAssertEqual(router.knock(at: 2), [])
        // Wall time has passed the deadline, but the latest sensor batch has not.
        XCTAssertNil(router.advance(wallTime: 2.50, processedSensorTime: 2.44))
        XCTAssertEqual(router.knock(at: 2.43), [.double])
        XCTAssertNil(router.advance(wallTime: 2.6, processedSensorTime: 2.6))
    }

    func testUnconfirmedPulseNearDeadlineDoesNotBecomeSingle() {
        var router = GestureRouter()
        _ = router.knock(at: 2)
        XCTAssertNil(router.advance(wallTime: 2.47, processedSensorTime: 2.47))
        XCTAssertEqual(router.knock(at: 2.445), [.double])
    }

    func testSlowThresholdCrossingDoesNotSwallowFollowingSharpTap() {
        var detector = KnockDetector()
        detector.settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.02)
        var onsets: [Double] = []
        for index in 0..<2400 {
            let t = Double(index) / 800
            // A slow swell crosses the floor, followed by a real contact before
            // the chassis has returned to quiet. Repeat as a double tap.
            var x = 0.0
            for start in [2.0, 2.25] {
                let age = t - start
                if age >= 0 && age < 0.03 { x += age * 0.9 }
                if age >= 0.03 && age < 0.042 { x += 0.06 }
            }
            if detector.ingest(AccelerationSample(time: t, x: x, y: 0, z: 1), lastKeyTime: nil) {
                onsets.append(detector.acceptedOnset)
            }
        }
        XCTAssertEqual(onsets.count, 2)
        if onsets.count == 2 { XCTAssertEqual(onsets[1] - onsets[0], 0.25, accuracy: 0.005) }
    }

    func testBothDirectionsVisitEveryActionAndWrap() {
        for step in [-1, 1] {
            var selected = Command.playPause
            var visited: Set<Command> = []
            for _ in Command.allCases {
                visited.insert(selected)
                selected = Command.advancing(selected, by: step)
            }
            XCTAssertEqual(visited, Set(Command.allCases))
            XCTAssertEqual(selected, .playPause)
        }
        XCTAssertEqual(Command.advancing(nil, by: 1), Command.allCases.first)
        XCTAssertEqual(Command.advancing(nil, by: -1), Command.allCases.last)
    }

    func testEveryRingActionCanBeAssignedToDoubleTap() {
        XCTAssertEqual(Set(DoubleTapAction.allCases.compactMap(\.command)), Set(Command.allCases))
        XCTAssertNil(DoubleTapAction.ring.command)
    }

    func testLegacyPreferencesMigrateWithoutChangingAction() {
        func restore(_ preset: Preset, _ command: Command? = nil, _ intent: AssistantIntent? = nil) -> DoubleTapAction {
            .restored(saved: nil, preset: preset.rawValue, quickAction: command?.rawValue, assistantIntent: intent?.rawValue)
        }
        XCTAssertEqual(restore(.doubleTapLock), .lock)
        XCTAssertEqual(restore(.quickAction, .lock), .lock)
        XCTAssertEqual(restore(.quickAction, .playPause), .playPause)
        XCTAssertEqual(restore(.commandRing), .ring)
        XCTAssertEqual(restore(.assistant, nil, .accept), .approve)
        XCTAssertEqual(restore(.assistant, nil, .reject), .reject)
        XCTAssertEqual(restore(.assistant, nil, .dictation), .dictation)
        XCTAssertEqual(DoubleTapAction.restored(saved: "Next Track", preset: "Double-tap Lock", quickAction: nil, assistantIntent: nil), .next)
        XCTAssertEqual(DoubleTapAction.restored(saved: "invalid", preset: nil, quickAction: nil, assistantIntent: nil), .lock)
    }

    func testOpenNavigateAndConfirmWithConsecutivePairs() {
        var router = GestureRouter()
        var selected = Command.playPause
        XCTAssertEqual(router.knock(at: 1), [])
        XCTAssertEqual(router.knock(at: 1.2), [.double])
        router.consumeOpening(at: 1.2)
        // A second pair can choose the initial selection without a hover or single tap.
        XCTAssertEqual(router.knock(at: 1.4), [])
        XCTAssertEqual(router.knock(at: 1.6), [.double])
        XCTAssertEqual(selected, .playPause)
        router.consumeOpening(at: 1.6)
        XCTAssertEqual(router.knock(at: 2), [])
        XCTAssertEqual(router.advance(to: 2.46), .single)
        selected = Command.advancing(selected, by: 1)
        XCTAssertEqual(router.knock(at: 2.6), [])
        XCTAssertEqual(router.knock(at: 2.8), [.double])
        XCTAssertEqual(selected, .next)
    }

    func testLightSensorTapsNavigateFullCircleThenConfirm() {
        for sampleRate in [100, 800] {
            var detector = KnockDetector()
            detector.settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
            var router = GestureRouter()
            let navigationTimes = Command.allCases.indices.map { 3.0 + Double($0) * 0.7 }
            let confirmTime = navigationTimes.last! + 0.8
            let tapTimes = [2.0, 2.25] + navigationTimes + [confirmTime, confirmTime + 0.25]
            var selected = Command.playPause
            var opened = false
            var moves = 0
            var choices: [Command] = []
            func route(_ event: GestureEvent) {
                if event == .single, opened {
                    selected = Command.advancing(selected, by: 1)
                    moves += 1
                } else if event == .double {
                    if opened { choices.append(selected) }
                    else { opened = true }
                }
            }
            for index in 0..<Int((confirmTime + 1) * Double(sampleRate)) {
                let time = Double(index) / Double(sampleRate)
                let contact = tapTimes.contains { time >= $0 && time < $0 + 0.012 }
                let sample = AccelerationSample(time: time, x: contact ? 0.012 : 0, y: 0, z: 1)
                if detector.ingest(sample, lastKeyTime: nil) {
                    for event in router.knock(at: detector.acceptedOnset) { route(event) }
                }
                if let event = router.advance(to: time - 0.04) { route(event) }
            }
            XCTAssertTrue(opened, "\(sampleRate) Hz")
            XCTAssertEqual(moves, Command.allCases.count, "\(sampleRate) Hz")
            XCTAssertEqual(choices, [.playPause], "\(sampleRate) Hz")
        }
    }

    func testDoubleChoosesWithoutFirstProducingNavigation() {
        var router = GestureRouter()
        router.consumeOpening(at: 1)
        XCTAssertEqual(router.knock(at: 1.5), [])
        XCTAssertNil(router.advance(to: 1.7))
        XCTAssertEqual(router.knock(at: 1.75), [.double])
        XCTAssertNil(router.advance(to: 2.3))
        XCTAssertEqual(router.knock(at: 2.5), [])
        XCTAssertEqual(router.advance(to: 2.96), .single)
    }
}
