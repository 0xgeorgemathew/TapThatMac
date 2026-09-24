import Foundation

public struct CalibrationScore: Codable {
    public let expected: Int
    public let matched: Int
    public let unexpected: Int
    public let pairs: Int
    public var passed: Bool { matched == expected && unexpected == 0 && pairs == (expected == 2 ? 1 : 0) }
}

public enum CalibrationEvaluator {
    /// No imported examples or detector-generated truth. Evaluate only confirmed fresh trials.
    public static func score(_ trial: CalibrationTrial, floor: Double) throws -> CalibrationScore {
        guard trial.confirmed, trial.quality.usable, floor.isFinite, (0.005...0.07).contains(floor) else {
            throw CalibrationError.invalidTrial
        }
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: floor)
        // A keyboard veto must not conceal a sensor false positive in negative examples.
        settings.suppressTyping = false
        let replay = try RecordingReplay.evaluate(samples: trial.samples, keyTimes: [], settings: settings)
        let expected = trial.step.activity.expectedContacts
        let inWindow = replay.knockTimes.filter { time in
            guard expected > 0, let start = trial.cueTime, let end = trial.responseEnd else { return false }
            return time >= start && time <= end
        }.count
        return CalibrationScore(expected: expected, matched: min(expected, inWindow),
            unexpected: replay.knockTimes.count - min(expected, inWindow), pairs: replay.doubleKnockTimes.count)
    }

    public static func candidate(from trials: [CalibrationTrial]) throws -> Double? {
        let training = trials.filter { $0.step.partition == .training && $0.confirmed }
        guard training.map(\.step) == CalibrationStep.sequence.filter({ $0.partition == .training }) else {
            throw CalibrationError.incomplete
        }
        // Highest qualifying floor gives the largest amplitude rejection margin.
        // Candidates are tried independently; success is not assumed monotonic in sensitivity.
        let floors = [0.07, 0.05, 0.035, 0.025, 0.02, 0.0175, 0.014, 0.011, 0.008, 0.006, 0.005]
        for floor in floors {
            if try training.allSatisfy({ try score($0, floor: floor).passed }) { return floor }
        }
        return nil
    }

    public static func verify(_ trials: [CalibrationTrial], frozenFloor: Double) throws -> Bool {
        let verification = trials.filter { $0.step.partition == .verification && $0.confirmed }
        guard verification.map(\.step) == CalibrationStep.sequence.filter({ $0.partition == .verification }) else {
            throw CalibrationError.incomplete
        }
        return try verification.allSatisfy { try score($0, floor: frozenFloor).passed }
    }
}

public enum CalibrationError: Error, LocalizedError {
    case invalidTrial, incomplete
    public var errorDescription: String? {
        switch self {
        case .invalidTrial: return "This recording has not passed collection checks and user confirmation."
        case .incomplete: return "Complete every calibration step before evaluating the session."
        }
    }
}
