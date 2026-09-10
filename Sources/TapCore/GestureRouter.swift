import Foundation

public enum GestureEvent: Equatable { case single, double, triple, ambiguous }

public struct GestureRouter {
    public enum State { case idle, firstKnockPending(Double), secondKnockPending(Double), cooldown(until: Double) }
    public private(set) var state: State = .idle
    public let minimumInterval = 0.1
    public let maximumInterval = 0.45
    private let tripleInterval: Double
    private let recognizesTriples: Bool
    public init(recognizesTriples: Bool = false, tripleInterval: Double = 0.45) {
        self.recognizesTriples = recognizesTriples
        self.tripleInterval = min(0.45, max(0.2, tripleInterval))
    }
    // The detector already rejects impact echoes. Double-only routing needs only
    // the minimum inter-tap gap, not another 350 ms blind period after a pair.
    private var recoveryInterval: Double { recognizesTriples ? 0.35 : minimumInterval }
    public mutating func reset() { state = .idle }
    public mutating func consumeOpening(at time: Double) { state = .cooldown(until: time + recoveryInterval) }

    public mutating func advance(to time: Double) -> GestureEvent? {
        switch state {
        case .firstKnockPending(let first) where time - first > maximumInterval:
            state = .idle; return .single
        case .secondKnockPending(let second) where time - second > tripleInterval:
            state = .cooldown(until: time + recoveryInterval); return .double
        case .cooldown(let until) where time >= until: state = .idle
        default: break
        }
        return nil
    }

    public mutating func knock(at time: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []
        if let expired = advance(to: time) { events.append(expired) }
        switch state {
        case .idle: state = .firstKnockPending(time)
        case .firstKnockPending(let first):
            // A short vibration echo must not cancel the first knock and
            // swallow the real second knock in a cooldown.
            guard time - first >= minimumInterval else { return events }
            if recognizesTriples { state = .secondKnockPending(time) }
            else {
                state = .cooldown(until: time + recoveryInterval)
                events.append(.double)
            }
        case .secondKnockPending(let second):
            guard time - second >= minimumInterval else { return events }
            state = .cooldown(until: time + recoveryInterval)
            events.append(.triple)
        case .cooldown: break
        }
        return events
    }
}
