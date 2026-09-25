import Foundation

/// A fixed display transform: large impacts never rescale away quiet motion.
/// Values and detector thresholds remain in g; only their screen positions change.
public enum MotionGraphScale: String, CaseIterable {
    case detail = "Low-range detail"
    case linear = "Linear"

    public static let ceiling = 0.1
    private static let knee = 0.001

    public var ticks: [Double] {
        switch self {
        case .detail: [0, 0.001, 0.003, 0.01, 0.03, Self.ceiling]
        case .linear: [0, 0.025, 0.05, 0.075, Self.ceiling]
        }
    }

    public func position(for amplitude: Double) -> Double {
        guard amplitude.isFinite else { return 0 }
        let value = min(Self.ceiling, max(0, amplitude))
        switch self {
        case .detail: return log1p(value / Self.knee) / log1p(Self.ceiling / Self.knee)
        case .linear: return value / Self.ceiling
        }
    }

    /// Exact inverse used by threshold dragging, including the expanded scale.
    public func amplitude(at position: Double) -> Double {
        guard position.isFinite else { return 0 }
        let value = min(1, max(0, position))
        switch self {
        case .detail: return Self.knee * expm1(value * log1p(Self.ceiling / Self.knee))
        case .linear: return value * Self.ceiling
        }
    }
}
