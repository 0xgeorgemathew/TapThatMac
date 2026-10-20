import AppKit
import SwiftUI
import TapCore

// MARK: - Material hosting

/// The backing material under the ring. Reduce Transparency takes precedence
/// over both material branches and selects the opaque surface.
enum RingMaterialKind {
    case liquidGlass
    case legacyBlur
    case opaque
}

/// One circular AppKit material host with the SwiftUI controls installed
/// inside it. On macOS 26+ the hosting view is assigned to
/// NSGlassEffectView.contentView because only the content view is guaranteed
/// to sit inside the glass effect; arbitrary subviews are not. The same
/// hosting view is reused when the material changes, so accessibility
/// preference flips while the ring is open keep selected and committing state.
struct MaterialHost: NSViewRepresentable {
    var material: RingMaterialKind
    var interactive: Bool
    var content: RingContent

    final class Coordinator {
        var hosting: NSHostingView<RingContent>?
        var installedMaterial: RingMaterialKind?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = MaterialContainerView()
        let hosting = NSHostingView(rootView: content)
        context.coordinator.hosting = hosting
        context.coordinator.installedMaterial = material
        container.install(hosting: hosting, material: material)
        container.setInteractive(interactive)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hosting?.rootView = content
        guard let container = nsView as? MaterialContainerView else { return }
        if coordinator.installedMaterial != material {
            coordinator.installedMaterial = material
            if let hosting = coordinator.hosting {
                container.install(hosting: hosting, material: material)
            }
        }
        container.setInteractive(interactive)
    }
}

/// Keeps the backing material installed and fills it to the container. Each
/// material view rounds itself to a circle as it lays out.
final class MaterialContainerView: NSView {
    var backing: NSView?

    override func layout() {
        super.layout()
        // The panel is square but the ring is the circle inscribed in it.
        // Clipping here zeroes every stray square alpha pixel around the
        // glass, so the window shadow, which AppKit derives from the rendered
        // content shape, follows the circle instead of the frame rectangle.
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = bounds.width / 2
    }

    func install(hosting: NSView, material: RingMaterialKind) {
        backing?.removeFromSuperview()
        if #available(macOS 26.0, *), material == .liquidGlass {
            let glass = CircularGlassEffectView()
            glass.style = .regular
            glass.contentView = hosting
            backing = glass
        } else if material == .opaque {
            let surface = CircularOpaqueView()
            surface.addSubview(hosting)
            backing = surface
        } else {
            // macOS 14/15 fallback: legacy vibrancy material, not Liquid Glass.
            let effect = CircularVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.addSubview(hosting)
            backing = effect
        }
        if let backing {
            backing.frame = bounds
            backing.autoresizingMask = [.width, .height]
            addSubview(backing)
        }
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
    }

    /// Interactive glass feedback exists from macOS 27 only; on 26 the glass
    /// stays static and is not promised interactive deformation.
    func setInteractive(_ interactive: Bool) {
        guard #available(macOS 26.0, *), let glass = backing as? NSGlassEffectView else { return }
        // effectIsInteractive is in the macOS 27 SDK (Swift 6.4); older SDKs build without it.
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = interactive
        }
        #endif
    }

}

@available(macOS 26.0, *)
final class CircularGlassEffectView: NSGlassEffectView {
    // The panel is a square hosting a circular surface, so keep the glass
    // fully round whenever the hosting view lays it out.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cornerRadius = newSize.width / 2
    }
}

final class CircularVisualEffectView: NSVisualEffectView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        wantsLayer = true
        layer?.cornerRadius = newSize.width / 2
        layer?.masksToBounds = true
    }
}

final class CircularOpaqueView: NSView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        wantsLayer = true
        layer?.cornerRadius = newSize.width / 2
        layer?.masksToBounds = true
        updateSurfaceColor()
    }
    private func updateSurfaceColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    // Re-resolve the surface color if the system appearance changes while the
    // ring is open.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceColor()
    }
}

struct Sector: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let sweep = 360.0 / Double(Command.allCases.count)
        let start = Double(index) * sweep - 90 - sweep / 2 + 1
        let end = start + sweep - 2
        var path = Path()
        path.addArc(center: center, radius: rect.width / 2 - 7, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: rect.width * 0.235, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A softly rounded annular segment. The artwork is independent of Sector,
/// which keeps pointer hit regions unchanged while the highlight travels.
private struct RingSelectionSurface: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width * 0.468
        let inner = rect.width * 0.248
        let corner = ReactorTheme.surfaceRadius
        let halfSweep = .pi / Double(Command.allCases.count) - 0.045
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
        // Preserve the option's appearance when confirmation disables input.
        // The hub supplies press feedback; the plain style would dim the ring.
        configuration.label
    }
}

/// One persistent selection surface moves over the native material. Controls
/// stay fixed so fast navigation never moves the targets beneath the pointer.
struct RingContent: View {
    @ObservedObject var state: RingState
    let size: CGFloat
    let reduceMotion: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    private let accent = ReactorTheme.accent

    var body: some View {
        ZStack {
            RingSelectionSurface()
                .fill(accent.opacity(contrast == .increased ? 0.23 : 0.13))
                .overlay {
                    // Top-lit glass rim on the pill-shaped segment, matching
                    // the edge treatment of the settings panes' cards.
                    RingSelectionSurface()
                        .stroke(
                            LinearGradient(
                                colors: contrast == .increased
                                    ? [accent.opacity(0.75), accent.opacity(0.75)]
                                    : [accent.opacity(0.45), accent.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: contrast == .increased ? 1.5 : 1
                        )
                }
                .overlay {
                    RingSelectionSurface()
                        .stroke(Color.primary.opacity(contrast == .increased ? 0 : 0.06), lineWidth: 0.5)
                }
                .modifier(PresentedSelectionRotation(angle: state.selectionAngle, state: state))
                .animation(reduceMotion ? nil : RingMotion.selection, value: state.selectionAngle)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ForEach(Array(Command.allCases.enumerated()), id: \.element) { index, command in
                let shape = Sector(index: index)
                let isSelected = state.selected == command
                Button { state.choose?(command) } label: {
                    ZStack {
                        shape.fill(.clear)
                        VStack(spacing: 9) {
                            Image(systemName: command.symbol)
                                .font(.system(size: 23, weight: isSelected ? .medium : .regular))
                                .frame(height: 26)
                            Text(command.rawValue)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                                .frame(width: 82)
                        }
                        .foregroundStyle(isSelected ? accent : Color.primary.opacity(0.82))
                        .position(position(index, size: size))
                    }
                    .contentShape(shape)
                }
                .buttonStyle(RingOptionStyle())
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
        .clipShape(Circle())
    }

    private func position(_ index: Int, size: CGFloat) -> CGPoint {
        let angle = (Double(index) * (360 / Double(Command.allCases.count)) - 90) * Double.pi / 180
        return CGPoint(x: size / 2 + cos(angle) * size * 0.35, y: size / 2 + sin(angle) * size * 0.35)
    }
}
