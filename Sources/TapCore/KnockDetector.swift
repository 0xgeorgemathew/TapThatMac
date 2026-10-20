import Foundation

/// Immutable onset measurement: later peaks cannot relax release confirmation.
struct PulseReleaseCandidate {
    let onset: Double
    let initialMagnitude: Double
    enum State { case pending, released, expired }

    func state(feature: Double, at time: Double, maximumDuration: Double) -> State {
        if time > onset + maximumDuration { return .expired }
        return feature <= initialMagnitude * KnockPolicy.releaseRatio ? .released : .pending
    }
}

/// Coalesce paths before spacing/burst accounting. Only spaced confirmations
/// consume the rolling onset budget; suppressed contacts never extend ignore.
struct ContactConfirmationGate {
    private var lastCoalescedOnset = -Double.infinity
    private var lastSpacedOnset = -Double.infinity
    private var recentOnsets: [Double] = []
    private var ignoreUntil = -Double.infinity
    private(set) var rejectionTime = -Double.infinity
    private(set) var rejectionReason = ""

    mutating func reset() { self = Self() }

    mutating func accept(onset: Double, confirmedAt time: Double) -> Bool {
        guard onset >= ignoreUntil, time >= ignoreUntil else {
            rejectionTime = time; rejectionReason = "rapid-contact ignore window"
            return false
        }
        guard onset >= lastCoalescedOnset + KnockPolicy.pathCoalescingInterval else { return false }
        guard onset >= lastSpacedOnset + KnockPolicy.minimumContactSpacing else {
            rejectionTime = time; rejectionReason = "contacts less than 120 ms apart"
            return false
        }
        lastCoalescedOnset = onset
        lastSpacedOnset = onset
        recentOnsets.removeAll { onset > $0 + KnockPolicy.burstWindow }
        recentOnsets.append(onset)
        guard recentOnsets.count < KnockPolicy.burstContactLimit else {
            recentOnsets.removeAll()
            ignoreUntil = time + KnockPolicy.burstIgnoreDuration
            rejectionTime = time; rejectionReason = "four contacts within 500 ms"
            return false
        }
        return true
    }
}

private struct PulseDetector {
    private(set) var acceptedOnset = -Double.infinity
    private(set) var rejectionTime = -Double.infinity
    private(set) var rejectionReason = ""
    public var settings = DetectorSettings()
    public private(set) var feature = 0.0
    public private(set) var threshold = 0.0
    public private(set) var warmingUp = true
    private var gravity: (Double, Double, Double)?
    private var lastTime: Double?
    private var startTime = 0.0
    private var shortAverage = 0.0
    private var baseline = 0.002
    private var latched = false
    private var lastImpact = -Double.infinity
    private var candidate: PulseReleaseCandidate?
    var pendingOnset: Double? { candidate?.onset }
    private var quietSince: Double?

    let impulseMode: Bool
    init(impulseMode: Bool = false) { self.impulseMode = impulseMode }

    public mutating func reset() {
        let saved = settings
        self = PulseDetector(impulseMode: impulseMode)
        settings = saved
    }

    public mutating func ingest(_ sample: AccelerationSample, lastKeyTime: Double?, maximumSampleGap: Double = 0.5) -> Bool {
        guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { return false }
        if let previous = lastTime, sample.time <= previous { return false }
        if let previous = lastTime, sample.time - previous > max(0.5, maximumSampleGap) { reset() }
        guard let g = gravity, let previous = lastTime else {
            gravity = (sample.x, sample.y, sample.z)
            lastTime = sample.time; startTime = sample.time
            return false
        }
        let dt = min(sample.time - previous, 0.1)
        lastTime = sample.time
        let lightTapMode = impulseMode
        // Light contacts need the impulse, not the chassis' long settling tail.
        // A 10 ms high-pass reference removes that tail before detection/rearming.
        // Keep the envelope path at its existing thresholds.
        let slow = 1 - exp(-dt / (lightTapMode ? 0.01 : 0.3))
        gravity = (g.0 + slow * (sample.x - g.0), g.1 + slow * (sample.y - g.1), g.2 + slow * (sample.z - g.2))
        let dx = sample.x - g.0, dy = sample.y - g.1, dz = sample.z - g.2
        let previousFeature = feature
        feature = sqrt(dx * dx + dy * dy + dz * dz)
        let riseRate = (feature - previousFeature) / dt
        shortAverage += (1 - exp(-dt / 0.012)) * (feature - shortAverage)
        // A sharp contact is distinguishable below the broader motion floor: it
        // must also satisfy the stricter impulse rise-rate and duration gates.
        // Keep an absolute guard so increasing sensitivity cannot chase sensor noise.
        let amplitudeFloor = lightTapMode
            ? max(DetectorSettings.minimumAmplitudeFloor * 0.625, settings.amplitudeFloor * 0.625)
            : settings.amplitudeFloor
        threshold = max(amplitudeFloor, baseline * 4.5)
        warmingUp = sample.time - startTime < 1.5
        if warmingUp || feature < threshold {
            baseline += (1 - exp(-dt / (warmingUp ? 0.2 : 1.5))) * (min(feature, threshold) - baseline)
        }
        if feature < threshold * 0.4 {
            if quietSince == nil { quietSince = sample.time }
            if sample.time - quietSince! >= KnockPolicy.rearmQuietDuration { latched = false }
        } else { quietSince = nil }

        if let pending = candidate {
            switch pending.state(feature: feature, at: sample.time,
                                 maximumDuration: settings.maximumPulseDuration) {
            case .expired:
                candidate = nil
                rejectionTime = sample.time
                rejectionReason = "pulse longer than \(Int(settings.maximumPulseDuration * 1_000)) ms"
            case .released:
                candidate = nil
                if settings.suppressTyping, KnockPolicy.typingBlocks(at: sample.time, lastKeyTime: lastKeyTime) { return false }
                acceptedOnset = pending.onset
                return true
            case .pending: break
            }
        }
        // A light pulse can end before the short average reaches contrast.
        // Use instantaneous contrast in the explicitly selected light-tap range;
        // sharp onset, short duration and quiet rearming are still required.
        let contrast = settings.amplitudeFloor < 0.0175 ? feature : shortAverage
        guard !warmingUp, !latched, feature >= threshold,
              contrast / max(baseline, min(0.001, amplitudeFloor / 2.5)) >= 2.5,
              sample.time - lastImpact >= 0.09 else { return false }
        // Confirm a short pulse on its falling edge, then require quiet before
        // rearming. A threshold crossing alone accepts shaking and ring echoes.
        // Slow swells from moving objects can have short threshold crossings.
        // Require a sharp onset as well as a short pulse.
        let minimumRiseRate = lightTapMode ? settings.impulseMinimumRiseRate : settings.minimumRiseRate
        guard riseRate >= minimumRiseRate else {
            rejectionTime = sample.time; rejectionReason = "onset too slow"
            return false
        }
        if settings.suppressTyping, KnockPolicy.typingBlocks(at: sample.time, lastKeyTime: lastKeyTime) { return false }
        // Rejected slow crossings must not disarm a sharper contact that follows
        // while the computer is still moving. Only a candidate starts rearming.
        latched = true; lastImpact = sample.time
        candidate = PulseReleaseCandidate(onset: sample.time, initialMagnitude: feature)
        return false
    }
}


/// Combine the knock envelope with a short impulse path for light
/// contacts. Both describe the same physical impacts; coalesce before pairing.
public struct KnockDetector {
    public var settings = DetectorSettings()
    private var envelope = PulseDetector()
    private var impulse = PulseDetector(impulseMode: true)
    private var confirmationGate = ContactConfirmationGate()
    private var lastSampleTime: Double?
    public private(set) var acceptedOnset = -Double.infinity
    public private(set) var acceptedPath = ""
    public var lastRejectionTime: Double { max(confirmationGate.rejectionTime, max(envelope.rejectionTime, impulse.rejectionTime)) }
    public var lastRejectionReason: String {
        if confirmationGate.rejectionTime >= max(envelope.rejectionTime, impulse.rejectionTime) {
            return confirmationGate.rejectionReason
        }
        return impulse.rejectionTime > envelope.rejectionTime
            ? "impulse: " + impulse.rejectionReason : "envelope: " + envelope.rejectionReason
    }
    public var feature: Double { envelope.feature }
    public var threshold: Double { envelope.threshold }
    public var impulseFeature: Double? { settings.amplitudeFloor < 0.0175 ? impulse.feature : nil }
    public var impulseThreshold: Double? { settings.amplitudeFloor < 0.0175 ? impulse.threshold : nil }
    public var pendingOnset: Double? {
        [envelope.pendingOnset, settings.amplitudeFloor < 0.0175 ? impulse.pendingOnset : nil]
            .compactMap { $0 }.min()
    }
    public var warmingUp: Bool { envelope.warmingUp }
    public init() {}
    public mutating func reset() {
        envelope.reset(); impulse.reset(); confirmationGate.reset()
        lastSampleTime = nil; acceptedOnset = -Double.infinity; acceptedPath = ""
    }
    public mutating func ingest(_ sample: AccelerationSample, lastKeyTime: Double?, maximumSampleGap: Double = 0.5) -> Bool {
        guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { return false }
        if let previous = lastSampleTime {
            guard sample.time > previous else { return false }
            if sample.time - previous > max(0.5, maximumSampleGap) { reset() }
        }
        lastSampleTime = sample.time
        envelope.settings = settings
        let knock = envelope.ingest(sample, lastKeyTime: lastKeyTime, maximumSampleGap: maximumSampleGap)
        var light = false
        if settings.amplitudeFloor < 0.0175 {
            impulse.settings = settings
            light = impulse.ingest(sample, lastKeyTime: lastKeyTime, maximumSampleGap: maximumSampleGap)
        }
        guard knock || light else { return false }
        let onset = min(knock ? envelope.acceptedOnset : .infinity,
                        light ? impulse.acceptedOnset : .infinity)
        guard confirmationGate.accept(onset: onset, confirmedAt: sample.time) else { return false }
        acceptedOnset = onset
        acceptedPath = light ? "impulse" : "envelope"
        return true
    }
}
