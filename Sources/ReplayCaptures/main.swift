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
    guard session.schemaVersion == 1, session.detectorVersion == "dual-pulse-v1",
          session.trials.count <= 48, let floor = session.candidateFloor else { throw CalibrationError.incomplete }
    let selected = try CalibrationEvaluator.candidate(from: session.trials)
    guard selected == floor else { throw CalibrationError.invalidTrial }
    for trial in session.trials where trial.confirmed {
        let score = try CalibrationEvaluator.score(trial, floor: floor)
        print("\(trial.step.partition.rawValue) | \(trial.step.activity.title): \(score.passed ? "PASS" : "FAIL"); contacts \(score.matched)/\(score.expected), unexpected \(score.unexpected), pairs \(score.pairs)")
    }
    let passed = try CalibrationEvaluator.verify(session.trials, frozenFloor: floor)
    print("Frozen floor: \(floor) g. Verification: \(passed ? "passed" : "failed").")
    print("Labels are user-confirmed cue windows, not precise contact timestamps or a real-world accuracy guarantee.")
    exit(passed ? 0 : 1)
} catch {
    fputs("Replay failed: \(error.localizedDescription)\nOnly fresh guided calibration sessions are supported; old count-only datasets are not accepted.\n", stderr)
    exit(2)
}
