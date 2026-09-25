import SwiftUI
import TapCore

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection? = .tuning
    @State private var label = "Desk double taps"
    @State private var expectedDoubleKnocks = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Short bundle version for the dock footer caption.
    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        ZStack {
            // One immersive stage for every pane: real behind-window vibrancy
            // plus Calibration's radial accent glow, under all content.
            ReactorStage()

            Group {
                if selection == .calibration {
                    CalibrationPane(
                        model: model,
                        calibration: model.calibration,
                        onDismissOnboarding: { selection = .tuning }
                    )
                    // Clear the floating traffic lights without touching the
                    // calibration layout itself; the stage still fills the window.
                    .safeAreaInset(edge: .top, spacing: 0) { TrafficLightSpacer() }
                } else {
                    HStack(spacing: 8) {
                        NavDock(selection: $selection, appVersion: Self.appVersion)
                        VStack(spacing: 0) {
                            pane
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                // Keeps pane headers clear of the lights and
                                // gives the pane column a drag region.
                                .safeAreaInset(edge: .top, spacing: 0) { TrafficLightSpacer() }
                                // Scroll-edge scrim: passing content dissolves into
                                // the shelf tone instead of slicing hard at its edge.
                                .overlay(alignment: .bottom) { paneScrim }
                                // Dock selection drives the pane swap: the
                                // incoming pane springs up, the outgoing fades.
                                .transition(paneTransition)
                            settingsFooter
                        }
                        // The settings column participates in pane swaps while
                        // the dock remains fixed on the left.
                        .animation(paneAnimation, value: selection)
                    }
                }
            }
        }
        // The whole top edge above the stage is a drag region; the dock rail
        // keeps clear of it, so window dragging works everywhere else.
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: 26)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 560, idealHeight: 680)
        // No opaque window paint: ReactorStage's representable makes the
        // window clear with a behind-window blur, so the translucent glass
        // panels and dock float on real vibrancy.
        .background(SettingsWindowReader(model: model)).tint(ReactorTheme.accent)
        .onAppear {
            model.refreshPermissions()
            if !model.accessibilityPermission || !model.typingPermission {
                selection = .permissions
            } else if !model.hasSeenCalibrationOnboarding {
                selection = .calibration
            }
        }
    }

    /// Spring the incoming pane up 12 pt from 0.995 scale; the outgoing pane
    /// only fades. Reduce Motion: opacity-only both ways.
    private var paneTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.995)),
            removal: .opacity
        )
    }

    private var paneAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.4, dampingFraction: 0.85)
    }

    @ViewBuilder private var pane: some View {
        switch selection ?? .tuning {
        case .permissions: PermissionsPane(model: model)
        case .tuning:      TuningPane(model: model, openCalibration: { selection = .calibration })
        case .actions:     ActionsPane(model: model)
        case .calibration: EmptyView()
        case .recordings:  RecordingsPane(model: model,
                                          label: $label,
                                          expectedDoubleKnocks: $expectedDoubleKnocks)
        case .input:       InputPane(model: model)
        case .diagnostics: DiagnosticsPane(model: model, setSelection: { selection = $0 })
        }
    }

    /// Bottom dissolve so scrolling pane content fades into the shelf tone.
    private var paneScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.72), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .padding(.bottom, -6)
    }

    /// Floating glass shelf: live status, Pause, and the completion button.
    private var settingsFooter: some View {
        ReactorGlassContainer(spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.actionStatus, systemImage: "info.circle")
                        .font(.callout)
                        .contentTransition(.opacity)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.25),
                            value: model.actionStatus
                        )
                    // The acknowledgment usually restates the status; only show
                    // it as a second line when it adds distinct detail. Each
                    // fresh acknowledgment pops in with a spring checkmark.
                    if model.acknowledgment != model.actionStatus {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(ReactorTheme.accent)
                            Text(model.acknowledgment).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .id(model.acknowledgment)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7),
                    value: model.acknowledgment
                )
                Spacer(minLength: 8)
                Toggle("Pause actions", isOn: $model.paused)
                    .toggleStyle(.switch)
                    // Native control, accent-tinted so the switch matches
                    // the one accent when on.
                    .tint(ReactorTheme.accent)
                    .fixedSize()
                Button("Enable & close") { model.enableAndCloseSettings() }
                    .buttonStyle(.reactorButton(prominent: true)).fixedSize()
                    .disabled(model.calibration.blocksActions || model.captureRemaining > 0 || model.paused || model.input == .simulated || (model.input == .sensor && model.sampleRate < 50))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .reactorGlass(in: ReactorTheme.panelShape)
            .reactorEdgeHighlight(in: ReactorTheme.panelShape)
            // Shadow lift: macOS 26+ glass draws its own; below that the
            // shelf needs one to read as floating, like the nav rail.
            .reactorGlassLift()
        }
        // Align the shelf with PaneScaffold's content column.
        .padding(.top, 10)
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }
}

// Track the whole settings window, including sections that do not contain a graph.
private struct SettingsWindowReader: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> WindowView { WindowView(model: model) }
    func updateNSView(_ view: WindowView, context: Context) {}
    final class WindowView: NSView {
        weak var model: AppModel?
        init(model: AppModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            model?.setupWindow = window
            // Scene-level clear-window setup: applied as early as the shell
            // can reach the window, around/before the stage's vibrancy layer
            // installs itself. Idempotent — the vibrancy layer re-asserts
            // the same configuration and keeps it live.
            if let window { ReactorWindowConfig.apply(to: window) }
        }
    }
}

/// Clear strip that reserves the traffic-light area of the transparent
/// titlebar. It also acts as a drag region: the window is full-size content,
/// so without it the top edge would have nothing to grab.
private struct TrafficLightSpacer: View {
    var body: some View {
        WindowDragArea()
            .frame(height: 30)
            .frame(maxWidth: .infinity)
    }
}

/// Transparent AppKit view that only moves the window; it draws nothing and
/// handles no other events.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
