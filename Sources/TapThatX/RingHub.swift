import SwiftUI
import TapCore

/// A quiet, concentric readout inside the ring's unchanged central dead zone.
struct CenterReadout: View {
    @ObservedObject var state: RingState
    let size: CGFloat
    let reduceMotion: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var command: Command? { state.committing ?? state.selected }
    private var diameter: CGFloat { size * 0.43 }
    private var guidance: String {
        if state.committing != nil { return "Selected" }
        if state.automaticAction { return "Selecting…" }
        return "Tap to move · Double to choose\nArrows · Return · Esc"
    }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: command?.symbol ?? "circle")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(state.committing == nil ? Color.primary : ReactorTheme.accent)
                // Confirm locally so the material and option targets stay still.
                // This overrides the transaction nil below.
                .scaleEffect(state.committing == nil ? 1 : 1.05)
                .animation(reduceMotion ? nil : RingMotion.confirmation, value: state.committing)
                .frame(width: 40, height: 32)
                .accessibilityHidden(true)

            Text(command?.rawValue ?? "TapThatX")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: diameter * 0.86, height: 36)

            Text(guidance)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(contrast == .increased ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(width: diameter * 0.85, height: 32)
        }
        // Keep one current text/glyph tree. Fading its opacity back in avoids
        // accumulating outgoing labels when navigation changes rapidly. Only a
        // different command fades; confirming the current one keeps it steady.
        .transaction { $0.animation = nil }
        .phaseAnimator([false, true], trigger: command) { content, dimmed in
            content.opacity(reduceMotion || !dimmed ? 1 : 0.72)
        } animation: { dimmed in
            reduceMotion || dimmed ? nil : RingMotion.content
        }
        .frame(width: diameter, height: diameter)
        .background {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(reduceTransparency ? 1 : 0.24))
        }
        .overlay {
            // A whisper of the accent so the hub reads as part of the ring.
            Circle()
                .fill(ReactorTheme.accent.opacity(reduceTransparency || contrast == .increased ? 0 : 0.05))
        }
        .overlay {
            // Strong hairline when contrast is increased; otherwise the shared
            // top-lit glass edge below carries the rim.
            if contrast == .increased {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
            }
        }
        .reactorEdgeHighlight(in: Circle())
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}
