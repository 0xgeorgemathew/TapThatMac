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
    func testLightTapProfileRejectsRecordedIncidentalMovement() throws {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: 0.008)
        for name in ["calibration-labeled", "verification-round1"] {
            let url = Bundle.module.url(forResource: name, withExtension: "json")!
            let data = try JSONDecoder().decode(ReplayDataset.self, from: Data(contentsOf: url))
            for recording in data.captures where recording.expectedDoubleKnocks == 0 {
                let result = try RecordingReplay.evaluate(samples: recording.samples, keyTimes: recording.keyTimes ?? [], settings: settings)
                XCTAssertTrue(result.doubleKnockTimes.isEmpty, recording.label)
            }
        }
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
