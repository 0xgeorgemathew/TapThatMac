import Foundation
import TapCore

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 1 else {
    fputs("Usage: ReplayCaptures <fresh-calibration-session.json>\n", stderr)
    exit(2)
}
do {
    let url = URL(fileURLWithPath: args[0])
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 64_000_000 else { throw CalibrationError.invalidTrial }
    let session = try JSONDecoder().decode(CalibrationSession.self, from: Data(contentsOf: url))
    guard session.trials.count <= 48 else { throw CalibrationError.incomplete }
    let steps = session.schemaVersion >= 3
        ? CalibrationStep.sequence
        : CalibrationStep.sequence(includingSurfaceBumps: session.context.includesSurfaceBumps)
    let settings: DetectorSettings
    if session.schemaVersion == 4, session.detectorVersion == "light-impulse-profile-v4",
       session.finished, let frozen = session.candidateSettings {
        guard try CalibrationEvaluator.candidateSettings(from: session.trials, expectedSteps: steps) == frozen else {
            throw CalibrationError.invalidTrial
        }
        settings = frozen
    } else if session.schemaVersion == 3, session.detectorVersion == "four-gesture-profile-v3",
       session.finished, let frozen = session.candidateSettings {
        guard try CalibrationEvaluator.candidateSettings(from: session.trials, expectedSteps: steps) == frozen else {
            throw CalibrationError.invalidTrial
        }
        settings = frozen
    } else if session.schemaVersion == 2, session.detectorVersion == "dual-pulse-profile-v2",
       let frozen = session.candidateSettings {
        guard try CalibrationEvaluator.candidateSettings(from: session.trials, expectedSteps: steps) == frozen else {
            throw CalibrationError.invalidTrial
        }
        settings = frozen
    } else if session.schemaVersion == 1, session.detectorVersion == "dual-pulse-v1",
              let floor = session.candidateFloor {
        guard try CalibrationEvaluator.candidate(from: session.trials) == floor else { throw CalibrationError.invalidTrial }
        var legacy = DetectorSettings()
        legacy.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: floor)
        settings = legacy
    } else {
        throw CalibrationError.incomplete
    }
    for trial in session.trials where trial.confirmed {
        let score = try CalibrationEvaluator.score(trial, settings: settings)
        print("\(trial.step.partition.rawValue) | \(trial.step.activity.title): \(score.passed ? "PASS" : "FAIL"); contacts \(score.matched)/\(score.expected), unexpected \(score.unexpected), pairs \(score.pairs)")
    }
    let passed = try CalibrationEvaluator.verify(session.trials, frozenSettings: settings, expectedSteps: steps)
    print("Frozen profile: \(settings.amplitudeFloor) g floor, \(Int(settings.maximumPulseDuration * 1_000)) ms pulse. Verification: \(passed ? "passed" : "failed").")
    print("Labels are user-confirmed cue windows, not precise contact timestamps or a real-world accuracy guarantee.")
    exit(passed ? 0 : 1)
} catch {
    fputs("Replay failed: \(error.localizedDescription)\nOnly fresh guided calibration sessions are supported; old count-only datasets are not accepted.\n", stderr)
    exit(2)
}
