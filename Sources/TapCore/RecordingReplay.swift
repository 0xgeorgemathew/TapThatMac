import Foundation

public struct ReplayResult {
    public let knockTimes: [Double]
    public let doubleKnockTimes: [Double]
    public let tripleKnockTimes: [Double]
}
public enum ReplayError: Error, LocalizedError {
    case invalidSamples, invalidKeyTimes
    public var errorDescription: String? {
        switch self {
        case .invalidSamples: return "Recording must contain finite, strictly increasing samples."
        case .invalidKeyTimes: return "Key timing markers must be finite and sorted."
        }
    }
}

public enum RecordingReplay {
    // Runs detector + gesture routing only. Never imports AppKit or sends actions.
    // Fixed 50 ms delivery ticks reproduce the app's 40 ms typing grace period.
    public static func evaluate(samples: [AccelerationSample], keyTimes: [Double], settings: DetectorSettings, recognizesTriples: Bool = false) throws -> ReplayResult {
        guard !samples.isEmpty, samples.count <= 100_000,
              samples.last!.time - samples.first!.time <= 60 else { throw ReplayError.invalidSamples }
        var previous = -Double.infinity
        for sample in samples {
            guard sample.time.isFinite, sample.time >= 0, sample.time > previous,
                  sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { throw ReplayError.invalidSamples }
            previous = sample.time
        }
        previous = -Double.infinity
        for key in keyTimes {
            guard key.isFinite, key >= previous else { throw ReplayError.invalidKeyTimes }
            previous = key
        }
        var detector = KnockDetector(); detector.settings = settings
        var router = GestureRouter(recognizesTriples: recognizesTriples,
            maximumInterval: settings.maximumTapInterval)
        var pending: [Double] = []
        var knocks: [Double] = []
        var doubles: [Double] = []
        var triples: [Double] = []
        var lastKey: Double?
        var keyIndex = 0
        var nextTick = samples[0].time
        var lastSample: Double?
        func applyKeys(through time: Double) {
            while keyIndex < keyTimes.count, keyTimes[keyIndex] <= time {
                lastKey = keyTimes[keyIndex]; keyIndex += 1
                if settings.suppressTyping { pending.removeAll(); router.reset() }
            }
        }
        func record(_ event: GestureEvent, at time: Double) {
            switch event {
            case .double: doubles.append(time); router.consumeOpening(at: time)
            case .triple: triples.append(time); router.consumeOpening(at: time)
            default: break
            }
        }
        func tick(at time: Double, flushing: Bool = false) {
            let ready = pending.filter { time - $0 >= 0.04 }
            pending.removeAll { time - $0 >= 0.04 }
            for impact in ready {
                guard !settings.suppressTyping || lastKey.map({ abs(impact - $0) > 0.18 }) != false else { continue }
                knocks.append(impact)
                for event in router.knock(at: impact) {
                    record(event, at: impact)
                }
            }
            let pendingOnset = (pending + (flushing ? [] : [detector.pendingOnset].compactMap { $0 })).min()
            if let event = router.advance(wallTime: time,
                processedSensorTime: flushing ? time : lastSample ?? time,
                pendingOnset: pendingOnset) { record(event, at: time) }
        }
        for sample in samples {
            while nextTick < sample.time {
                applyKeys(through: nextTick); tick(at: nextTick); nextTick += 0.05
            }
            applyKeys(through: sample.time)
            if let previous = lastSample, sample.time - previous > 0.5 {
                detector.reset(); router.reset(); pending.removeAll(); lastKey = nil
            }
            lastSample = sample.time
            if detector.ingest(sample, lastKeyTime: lastKey) { pending.append(detector.acceptedOnset) }
        }
        let end = samples.last!.time + 0.6
        while nextTick <= end {
            applyKeys(through: nextTick); tick(at: nextTick, flushing: true); nextTick += 0.05
        }
        return ReplayResult(knockTimes: knocks, doubleKnockTimes: doubles, tripleKnockTimes: triples)
    }
}
