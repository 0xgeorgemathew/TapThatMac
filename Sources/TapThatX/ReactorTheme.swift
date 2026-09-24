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
}

/// Liquid Glass on macOS 26+ (picks up the macOS 27 refinements automatically),
/// ultraThinMaterial below, solid fill under Reduce Transparency.
private struct ReactorGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// Applies the reactor glass surface material in the given shape.
    func reactorGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(ReactorGlassModifier(shape: shape, interactive: interactive))
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

extension View {
    /// Prominent action: Liquid Glass prominent on macOS 26, classic below.
    @ViewBuilder
    func reactorProminentButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glassProminent) }
        else { self.buttonStyle(.borderedProminent) }
    }
    /// Glass secondary action on macOS 26, bordered below.
    @ViewBuilder
    func reactorGlassButton() -> some View {
        if #available(macOS 26.0, *) { self.buttonStyle(.glass) }
        else { self.buttonStyle(.bordered) }
    }
}
