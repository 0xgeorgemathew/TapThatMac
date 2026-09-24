public enum RingSelection {
    /// Returns an unwrapped endpoint for the single animated selection surface.
    /// Positive direction travels clockwise, negative counterclockwise, and zero
    /// chooses the shortest route. Re-selecting an endpoint never adds a turn.
    public static func targetAngle(current: Double, index: Int, count: Int, direction: Int) -> Double {
        guard current.isFinite, count > 0, index >= 0, index < count else { return current }

        let target = Double(index) * 360 / Double(count)
        let normalizedCurrent = current.truncatingRemainder(dividingBy: 360)
        var delta = (target - normalizedCurrent).truncatingRemainder(dividingBy: 360)
        if delta < 0 { delta += 360 }

        // Fractional sector sizes can leave a tiny remainder after a full turn.
        if delta < 0.000000001 || 360 - delta < 0.000000001 { return current }
        if direction < 0 || (direction == 0 && delta > 180) { delta -= 360 }
        return current + delta
    }
}
