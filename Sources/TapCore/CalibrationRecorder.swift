import Foundation

/// Bounded raw collection before the production detector's filtering or age gates.
public struct CalibrationRecorder {
    public let step: CalibrationStep
    public let started: Double
    private var samples: [AccelerationSample] = []
    private var keyTimes: [Double] = []
    private var issues: [String] = []
    private var cueTime: Double?
    private var responseEnd: Double?
    private var maximumDelay = 0.0
    private var previousTime: Double?
    private var maximumGap = 0.0

    public init(step: CalibrationStep, started: Double) {
        self.step = step; self.started = started
        samples.reserveCapacity(8500)
    }
    public mutating func flag(_ issue: String) {
        if !issues.contains(issue), issues.count < 16 { issues.append(issue) }
    }
    public mutating func cue(at time: Double) {
        guard cueTime == nil else { return }
        cueTime = time
        if time - (started + 2.5) > 0.15 { flag("The tap prompt was delayed. Please retry.") }
    }
    public mutating func endResponse(at time: Double) {
        guard responseEnd == nil, let cueTime else { return }
        responseEnd = time
        if time - cueTime > 1.65 { flag("The tap prompt stayed on screen too long. Please retry.") }
    }
    public mutating func append(_ sample: AccelerationSample, receivedAt: Double) {
        guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.z.isFinite,
              receivedAt.isFinite else { flag("Invalid sensor values."); return }
        guard sample.time >= started else { return }
        guard sample.time <= started + step.duration else { return }
        if sample.time > receivedAt + 0.01 { flag("Sensor timestamps are ahead of the clock."); return }
        if let previousTime {
            guard sample.time > previousTime else { flag("Sensor timestamps were duplicated or out of order."); return }
            maximumGap = max(maximumGap, sample.time - previousTime)
        }
        previousTime = sample.time
        maximumDelay = max(maximumDelay, receivedAt - sample.time)
        guard samples.count < 12_000 else { flag("The recording reached its sample limit."); return }
        samples.append(sample)
    }
    public mutating func key(at time: Double) {
        guard time.isFinite, time >= started, time <= started + step.duration else { return }
        guard keyTimes.count < 2048 else { flag("Too many keyboard markers."); return }
        keyTimes.append(time)
    }
    public mutating func finish(at time: Double) -> CalibrationTrial {
        let rate: Double
        if let first = samples.first, let last = samples.last, last.time > first.time {
            rate = Double(samples.count - 1) / (last.time - first.time)
            if first.time - started > 0.05 || started + step.duration - last.time > 0.05 {
                flag("The recording is missing its beginning or end.")
            }
        } else { rate = 0; flag("No usable sensor stream was recorded.") }
        // These are collection requirements, not claims of physical detection accuracy.
        if rate < 700 || rate > 900 { flag("Calibration needs a steady sensor stream near 800 Hz.") }
        if maximumGap > 0.02 { flag("Sensor samples were missing during the recording.") }
        if maximumDelay > 0.2 { flag("Sensor delivery was delayed. Close busy apps and retry.") }
        if time < started + step.duration { flag("Recording was interrupted.") }
        if step.activity.expectedContacts > 0 {
            if cueTime == nil || responseEnd == nil { flag("The tap prompt was not completed.") }
            if !keyTimes.isEmpty { flag("Typing overlapped this tap recording. Please retry without typing.") }
        }
        return CalibrationTrial(id: UUID(), step: step, started: started, ended: time,
            cueTime: cueTime, responseEnd: responseEnd, samples: samples, keyTimes: keyTimes,
            quality: CalibrationQuality(measuredRate: rate, maximumGap: maximumGap,
                maximumDeliveryDelay: maximumDelay, issues: issues))
    }
}
