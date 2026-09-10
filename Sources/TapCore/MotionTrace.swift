import Foundation

/// Peak envelopes retain millisecond impacts without redrawing at sensor rate.
/// Fixed storage avoids growing history or shifting arrays on every sample.
public struct MotionTrace {
    public struct Point {
        public let time: Double
        public var peak: Double
        public var threshold: Double
    }
    public static let capacity = 400
    private var storage = [Point?](repeating: nil, count: capacity)
    private var next = 0
    private var count = 0
    private var lastTime = -Double.infinity
    public init() {}

    public mutating func append(time: Double, amplitude: Double, threshold: Double) {
        guard time.isFinite, amplitude.isFinite, threshold.isFinite,
              time > lastTime, amplitude >= 0 else { return }
        lastTime = time
        let previous = (next + Self.capacity - 1) % Self.capacity
        if let point = storage[previous], time - point.time < 0.02 {
            storage[previous]?.peak = max(point.peak, amplitude)
            storage[previous]?.threshold = threshold
        } else {
            storage[next] = Point(time: time, peak: amplitude, threshold: threshold)
            next = (next + 1) % Self.capacity
            count = min(count + 1, Self.capacity)
        }
    }

    public var points: [Point] {
        (0..<count).compactMap { storage[(next + Self.capacity - count + $0) % Self.capacity] }
    }
}
