import SwiftUI
import TapCore

/// The hub: what's highlighted, and how many taps the ring has heard.
///
/// Two dots under the name mirror the double-tap: the first lights when a
/// single tap is pending, both light on a choice, and a ring of signal draws
/// itself around the hub while the choice commits.
struct CenterReadout: View {
    @ObservedObject var state: RingState
    let size: CGFloat
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var command: Command? { state.committing ?? state.selected }
    private var diameter: CGFloat { size * RingGeometry.hub }
    private var committing: Bool { state.committing != nil }

    private var guidance: String {
        if committing { return "Chosen" }
        if state.automaticAction { return "Selecting…" }
        if state.tapPending { return "Tap again to choose" }
        return "Tap to move · tap twice to choose"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: command?.symbol ?? "circle.dotted.circle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(committing ? Theme.signal : Theme.ink)
                .shadow(color: Theme.signal.opacity(committing ? 0.7 : 0), radius: 10)
                .scaleEffect(committing && !reduceMotion ? 1.12 : 1)
                .animation(reduceMotion ? nil : RingMotion.confirmation, value: committing)
                .frame(height: 32)
                .accessibilityHidden(true)
                .padding(.bottom, 8)

            if let family = command?.family {
                Text(family.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.faint)
            }
            Text(command?.shortName ?? "Tap That Mac")
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: diameter * 0.82)

            TapDots(first: state.tapPending || committing, second: committing, reduceMotion: reduceMotion)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Text(guidance)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(contrast == .increased ? Theme.ink : Theme.muted)
                .multilineTextAlignment(.center)
                .frame(width: diameter * 0.8)

            if !state.automaticAction {
                Text("← →  ·  Return  ·  Esc")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 3)
            }
        }
        // Keep one current text tree; a different command fades its contents
        // in quickly so rapid navigation never stacks outgoing labels.
        .transaction { $0.animation = nil }
        .phaseAnimator([false, true], trigger: command) { content, dimmed in
            content.opacity(reduceMotion || !dimmed ? 1 : 0.6)
        } animation: { dimmed in
            reduceMotion || dimmed ? nil : RingMotion.content
        }
        .frame(width: diameter, height: diameter)
        .background {
            Circle()
                .fill(Color.black.opacity(scheme == .dark ? 0.22 : 0.035))
                .overlay(Circle().strokeBorder(contrast == .increased ? Theme.muted : Theme.hairline, lineWidth: 1))
        }
        .overlay {
            // The commit ring draws itself around the hub.
            Circle()
                .trim(from: 0, to: committing ? 1 : 0)
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.signal.opacity(0.7), radius: 6)
                .padding(1.25)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: committing)
        }
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}

/// Two dots: one per tap of a double-tap.
struct TapDots: View {
    let first: Bool
    let second: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            dot(first)
            dot(second)
        }
        .accessibilityHidden(true)
    }

    private func dot(_ lit: Bool) -> some View {
        Circle()
            .fill(lit ? Theme.signal : Theme.faint.opacity(0.35))
            .frame(width: 6, height: 6)
            .shadow(color: Theme.signal.opacity(lit ? 0.8 : 0), radius: 4)
            .scaleEffect(lit && !reduceMotion ? 1.25 : 1)
            .animation(reduceMotion ? nil : Motion.pop, value: lit)
    }
}
