import SwiftUI

/// Design tokens: one cyan-blue accent and one surface radius.
/// The accent adapts to light and dark appearance.
enum ReactorTheme {
    /// Primary accent. Light: deep blue for contrast. Dark: bright cyan.
    /// SwiftUI has no Color(light:dark:) on macOS, so adapt through an NSColor
    /// dynamic provider resolved per appearance.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            NSColor(red: 0.404, green: 0.780, blue: 0.922, alpha: 1)
        } else {
            NSColor(red: 0.106, green: 0.494, blue: 0.706, alpha: 1)
        }
    })
    /// The one corner radius for custom surfaces across the app.
    static let surfaceRadius: CGFloat = 12

    /// Tint for prominent (white-label) buttons. The bright cyan accent is
    /// too light under white text (~1.9:1), so prominent glass deepens it to
    /// a saturated cyan-blue. Contrast arithmetic, WCAG relative luminance:
    /// dark fill #0E7FA8 -> R lin 0.0044, G lin 0.212, B lin 0.392
    /// => L = 0.2126*0.0044 + 0.7152*0.212 + 0.0722*0.392 = 0.181
    /// white contrast = (1.0 + 0.05) / (0.181 + 0.05) = 4.5:1 (target >= 3:1).
    /// Light fill #1B7EB5 -> L = 0.184, white contrast 4.5:1.
    static let prominentAccent = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            NSColor(red: 0.055, green: 0.498, blue: 0.659, alpha: 1)
        } else {
            NSColor(red: 0.106, green: 0.494, blue: 0.706, alpha: 1)
        }
    })
}

/// Liquid Glass on macOS 26+ (picks up the macOS 27 refinements automatically),
/// ultraThinMaterial below, solid fill under Reduce Transparency.
private struct ReactorGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var interactive: Bool
    /// Optional accent tint for prominent glass surfaces.
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Reduce Transparency fallback: solid, but still tinted when asked.
            content.background(
                tint ?? Color(nsColor: .windowBackgroundColor),
                in: shape
            )
        } else if #available(macOS 26.0, *) {
            let style = tint.map { Glass.regular.tint($0) } ?? .regular
            let glass = content.glassEffect(interactive ? style.interactive() : style, in: shape)
            if let tint {
                // Over the fully transparent window the glass tint alone
                // composites toward neutral gray, so seat tinted glass on a
                // stable accent ground fill underneath; the glass highlights
                // and bevel still render over it. Untinted glass is unchanged.
                glass.background(tint.opacity(0.85), in: shape)
            } else {
                glass
            }
        } else {
            // Pre-Liquid-Glass fallback: tinted capsule fill or thin material.
            if let tint {
                content.background(tint.opacity(0.88), in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        }
    }
}

extension View {
    /// Applies the reactor glass surface material in the given shape.
    /// `tint` colors the glass (prominent actions, the active nav pill).
    func reactorGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(ReactorGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }
}

/// Coordinates Liquid Glass rendering across adjacent surfaces on macOS 26 so
/// effects merge and lens correctly; a plain pass-through below that version.
struct ReactorGlassContainer<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Additive UI helpers (glass redesign pass)

/// Subtle 1px top-lit inner highlight so glass edges refract like ZCode/Codex.
/// Uses label-tinted (white-in-dark / black-in-light) strokes, not a new color.
extension View {
    func reactorEdgeHighlight<S: InsettableShape>(in shape: S) -> some View {
        overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.primary.opacity(0.12), .primary.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
    }
}

// MARK: - The one keyboard-focus ring

/// The app's single focus vocabulary, shared by every custom control:
/// disables the system's hard steel-blue focus band and, when `focused`,
/// draws the app recipe instead — a 2.5pt `ReactorTheme.accent` stroke
/// seated on the control's own edge (covering the surface hairline so it
/// reads as one clean stroke) with a soft outer accent glow for glass
/// depth. The ring is static by design: it never pulses or animates, so
/// Reduce Motion needs no special case.
extension View {
    func reactorFocusRing<S: InsettableShape>(in shape: S, focused: Bool) -> some View {
        self
            .focusEffectDisabled()
            .overlay {
                if focused {
                    shape
                        .strokeBorder(ReactorTheme.accent, lineWidth: 2.5)
                        .shadow(color: ReactorTheme.accent.opacity(0.35), radius: 3)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Content-layer surfaces

extension ReactorTheme {
    /// Continuous-rounded shape for small elements inside panels (graph
    /// insets, chips). Floating panels use `panelShape`; buttons are capsules.
    static let cardShape = RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous)

    /// The panel radius: the one continuous corner radius (20pt) for the
    /// large floating glass panels that hold pane content. Small elements
    /// keep `surfaceRadius` (12pt); buttons stay capsules.
    static let panelRadius: CGFloat = 20
    /// Continuous-rounded shape shared by all floating glass panels.
    static let panelShape = RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
}

/// Floating glass panel: the one pane surface. Liquid Glass on macOS 26+,
/// a translucent material with an edge highlight and a soft shadow lift on
/// macOS 14/15 (the Calibration pads' drop-shadow lift), and a quiet opaque
/// card fill under Reduce Transparency so content stays readable.
/// Panels float directly on the stage — never stacked on other glass.
private struct ReactorPanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let framed = content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        if reduceTransparency {
            framed
                .background(Color(nsColor: .controlBackgroundColor), in: ReactorTheme.panelShape)
                .overlay(
                    ReactorTheme.panelShape.strokeBorder(
                        Color(nsColor: .separatorColor).opacity(contrast == .increased ? 1 : 0.55),
                        lineWidth: 1
                    )
                )
        } else if #available(macOS 26.0, *) {
            framed
                .glassEffect(.regular, in: ReactorTheme.panelShape)
                .reactorEdgeHighlight(in: ReactorTheme.panelShape)
        } else {
            framed
                .background(.ultraThinMaterial, in: ReactorTheme.panelShape)
                .reactorEdgeHighlight(in: ReactorTheme.panelShape)
                .shadow(color: .black.opacity(0.26), radius: 16, x: 0, y: 8)
        }
    }
}

extension View {
    /// Groups content on the floating glass panel surface with generous padding.
    func reactorCard() -> some View { modifier(ReactorPanelModifier()) }

    /// Soft elevation for floating glass chrome (the nav dock rail) where the
    /// system Liquid Glass effect does not already draw its own shadow.
    /// No-op on macOS 26+, where `glassEffect` provides the lift.
    @ViewBuilder
    func reactorGlassLift() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self.shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 6)
        }
    }
}

/// Standard pane scroll container: Calibration-scale padding, a wide content
/// column, and 24pt section rhythm so panes breathe like the reference screen.
struct PaneScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                // Trailing inset is narrower to optically balance the overlay
                // scrollbar lane, so the card column reads symmetric (~34pt)
                // against the pane edges on both sides.
                .padding(.leading, 32)
                .padding(.trailing, 16)
                // Extra bottom inset so the final card can clear the footer
                // shelf at the resting scroll position.
                .padding(.bottom, 64)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - The one button family

/// Size variants of the reactor button family. Everything is the same
/// interactive Liquid Glass capsule; only the metrics differ.
enum ReactorButtonVariant {
    /// Standard action: 44pt+ tall, 28pt horizontal padding.
    case standard
    /// Inline/small utility action: 34pt tall, 18pt padding, smaller title.
    case compact
    /// Circular icon-only action: >= 34pt, no extra padding (label frames it).
    case icon

    var font: Font {
        switch self {
        case .standard: .system(size: 15, weight: .semibold, design: .rounded)
        case .compact: .system(size: 13, weight: .semibold, design: .rounded)
        case .icon: .system(size: 13, weight: .semibold, design: .rounded)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .standard: 28
        case .compact: 18
        case .icon: 0
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .standard: 44
        case .compact, .icon: 34
        }
    }
}

/// The single button style for the whole app: interactive Liquid Glass
/// capsule, optionally tinted with the one accent (prominent). Every variant
/// shows a press scale, a hover highlight, and dims to 0.45 when disabled.
struct ReactorGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var variant: ReactorButtonVariant = .standard

    func makeBody(configuration: Configuration) -> some View {
        ReactorButtonBody(
            configuration: configuration,
            prominent: prominent,
            variant: variant
        )
    }
}

extension ButtonStyle where Self == ReactorGlassButtonStyle {
    /// Standard secondary glass action.
    static var reactorButton: ReactorGlassButtonStyle { ReactorGlassButtonStyle() }

    /// Standard action; prominent tints the glass with the accent.
    static func reactorButton(prominent: Bool) -> ReactorGlassButtonStyle {
        ReactorGlassButtonStyle(prominent: prominent)
    }

    /// Small inline secondary glass action for utility rows.
    static var reactorButtonCompact: ReactorGlassButtonStyle {
        ReactorGlassButtonStyle(variant: .compact)
    }

    /// Small inline action; prominent tints the glass with the accent.
    static func reactorButtonCompact(prominent: Bool) -> ReactorGlassButtonStyle {
        ReactorGlassButtonStyle(prominent: prominent, variant: .compact)
    }

    /// Circular interactive glass icon button (label must frame itself >= 34pt).
    static var reactorIconButton: ReactorGlassButtonStyle {
        ReactorGlassButtonStyle(variant: .icon)
    }
}

/// The one picker skin: a glass capsule menu replacing the stock
/// NSPopUpButton. The capsule shows the selected option's text with a
/// chevron on the button family's glass; the pop-up itself stays a native
/// menu (`Picker` inside `Menu` keeps checkmark selection, keyboard access,
/// and accessibility). `label` produces the exact option strings shown in
/// the menu rows and on the capsule.
struct ReactorGlassMenuPicker<Option: Hashable>: View {
    /// The control's accessible name (the picker's original title).
    let title: String
    /// Every option; the selected one carries the menu's checkmark.
    let options: [Option]
    /// Display text for one option.
    let label: (Option) -> String
    @Binding var selection: Option

    @Environment(\.isEnabled) private var isEnabled
    /// Accent is reserved for live interaction. At rest the capsule stays
    /// neutral (label `.primary`, chevron `.secondary`) so it never mimics
    /// a focused control; the accent appears only while hovered live.
    @State private var hovering = false

    private var liveAccent: Bool { hovering && isEnabled }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label(selection))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(liveAccent ? ReactorTheme.accent : Color.secondary)
            }
            .font(.system(size: 13, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(minHeight: 34)
        }
        .menuStyle(.borderlessButton)
        // The borderless menu paints its label with the tint color, so the
        // tint carries the same rule as the chevron: neutral `.primary` at
        // rest, the one accent only while live.
        .tint(liveAccent ? ReactorTheme.accent : Color.primary)
        .reactorGlass(in: Capsule(), interactive: true)
        .reactorEdgeHighlight(in: Capsule())
        // Match the button family's disabled dim.
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 && isEnabled }
        .accessibilityLabel(title)
    }
}

/// Button body kept as a View so hover state is reliable; the press spring,
/// hover highlight, and dimming all live here for every variant.
private struct ReactorButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let variant: ReactorButtonVariant

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Keyboard focus, so buttons carry the same one-ring focus language as
    /// the dock pills instead of the system's steel-blue band.
    @Environment(\.isFocused) private var isFocused

    private var hoverStroke: Color {
        prominent ? Color.white.opacity(0.28) : ReactorTheme.accent.opacity(0.4)
    }

    var body: some View {
        configuration.label
            .font(variant.font)
            .foregroundStyle(
                prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(ReactorTheme.accent)
            )
            .padding(.horizontal, variant.horizontalPadding)
            .frame(minHeight: variant.minHeight)
            .modifier(ReactorGlassModifier(
                shape: Capsule(),
                interactive: true,
                tint: prominent ? ReactorTheme.prominentAccent : nil
            ))
            .reactorEdgeHighlight(in: Capsule())
            .overlay(
                // Prominent capsules get a brighter top-lit rim so they share
                // the same beveled-glass language as the compact secondaries.
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: prominent
                            ? [Color.white.opacity(0.30), Color.white.opacity(0.08)]
                            : [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .overlay(
                // Hover: subtle brightening stroke so the target reads live.
                Capsule().strokeBorder(hovering ? hoverStroke : .clear, lineWidth: 1)
            )
            // Keyboard focus: the shared accent ring and soft glow; the
            // helper also disables the system focus band.
            .reactorFocusRing(in: Capsule(), focused: isFocused)
            .brightness(hovering && !configuration.isPressed ? 0.04 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                value: configuration.isPressed
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}
