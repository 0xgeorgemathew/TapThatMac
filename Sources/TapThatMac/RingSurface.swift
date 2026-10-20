import AppKit
import SwiftUI
import TapCore

// MARK: - Geometry

/// Ring proportions as fractions of its diameter, shared by the hit regions,
/// the artwork and the Actions pane's miniature.
enum RingGeometry {
    static let outer = 0.47
    static let inner = 0.245
    static let label = 0.355
    static let hub = 0.43
    static var count: Int { Command.allCases.count }
    static var sweep: Double { 360 / Double(count) }

    /// Center of item `index`, clockwise from twelve o'clock.
    static func position(_ index: Int, size: CGFloat, radius: Double = label) -> CGPoint {
        let angle = (Double(index) * sweep - 90) * .pi / 180
        return CGPoint(x: size / 2 + cos(angle) * size * radius, y: size / 2 + sin(angle) * size * radius)
    }
}

/// Pointer hit region for one command: the full wedge between hub and rim.
struct Sector: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let sweep = RingGeometry.sweep
        let start = Double(index) * sweep - 90 - sweep / 2 + 1
        let end = start + sweep - 2
        var path = Path()
        path.addArc(center: center, radius: rect.width / 2 - 7, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: rect.width * 0.235, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A softly rounded annular segment at twelve o'clock. Rotated to travel; the
/// hit regions above never move, so fast navigation never shifts targets.
struct RingSelectionSurface: Shape {
    var corner: CGFloat = 12
    var gap: Double = 0.05

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width * RingGeometry.outer
        let inner = rect.width * (RingGeometry.inner + 0.005)
        let corner = min(self.corner, (outer - inner) / 3)
        let halfSweep = .pi / Double(RingGeometry.count) - gap
        let start = -.pi / 2 - halfSweep
        let end = -.pi / 2 + halfSweep
        let outerInset = Double(corner / outer)
        let innerInset = Double(corner / inner)

        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        var path = Path()
        path.move(to: point(outer, start + outerInset))
        path.addArc(center: center, radius: outer,
                    startAngle: .radians(start + outerInset), endAngle: .radians(end - outerInset), clockwise: false)
        path.addQuadCurve(to: point(outer - corner, end), control: point(outer, end))
        path.addLine(to: point(inner + corner, end))
        path.addQuadCurve(to: point(inner, end - innerInset), control: point(inner, end))
        path.addArc(center: center, radius: inner,
                    startAngle: .radians(end - innerInset), endAngle: .radians(start + innerInset), clockwise: true)
        path.addQuadCurve(to: point(inner + corner, start), control: point(inner, start))
        path.addLine(to: point(outer - corner, start))
        path.addQuadCurve(to: point(outer, start + outerInset), control: point(outer, start))
        path.closeSubpath()
        return path
    }
}

/// The lit edge of the selection: a short arc along the rim at twelve o'clock.
struct RingPointerArc: Shape {
    func path(in rect: CGRect) -> Path {
        let half = RingGeometry.sweep / 2 - 9
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * (RingGeometry.outer + 0.012),
                    startAngle: .degrees(-90 - half), endAngle: .degrees(-90 + half), clockwise: false)
        return path
    }
}

/// Hairline spokes between the commands.
struct RingSpokes: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for index in 0..<RingGeometry.count {
            let angle = (Double(index) * RingGeometry.sweep - 90 + RingGeometry.sweep / 2) * .pi / 180
            let from = rect.width * (RingGeometry.inner + 0.03), to = rect.width * (RingGeometry.outer - 0.03)
            path.move(to: CGPoint(x: center.x + cos(angle) * from, y: center.y + sin(angle) * from))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * to, y: center.y + sin(angle) * to))
        }
        return path
    }
}

/// The disc: the same lifted graphite as the app's cards, with a hairline, a
/// top highlight and a deep soft shadow so it floats over any desktop.
struct RingDisc: View {
    var shadow = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.discTop, Theme.discBottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                Circle().fill(RadialGradient(colors: [Theme.signal.opacity(scheme == .dark ? 0.07 : 0.04), .clear],
                                             center: .center, startRadius: 0, endRadius: 240))
            }
            .overlay {
                RingSpokes().stroke(contrast == .increased ? Theme.muted : Theme.hairline, lineWidth: 1)
            }
            .overlay { Circle().strokeBorder(contrast == .increased ? Theme.muted : Theme.hairline, lineWidth: 1) }
            .overlay {
                Circle().strokeBorder(LinearGradient(colors: [Theme.highlight, .clear], startPoint: .top, endPoint: .center),
                                      lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadow ? (scheme == .dark ? 0.5 : 0.18) : 0), radius: 28, y: 14)
            .shadow(color: .black.opacity(shadow ? 0.12 : 0), radius: 2, y: 1)
    }
}

/// The traveling selection: tinted segment, top-lit edge, glowing rim arc.
struct RingSelectionHighlight: View {
    var flash = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Light appearance needs far less tint for the same presence.
        let strength = scheme == .dark ? 1.0 : 0.55
        ZStack {
            RingSelectionSurface()
                .fill(LinearGradient(colors: [Theme.signal.opacity((flash ? 0.42 : 0.22) * strength),
                                              Theme.signal.opacity((flash ? 0.2 : 0.07) * strength)],
                                     startPoint: .top, endPoint: .bottom))
            RingSelectionSurface()
                .stroke(LinearGradient(colors: [Theme.signal.opacity(contrast == .increased ? 0.9 : 0.55),
                                                Theme.signal.opacity(contrast == .increased ? 0.9 : 0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: contrast == .increased ? 1.5 : 1)
            RingPointerArc()
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Theme.signal.opacity(0.8), radius: 6)
        }
        .shadow(color: Theme.signal.opacity(flash ? 0.5 : 0.18), radius: flash ? 22 : 14)
    }
}

/// One command's icon and name, positioned on the ring.
struct RingItemLabel: View {
    let command: Command
    let selected: Bool
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 3 : 6) {
            Image(systemName: command.symbol)
                .font(.system(size: compact ? 11 : 21, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.signal : Theme.ink.opacity(0.78))
                .shadow(color: Theme.signal.opacity(selected ? 0.6 : 0), radius: 8)
                .frame(height: compact ? 12 : 24)
            if !compact {
                VStack(spacing: 1) {
                    if let family = command.family {
                        Text(family.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(selected ? Theme.signal.opacity(0.8) : Theme.faint)
                    }
                    Text(command.shortName)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.ink : Theme.muted)
                }
                .multilineTextAlignment(.center)
                .frame(width: 84)
            }
        }
    }
}

// MARK: - The live ring

/// Captures the interpolated angle without publishing state or scheduling a
/// second layout pass. Pointer retargeting can start from what is on screen.
private struct PresentedSelectionRotation: AnimatableModifier {
    var angle: Double
    let state: RingState

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        state.presentedSelectionAngle = angle
        return content.rotationEffect(.degrees(angle))
    }
}

private struct RingOptionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The hub supplies press feedback; the plain style would dim the ring.
        configuration.label
    }
}

/// One persistent selection surface travels over a still disc. Controls stay
/// fixed so fast navigation never moves the targets beneath the pointer.
struct RingContent: View {
    @ObservedObject var state: RingState
    let size: CGFloat
    let reduceMotion: Bool
    @State private var arrived = false

    var body: some View {
        ZStack {
            RingDisc()

            RingSelectionHighlight(flash: state.committing != nil)
                .modifier(PresentedSelectionRotation(angle: state.selectionAngle, state: state))
                .animation(reduceMotion ? nil : RingMotion.selection, value: state.selectionAngle)
                .animation(reduceMotion ? nil : RingMotion.confirmation, value: state.committing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ForEach(Array(Command.allCases.enumerated()), id: \.element) { index, command in
                let shape = Sector(index: index)
                let isSelected = state.selected == command
                Button { state.choose?(command) } label: {
                    ZStack {
                        shape.fill(.clear)
                        RingItemLabel(command: command, selected: isSelected)
                            .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
                            .animation(reduceMotion ? nil : RingMotion.selection, value: isSelected)
                            // Arrival: items settle in clockwise, a few ms apart.
                            .opacity(arrived || reduceMotion ? 1 : 0)
                            .offset(y: arrived || reduceMotion ? 0 : 6)
                            .animation(reduceMotion ? nil : RingMotion.opening.delay(Double(index) * 0.018),
                                       value: arrived)
                            .position(RingGeometry.position(index, size: size))
                    }
                    .contentShape(shape)
                }
                .buttonStyle(RingOptionStyle())
                // The ring has its own keyboard model (arrows, Return, Esc)
                // and the selection is its focus; no system focus ring.
                .focusable(false)
                .focusEffectDisabled()
                .disabled(state.automaticAction || state.committing != nil)
                .onHover { inside in
                    if inside && !state.automaticAction && state.committing == nil {
                        state.select(command)
                    }
                }
                .accessibilityLabel(command.rawValue)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            CenterReadout(state: state, size: size, reduceMotion: reduceMotion)
        }
        .frame(width: size, height: size)
        .onAppear { arrived = true }
    }
}
