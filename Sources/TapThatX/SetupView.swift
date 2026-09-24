import SwiftUI
import TapCore

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection? = .tuning
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var label = "Desk double taps"
    @State private var expectedDoubleKnocks = 1

    var body: some View {
        Group {
            if selection == .calibration {
                CalibrationPane(
                    model: model,
                    calibration: model.calibration,
                    onDismissOnboarding: { selection = .tuning }
                )
            } else {
                VStack(spacing: 0) {
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        List(selection: $selection) {
                            ForEach(SettingsSection.allCases) { section in
                                Label(section.title, systemImage: section.icon)
                                    .tag(section)
                            }
                        }
                        .listStyle(.sidebar)
                        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
                    } detail: {
                        pane
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .overlay(alignment: .bottom) { scrollFade }
                    }
                    // The shelf sits below the split view in the layout, so the panes'
                    // scroll bounds end at the shelf by construction.
                    settingsFooter
                }
            }
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
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

    /// Fades the last rows of scrolled pane content so rows cut at the scroll
    /// boundary above the shelf read as intentional instead of truncated.
    private var scrollFade: some View {
        LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 28)
            .allowsHitTesting(false)
    }

    /// Floating glass shelf: live status, Pause, and the completion button.
    private var settingsFooter: some View {
        ReactorGlassContainer(spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.actionStatus, systemImage: "info.circle").font(.callout)
                    Text(model.acknowledgment).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Toggle("Pause", isOn: $model.paused).toggleStyle(.switch).fixedSize()
                Button("Enable & close") { model.enableAndCloseSettings() }
                    .reactorProminentButton().fixedSize()
                    .disabled(model.calibration.blocksActions || model.captureRemaining > 0 || model.paused || model.input == .simulated || (model.input == .sensor && model.sampleRate < 50))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .reactorGlass(in: RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous))
        }
        .padding(.top, 10)
        .padding(.horizontal, 12)
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
        }
    }
}
