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
        guard trial.confirmed, trial.quality.usable, floor.isFinite, (DetectorSettings.minimumAmplitudeFloor...DetectorSettings.maximumAmplitudeFloor).contains(floor) else {
            throw CalibrationError.invalidTrial
        }
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: floor)
        return try score(trial, settings: settings)
    }

    public static func score(_ trial: CalibrationTrial, settings: DetectorSettings) throws -> CalibrationScore {
        guard trial.confirmed, trial.quality.usable,
              settings.amplitudeFloor.isFinite,
              (DetectorSettings.minimumAmplitudeFloor...DetectorSettings.maximumAmplitudeFloor).contains(settings.amplitudeFloor),
              (0.5...20).contains(settings.minimumRiseRate),
              (1...30).contains(settings.impulseMinimumRiseRate),
              (0.018...0.05).contains(settings.maximumPulseDuration),
              (0.3...0.8).contains(settings.maximumTapInterval) else {
            throw CalibrationError.invalidTrial
        }
        var settings = settings
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
        try candidateSettings(from: trials)?.amplitudeFloor
    }

    public static func candidateSettings(
        from trials: [CalibrationTrial],
        expectedSteps: [CalibrationStep]? = nil
    ) throws -> DetectorSettings? {
        let training = trials.filter { $0.step.partition == .training && $0.confirmed }
        let steps = expectedSteps ?? CalibrationStep.sequence
        guard training.map(\.step) == steps.filter({ $0.partition == .training }) else {
            throw CalibrationError.incomplete
        }
        // Prefer the highest floor, then the strongest declared shape
        // profile that still preserves every independently labelled contact. Keep
        // this list deliberately small: a short session cannot justify a broad grid.
        let floors = [0.07, 0.05, 0.035, 0.025, 0.02, 0.0175, 0.014, 0.011, 0.008, 0.006, 0.005, 0.004, 0.003, 0.002]
        let shapes = [
            (maximumDuration: 0.022, envelopeRise: 8.0, impulseRise: 12.0),
            (maximumDuration: 0.028, envelopeRise: 8.0, impulseRise: 12.0),
            (maximumDuration: 0.028, envelopeRise: 4.0, impulseRise: 8.0),
            (maximumDuration: 0.035, envelopeRise: 4.0, impulseRise: 8.0),
            (maximumDuration: 0.035, envelopeRise: 2.0, impulseRise: 5.0),
            (maximumDuration: 0.035, envelopeRise: 1.0, impulseRise: 3.0)
        ]
        let tapIntervals = [0.45, 0.55, 0.7]
        for floor in floors {
            for shape in shapes {
                for tapInterval in tapIntervals {
                    var settings = DetectorSettings()
                    settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: floor)
                    settings.minimumRiseRate = shape.envelopeRise
                    settings.impulseMinimumRiseRate = shape.impulseRise
                    settings.maximumPulseDuration = shape.maximumDuration
                    settings.maximumTapInterval = tapInterval
                    if try training.allSatisfy({ try score($0, settings: settings).passed }) {
                        return settings
                    }
                }
            }
        }
        return nil
    }

    public static func verify(_ trials: [CalibrationTrial], frozenFloor: Double) throws -> Bool {
        var settings = DetectorSettings()
        settings.sensitivity = DetectorSettings.sensitivity(forAmplitudeFloor: frozenFloor)
        return try verify(trials, frozenSettings: settings)
    }

    public static func verify(
        _ trials: [CalibrationTrial],
        frozenSettings: DetectorSettings,
        expectedSteps: [CalibrationStep]? = nil
    ) throws -> Bool {
        let verification = trials.filter { $0.step.partition == .verification && $0.confirmed }
        let steps = expectedSteps ?? CalibrationStep.sequence
        guard !verification.isEmpty,
              verification.map(\.step) == steps.filter({ $0.partition == .verification }) else {
            throw CalibrationError.incomplete
        }
        return try verification.allSatisfy { try score($0, settings: frozenSettings).passed }
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
