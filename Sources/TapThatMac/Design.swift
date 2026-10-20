import AppKit
import SwiftUI

// MARK: - Palette
//
// One set of tokens for the window, the graph, the ring and the toast. The
// surfaces are quiet graphite; color is reserved for meaning:
//
//   signal  cyan    motion, the live state, selection
//   gate    gold    the threshold a tap has to cross
//   impulse violet  the light-tap impulse
//   ok / warn / danger  status only
//
// Every token adapts to light and dark appearance. AppKit drawing (the graph)
// reads the NSColor forms, so both worlds resolve the same values.

/// sRGB color from a hex literal, e.g. `hex(0x7FD3F7)`.
func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

private func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
}

enum Palette {
    // Text
    static let ink = adaptive(hex(0x15181D), hex(0xEEF2F6))
    static let muted = adaptive(hex(0x15181D, 0.58), hex(0xEEF2F6, 0.60))
    static let faint = adaptive(hex(0x15181D, 0.40), hex(0xEEF2F6, 0.38))

    // Surfaces
    static let canvas = adaptive(hex(0xEEF0F3), hex(0x0E1217))
    static let sidebar = adaptive(hex(0xE6E9ED), hex(0x0A0D11))
    static let cardTop = adaptive(.white, hex(0xFFFFFF, 0.060))
    static let cardBottom = adaptive(.white, hex(0xFFFFFF, 0.030))
    static let hairline = adaptive(hex(0x000000, 0.07), hex(0xFFFFFF, 0.075))
    static let highlight = adaptive(.clear, hex(0xFFFFFF, 0.08))
    static let tile = adaptive(hex(0x000000, 0.035), hex(0xFFFFFF, 0.045))
    static let tileHover = adaptive(hex(0x000000, 0.055), hex(0xFFFFFF, 0.075))
    static let track = adaptive(hex(0x000000, 0.055), hex(0x000000, 0.30))
    static let thumbTop = adaptive(.white, hex(0xFFFFFF, 0.17))
    static let thumbBottom = adaptive(.white, hex(0xFFFFFF, 0.10))
    static let grid = adaptive(hex(0x000000, 0.06), hex(0xFFFFFF, 0.055))
    static let well = adaptive(hex(0x000000, 0.025), hex(0x000000, 0.22))
    /// The ring's disc: a lifted graphite, a step above the window canvas.
    static let discTop = adaptive(hex(0xFBFCFD), hex(0x1B2129))
    static let discBottom = adaptive(hex(0xEEF1F4), hex(0x11151B))

    // Meaning
    static let signal = adaptive(hex(0x0B78B0), hex(0x7FD3F7))
    static let signalDeep = adaptive(hex(0x0A5F8C), hex(0x3BA9DB))
    static let onSignal = adaptive(.white, hex(0x04121B))
    static let gate = adaptive(hex(0xA87400), hex(0xE9B949))
    static let impulse = adaptive(hex(0x6A4FD8), hex(0xB9A6FF))
    static let ok = adaptive(hex(0x1E9E45), hex(0x30D158))
    static let warn = adaptive(hex(0xB87200), hex(0xFFC248))
    static let danger = adaptive(hex(0xD21F45), hex(0xFF6982))
}

enum Theme {
    static let ink = Color(nsColor: Palette.ink)
    static let muted = Color(nsColor: Palette.muted)
    static let faint = Color(nsColor: Palette.faint)
    static let canvas = Color(nsColor: Palette.canvas)
    static let sidebar = Color(nsColor: Palette.sidebar)
    static let cardTop = Color(nsColor: Palette.cardTop)
    static let cardBottom = Color(nsColor: Palette.cardBottom)
    static let hairline = Color(nsColor: Palette.hairline)
    static let highlight = Color(nsColor: Palette.highlight)
    static let tile = Color(nsColor: Palette.tile)
    static let tileHover = Color(nsColor: Palette.tileHover)
    static let track = Color(nsColor: Palette.track)
    static let thumbTop = Color(nsColor: Palette.thumbTop)
    static let thumbBottom = Color(nsColor: Palette.thumbBottom)
    static let discTop = Color(nsColor: Palette.discTop)
    static let discBottom = Color(nsColor: Palette.discBottom)
    static let signal = Color(nsColor: Palette.signal)
    static let signalDeep = Color(nsColor: Palette.signalDeep)
    static let onSignal = Color(nsColor: Palette.onSignal)
    static let gate = Color(nsColor: Palette.gate)
    static let impulse = Color(nsColor: Palette.impulse)
    static let ok = Color(nsColor: Palette.ok)
    static let warn = Color(nsColor: Palette.warn)
    static let danger = Color(nsColor: Palette.danger)

    /// Large surfaces (cards, the ring hub) and small ones (tiles, rows).
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 12
    static let cardShape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    static let tileShape = RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
}

// MARK: - Motion

/// Shared curves. Short and well damped: the app should feel immediate, and a
/// tap-driven interface must never lag the hand that drives it.
enum Motion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let settle = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.6)
    static let fade = Animation.easeOut(duration: 0.16)

    static func reduced(_ animation: Animation, _ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Type

extension Font {
    /// Pane titles: large, heavy, tightly tracked.
    static let ttTitle = Font.system(size: 30, weight: .bold)
    /// Hero numerals, always with tabular figures at the call site.
    static func ttNumeral(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold) }
    static let ttHeadline = Font.system(size: 14, weight: .semibold)
    static let ttBody = Font.system(size: 13)
    static let ttCaption = Font.system(size: 11.5)
    static let ttEyebrow = Font.system(size: 10.5, weight: .semibold)
}

/// Small tracked caps: section labels, axis names, states.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.faint

    init(_ text: String, color: Color = Theme.faint) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.ttEyebrow)
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

// MARK: - Surfaces

/// The card: a faint top-lit gradient, a hairline, and an optional colored orb
/// glowing from the top-left corner that names the card's subject.
private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var orb: Color?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = Theme.cardShape
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: [Theme.cardTop, Theme.cardBottom],
                                              startPoint: .top, endPoint: .bottom))
                    if let orb {
                        RadialGradient(colors: [orb.opacity(scheme == .dark ? 0.2 : 0.09), .clear],
                                       center: .topLeading, startRadius: 0, endRadius: 320)
                            .clipShape(shape)
                    }
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 12, y: 6)
                .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 1, y: 1)
            }
            .overlay {
                shape.strokeBorder(contrast == .increased ? Theme.muted : Theme.hairline, lineWidth: 1)
            }
            .overlay {
                // A one-point top highlight: the edge catching light.
                shape.strokeBorder(LinearGradient(colors: [Theme.highlight, .clear],
                                                  startPoint: .top, endPoint: .center), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func card(padding: CGFloat = 22, orb: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, orb: orb))
    }

    /// Inner grouping inside a card.
    func tile(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tile, in: Theme.tileShape)
    }
}

/// A rounded square holding a symbol, tinted with its subject's color.
struct IconTile: View {
    let symbol: String
    var color: Color = Theme.signal
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.1)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Status

/// A dot with a soft halo of its own color. `pulsing` sends out a slow ring,
/// the one continuous motion in the app, used only for "listening".
struct StatusDot: View {
    let color: Color
    var pulsing = false
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if pulsing && !reduceMotion {
                Circle()
                    .stroke(color, lineWidth: 1)
                    .phaseAnimator([false, true]) { ring, expanded in
                        ring.scaleEffect(expanded ? 2.6 : 1).opacity(expanded ? 0 : 0.7)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.6) : .linear(duration: 0)
                    }
            }
            Circle()
                .fill(color)
                .shadow(color: color.opacity(0.7), radius: size * 0.6)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Dot plus label in a tinted capsule: the app's verdict.
struct StatusBadge: View {
    let title: String
    let color: Color
    var pulsing = false

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(color: color, pulsing: pulsing)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Small outlined caps: WORKS, PRE-ALPHA, EXPERIMENTAL.
struct Tag: View {
    let text: String
    var color: Color = Theme.signal

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(color.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
    }
}

/// A short horizontal legend swatch for the graph's series.
struct LegendItem: View {
    enum Mark { case line, dashes, dots }
    let title: String
    let color: Color
    var mark: Mark = .line

    var body: some View {
        HStack(spacing: 7) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let style: StrokeStyle = switch mark {
                case .line: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                case .dashes: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3.5])
                case .dots: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 4])
                }
                context.stroke(path, with: .color(color), style: style)
            }
            .frame(width: 16, height: 6)
            Text(title)
                .font(.ttCaption)
                .foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Controls

/// The segmented capsule: a recessed track with a lifted thumb that slides
/// between options.
struct SegmentedCapsule<Value: Hashable>: View {
    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    var fill = false

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Segment(text: label(option), selected: option == selection, fill: fill,
                        namespace: namespace) {
                    withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) { selection = option }
                }
            }
        }
        .padding(3)
        .background(Theme.track, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75))
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private struct Segment: View {
        let text: String
        let selected: Bool
        let fill: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text(text)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.ink : hovering ? Theme.ink.opacity(0.8) : Theme.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.thumbTop, Theme.thumbBottom],
                                                     startPoint: .top, endPoint: .bottom))
                                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
}

enum ButtonKind { case primary, secondary, quiet }

/// The one button family. Primary is a lit signal capsule; secondary a quiet
/// tile capsule; quiet is text only.
struct TTButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        TTButtonBody(configuration: configuration, kind: kind, small: small)
    }
}

extension ButtonStyle where Self == TTButtonStyle {
    static var primary: TTButtonStyle { TTButtonStyle(kind: .primary) }
    static var secondary: TTButtonStyle { TTButtonStyle(kind: .secondary) }
    static var primarySmall: TTButtonStyle { TTButtonStyle(kind: .primary, small: true) }
    static var secondarySmall: TTButtonStyle { TTButtonStyle(kind: .secondary, small: true) }
    static var quiet: TTButtonStyle { TTButtonStyle(kind: .quiet, small: true) }
}

private struct TTButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ButtonKind
    let small: Bool

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 6 : small ? 12 : 18)
            .frame(minHeight: small ? 28 : 34)
            .background { background }
            .contentShape(Capsule())
            .focusRing(Capsule(), focused: isFocused)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(Motion.reduced(Motion.pop, reduceMotion), value: configuration.isPressed)
            .animation(Motion.reduced(Motion.fade, reduceMotion), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.onSignal
        case .secondary: Theme.ink
        case .quiet: hovering ? Theme.ink : Theme.signal
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            Capsule()
                .fill(LinearGradient(colors: [Theme.signal, Theme.signalDeep], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75).blendMode(.overlay))
                .brightness(hovering ? 0.05 : 0)
                .shadow(color: Theme.signal.opacity(hovering ? 0.45 : 0.25), radius: hovering ? 12 : 8, y: 2)
        case .secondary:
            Capsule()
                .fill(hovering ? Theme.tileHover : Theme.tile)
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        case .quiet:
            Capsule().fill(hovering ? Theme.tile : .clear)
        }
    }
}

/// A round icon button (close, hold).
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    @State private var hovering = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(hovering ? Theme.ink : Theme.muted)
            .frame(width: size, height: size)
            .background(hovering ? Theme.tileHover : Theme.tile, in: Circle())
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Circle())
            .focusRing(Circle(), focused: isFocused)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(Motion.reduced(Motion.pop, reduceMotion), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// A capsule menu: the selected option and a chevron, opening a native menu.
struct CapsuleMenuPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option
    @State private var hovering = false

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label(selection)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(hovering ? Theme.tileHover : Theme.tile, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        // The button menu style with a plain button draws our label as-is,
        // instead of the system's bordered pop-up chrome.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

// MARK: - Focus

extension View {
    /// The app's one keyboard-focus ring: a signal stroke on the control's own
    /// edge with a soft glow, replacing the system's focus band.
    func focusRing<S: InsettableShape>(_ shape: S, focused: Bool) -> some View {
        self
            .focusEffectDisabled()
            .overlay {
                if focused {
                    shape.strokeBorder(Theme.signal, lineWidth: 2)
                        .shadow(color: Theme.signal.opacity(0.4), radius: 3)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Bounces a symbol when `value` changes, where the API exists.
    @ViewBuilder
    func symbolBounce<V: Equatable>(value: V, reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else if #available(macOS 15.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}
