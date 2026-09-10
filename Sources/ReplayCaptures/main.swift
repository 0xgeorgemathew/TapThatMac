import Foundation
import TapCore

// Each run scores one partition. Tune on Calibration; reserve Verification.
let args = Array(CommandLine.arguments.dropFirst())
guard (3...4).contains(args.count), args[1] == "--purpose", ["Calibration", "Verification"].contains(args[2]) else {
    fputs("Usage: ReplayCaptures <export.json> --purpose Calibration|Verification [sensitivity 0.5...7]\n", stderr)
    exit(2)
}
do {
    var settings = DetectorSettings(); settings.sensitivity = 2
    if args.count == 4 {
        guard let sensitivity = Double(args[3]), sensitivity.isFinite, (0.5...7).contains(sensitivity) else {
            throw NSError(domain: "Replay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sensitivity must be 0.5...7"])
        }
        settings.sensitivity = sensitivity
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: args[0]))
    let dataset = try JSONDecoder().decode(ReplayDataset.self, from: data)
    let captures = dataset.captures.filter { $0.purpose == args[2] }
    guard !captures.isEmpty else {
        throw NSError(domain: "Replay", code: 2, userInfo: [NSLocalizedDescriptionKey: "No recordings in requested partition"])
    }
    var invalid = 0, missed = 0, extra = 0, falseTriggers = 0
    var negativeSeconds = 0.0
    print("\(args[2]); sensitivity \(settings.sensitivity); production detector + router")
    for capture in captures {
        guard !capture.simulated, let expected = capture.expectedDoubleKnocks, expected >= 0,
              let keys = capture.keyTimes, let duration = capture.duration, duration >= 14,
              let first = capture.samples.first, let last = capture.samples.last, last.time - first.time >= 13 else {
            print("UNSCORED \(capture.label): needs a complete real recording, intended count and key timing")
            invalid += 1; continue
        }
        let result = try RecordingReplay.evaluate(samples: capture.samples, keyTimes: keys, settings: settings)
        let actual = result.doubleKnockTimes.count
        if expected == 0 { falseTriggers += actual; negativeSeconds += last.time - first.time }
        else { missed += max(0, expected - actual); extra += max(0, actual - expected) }
        let times = result.doubleKnockTimes.map { String(format: "%.3f", $0 - first.time) }.joined(separator: ", ")
        print("\(actual == expected ? "PASS" : "FAIL") \(capture.label): intended \(expected), detected \(actual); seconds [\(times)]")
    }
    print("Missing intended counts: \(missed); extra positive-recording triggers: \(extra)")
    print("False triggers: \(falseTriggers) over \(String(format: "%.1f", negativeSeconds)) seconds of negative recordings; unscored: \(invalid)")
    print("Counts do not prove event identity. Inspect timestamps; collect more sessions before trusting a profile.")
    exit(invalid > 0 ? 2 : (missed + extra + falseTriggers > 0 ? 1 : 0))
} catch {
    fputs("Replay failed: \(error.localizedDescription)\n", stderr); exit(2)
}
