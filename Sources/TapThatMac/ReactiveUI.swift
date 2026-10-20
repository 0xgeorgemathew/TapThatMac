import SwiftUI

// MARK: - Reactive layer (glass redesign pass 2)
//
// Small, reusable live-motion components shared by the panes. Everything in
// this file is motivated (driven by real data or a real state change), uses
// restrained springs, and settles to a static presentation under
// Reduce Motion. Nothing here polls: the data arrives through AppModel's
// publishers and ordinary SwiftUI values.

/// Ring-and-dot live indicator (Calibration's pad motif at small scale).
/// The ring tightens and the dot brightens while motion sits above the
/// detection threshold; crossing the boundary gives one spring pop.
struct LiveMotionIndicator: View {
    /// True while the live motion envelope is above the detection floor.
    let live: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle().stroke(ReactorTheme.accent.opacity(live ? 0.9 : 0.35), lineWidth: 1.4)
            Circle()
                .fill(ReactorTheme.accent)
                .frame(width: 5, height: 5)
                .opacity(live ? 1 : 0.4)
        }
        .frame(width: 12, height: 12)
        .scaleEffect(live && !reduceMotion ? 1.18 : 1)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55),
            value: live
        )
        .accessibilityHidden(true)
    }
}

/// One expanding accent ring fired per detected tap (0.5 s one-shot, like
/// GestureIndicator's active pop). Managed by `TapPulseLayer`.
private struct TapPulseRing: View {
    @State private var expanded = false

    var body: some View {
        ReactorTheme.cardShape
            .strokeBorder(ReactorTheme.accent, lineWidth: 2)
            .opacity(expanded ? 0 : 0.75)
            .scaleEffect(expanded ? 1.06 : 0.92)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { expanded = true }
            }
    }
}

/// Hosts the in-flight tap pulse rings over the graph panel. Rings are
/// removed after their 0.5 s flight so the overlay stays empty at rest.
struct TapPulseLayer: View {
    let pulses: [UUID]
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(pulses, id: \.self) { _ in TapPulseRing() }
            }
        }
        .clipShape(ReactorTheme.cardShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Gently breathes (a 1.02 scale cycle) while `active`; fully static
/// otherwise and under Reduce Motion. Used for the active dock ring-dot,
/// echoing Calibration's live pads.
private struct BreathingScale: ViewModifier {
    let active: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.phaseAnimator([false, true]) { view, phase in
                view.scaleEffect(phase ? 1.02 : 1)
            } animation: { _ in
                .easeInOut(duration: 1.5)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Subtle 1.02 scale breathe for the active dock pill's ring-dot.
    func reactorBreathing(active: Bool, reduceMotion: Bool) -> some View {
        modifier(BreathingScale(active: active, reduceMotion: reduceMotion))
    }
}

/// Symbol bounce gated to macOS 15+ (`symbolEffect(.bounce, value:)`),
/// pass-through below and under Reduce Motion.
private struct ReactorSymbolBounce: ViewModifier {
    let value: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else if #available(macOS 15.0, *) {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

extension View {
    /// Bounces a symbol image when `value` flips, where the API is available.
    func reactorSymbolBounce(value: Bool, reduceMotion: Bool) -> some View {
        modifier(ReactorSymbolBounce(value: value, reduceMotion: reduceMotion))
    }
}
