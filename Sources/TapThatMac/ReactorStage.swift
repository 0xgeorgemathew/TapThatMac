import AppKit
import SwiftUI

/// The immersive stage shared by every pane and the Calibration branch:
/// a real behind-window vibrancy layer plus Calibration's radial accent
/// glow, painted under all content at the shell level.
///
/// The chain is strictly translucent: vibrancy at the bottom, the accent
/// glow (`ReactorTheme.accent.opacity(0.13)` fading to `.clear`, no opaque
/// base) above it, content on top. Nothing opaque is painted anywhere in
/// the chain, so the blurred desktop and other windows show through the
/// whole window. Pass a `glowCenter` to bias the glow per pane; the
/// default centers it on the window.
struct ReactorStage: View {
    var glowCenter: UnitPoint = .center

    var body: some View {
        ZStack {
            WindowVibrancy()
            RadialGradient(
                colors: [ReactorTheme.accent.opacity(0.13), .clear],
                center: glowCenter,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// Window configuration that makes behind-window vibrancy real: the window
/// is non-opaque with a clear background so the vibrancy view can blend
/// with the actual backdrop, and its shadow is invalidated because the
/// shadow shape changes once the window turns transparent.
///
/// Reduce Transparency fallback: the window goes back to an opaque
/// `windowBackgroundColor`.
///
/// Applied from two places on purpose. The scene shell applies it as early
/// as it can reach the window, and the vibrancy layer re-applies and
/// re-asserts it — SwiftUI finishes configuring scene windows (background,
/// titlebar) after the content hierarchy is installed, and that late
/// configuration is what otherwise paints an opaque surface over the
/// vibrancy and kills the backdrop bleed.
enum ReactorWindowConfig {
    static func apply(to window: NSWindow) {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        window.isOpaque = reduceTransparency
        window.backgroundColor = reduceTransparency ? .windowBackgroundColor : .clear
        window.titlebarAppearsTransparent = !reduceTransparency
        window.hasShadow = true
        window.invalidateShadow()
    }
}

/// Makes the hosting window a true vibrancy surface: non-opaque with a
/// clear background and a full-window behind-window blur
/// (`NSVisualEffectView`, material `.underWindowBackground`, blending
/// `.behindWindow`) underneath the SwiftUI content, so the wallpaper and
/// other windows visibly blur through the whole window.
///
/// Reduce Transparency fallback: the window is reconfigured to opaque
/// `windowBackgroundColor` and the effect layer is hidden. The setting is
/// read at layer setup and observed live through
/// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
private struct WindowVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> VibrancyView { VibrancyView() }
    func updateNSView(_ view: VibrancyView, context: Context) {
        view.applyDisplayOptions()
    }

    final class VibrancyView: NSView {
        private let effect = NSVisualEffectView()
        private var optionsObserver: NSObjectProtocol?
        private var windowObserver: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // Behind-window blur: wallpaper and other windows bleed through
            // the entire window. `.active` keeps the material looking alive
            // even when the window is not key.
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.translatesAutoresizingMaskIntoConstraints = false
            addSubview(effect)
            NSLayoutConstraint.activate([
                effect.leadingAnchor.constraint(equalTo: leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: trailingAnchor),
                effect.topAnchor.constraint(equalTo: topAnchor),
                effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                applyDisplayOptions()
                // SwiftUI's own scene-window configuration lands after the
                // content hierarchy is installed and would repaint the
                // window opaque over the vibrancy; re-assert the clear
                // setup on the next runloop turn so the backdrop keeps
                // bleeding through.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window === window else { return }
                    self.applyDisplayOptions()
                }
                registerObservers(in: window)
            } else {
                removeObservers()
            }
        }

        /// Reconfigures the window for the current Reduce Transparency state.
        func applyDisplayOptions() {
            guard let window else { return }
            let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            effect.isHidden = reduceTransparency
            ReactorWindowConfig.apply(to: window)
            clearOpaqueLayerBackgrounds()
        }

        /// The SwiftUI scene hosts this view inside an `NSHostingView`; an
        /// opaque layer background anywhere between here and the window's
        /// content view would sit above the vibrancy and hide the backdrop.
        /// Remove explicit background colors from that ancestor chain only —
        /// view structure is untouched.
        private func clearOpaqueLayerBackgrounds() {
            var ancestor = superview
            while let view = ancestor {
                if view.layer?.backgroundColor != nil {
                    view.layer?.backgroundColor = nil
                }
                ancestor = view.superview
            }
        }

        private func registerObservers(in window: NSWindow) {
            removeObservers()
            let center = NotificationCenter.default
            optionsObserver = center.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applyDisplayOptions()
            }
            // Key-window transitions re-run window compositing; re-asserting
            // the clear setup there is free and keeps the window transparent.
            windowObserver = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.applyDisplayOptions()
            }
        }

        private func removeObservers() {
            if let optionsObserver {
                NotificationCenter.default.removeObserver(optionsObserver)
                self.optionsObserver = nil
            }
            if let windowObserver {
                NotificationCenter.default.removeObserver(windowObserver)
                self.windowObserver = nil
            }
        }

        deinit {
            // The block-based observers are safe to remove from any thread.
            if let optionsObserver { NotificationCenter.default.removeObserver(optionsObserver) }
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        }
    }
}
