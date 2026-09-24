import SwiftUI

/// Each component owns one transition; shared timings keep the ring coordinated.
/// Every curve is short and tightly damped so the ring reads as immediate:
/// durations are ceilings, never theatrical targets. Reduced Motion is honored
/// by the callers (the shell drops to nil animations, the controller to zero
/// duration), not by these constants.
enum RingMotion {
    /// Shell appearance, a 0.96 -> 1 scale with fade. dampingFraction 0.94
    /// overshoots by roughly 0.02% of the scale step: enough to feel like
    /// arrival, far too little to read as a bounce.
    static let opening = Animation.spring(response: 0.24, dampingFraction: 0.94)
    /// Highlight travel across sectors. Damped harder than opening (0.96) so
    /// rapid retargeting never overshoots into the neighboring sector.
    static let selection = Animation.spring(response: 0.23, dampingFraction: 0.96)
    /// Hub press feedback on commit. Critically damped: a confirmation is a
    /// decision, not a bounce.
    static let confirmation = Animation.spring(response: 0.16, dampingFraction: 1)
    /// Hub text and glyph crossfade. Faster than selection so the label never
    /// lags the highlight it names.
    static let content = Animation.easeOut(duration: 0.10)
    /// Retirement delay for the controller's exit choreography; the controller
    /// times panel teardown against this constant. Keep it coupled to `exit`.
    static let exitDuration: Double = 0.12
    static let exit = Animation.easeOut(duration: exitDuration)
}
