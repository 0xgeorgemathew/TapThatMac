import Foundation

/// Fifteen seconds of local replay context, with fixed storage and no disk I/O.
/// Key timing is retained to reproduce suppression; characters are never stored.
public struct RecentMotionBuffer {
    private var samples = [AccelerationSample?](repeating: nil, count: 12_000)
    private var keys = [Double?](repeating: nil, count: 1024)
    private var sampleIndex = 0
    private var keyIndex = 0
    private var latest = -Double.infinity
    public init() {}

    public mutating func append(_ sample: AccelerationSample) {
        guard sample.time.isFinite, sample.time > latest,
              sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { return }
        latest = sample.time
        samples[sampleIndex] = sample
        sampleIndex = (sampleIndex + 1) % samples.count
    }
    public mutating func appendKey(at time: Double) {
        guard time.isFinite else { return }
        keys[keyIndex] = time
        keyIndex = (keyIndex + 1) % keys.count
    }
    public func snapshot() -> (samples: [AccelerationSample], keyTimes: [Double]) {
        let cutoff = latest - 15
        let motion = (0..<samples.count).compactMap { samples[(sampleIndex + $0) % samples.count] }
            .filter { $0.time >= cutoff }
        let timing = (0..<keys.count).compactMap { keys[(keyIndex + $0) % keys.count] }
            .filter { $0 >= cutoff && $0 <= latest }.sorted()
        return (motion, timing)
    }
}
