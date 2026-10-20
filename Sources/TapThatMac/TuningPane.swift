import SwiftUI
import AppKit
import TapCore

struct TuningPane: View {
    @ObservedObject var model: AppModel
    let openCalibration: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Live motion envelope in g from `AppModel.liveAmplitude` (~10 Hz).
    @State private var liveAmplitude = 0.0
    /// In-flight one-shot tap pulse rings over the graph.
    @State private var tapPulses: [UUID] = []
    @State private var graphScale: MotionGraphScale = .detail
    @State private var graphDuration = 8.0
    @State private var graphHeld = false
    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Live",
                           detail: "Watch the motion trace and adjust tap sensitivity.")

                VStack(spacing: 20) {
                    if !model.accessibilityPermission || !model.typingPermission { permissionCard }
                    if model.status != "Streaming accelerometer" && !model.paused { connectionRecoveryCard }
                    signalCard
                    profileCard
                    behaviorCard
                }
            }
        }
        .onReceive(model.liveAmplitude) { value in
            liveAmplitude = value
        }
        .onReceive(model.tapDetected) {
            guard !reduceMotion, !graphHeld else { return }
            let id = UUID()
            tapPulses.append(id)
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                tapPulses.removeAll { $0 == id }
            }
        }
    }

    /// Live motion graph, status and recognition metrics, and threshold controls.
    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Label(model.status, systemImage: "waveform")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    LiveMotionIndicator(
                        live: liveAmplitude > model.amplitudeFloor,
                        reduceMotion: reduceMotion
                    )
                }
                Spacer()
                HStack(spacing: 14) {
                    signalMetric("Rate", value: String(format: "%.1f Hz", model.rate))
                    signalMetric("Taps", value: "\(model.knocks)")
                    signalMetric("Pairs", value: "\(model.recognizedPairs)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.rate)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.knocks)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.recognizedPairs)

            HStack(spacing: 12) {
                Picker("Signal scale", selection: $graphScale) {
                    ForEach(MotionGraphScale.allCases, id: \.self) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
                Picker("Time window", selection: $graphDuration) {
                    Text("2 s").tag(2.0)
                    Text("8 s").tag(8.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
                Spacer(minLength: 0)
                Button(graphHeld ? "Resume live" : "Hold trace") {
                    tapPulses.removeAll()
                    graphHeld.toggle()
                }
                .buttonStyle(.reactorButtonCompact)
                .help("Hold the graph for inspection. Sensor sampling continues.")
            }

            MotionGraphView(model: model, scale: graphScale, duration: graphDuration, held: graphHeld)
                .frame(height: 340)
                .clipShape(ReactorTheme.cardShape)
                .overlay(TapPulseLayer(pulses: tapPulses, reduceMotion: reduceMotion))

            HStack {
                Text("Threshold")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("\(model.amplitudeFloor, specifier: "%.4f") g")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.851, green: 0.639, blue: 0.255))
                Spacer()
                ReactorGlassContainer(spacing: 8) {
                    Button("Set for light taps") { model.setAmplitudeFloor(0.008) }
                        .buttonStyle(.reactorButtonCompact)
                        .disabled(graphHeld)
                    Button("Reset threshold") { model.setAmplitudeFloor(0.0175) }
                        .buttonStyle(.reactorButtonCompact)
                        .disabled(graphHeld)
                }
            }

            Text("Hold the trace and hover to inspect peaks. Drag the gold threshold, or focus the graph and use arrow keys (Shift for fine steps).")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Text("Cyan shows motion; violet shows the light-tap impulse when enabled. Gold dashes mark the motion gate; violet dots mark the light-tap gate. A crossing alone does not confirm a tap.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .reactorCard()
    }

    private func signalMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 18)).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.05), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.activeCalibrationProfile?.name ?? "No calibration profile")
                        .font(.headline)
                    Text(model.activeCalibrationProfile == nil
                         ? "Calibrate to match your taps."
                         : "Your personal tap settings are active.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.activeCalibrationProfile == nil {
                    Button("Calibrate…", action: openCalibration)
                        .buttonStyle(.reactorButton(prominent: true))
                } else {
                    Button("Recalibrate…", action: openCalibration)
                        .buttonStyle(.reactorButton)
                }
            }

            if model.calibrationProfiles.count > 1 {
                HStack(spacing: 12) {
                    Text("Tap profile")
                        .font(.callout)
                    Spacer(minLength: 8)
                    ReactorGlassMenuPicker(
                        title: "Tap profile",
                        options: [Optional<UUID>.none] + model.calibrationProfiles.map(\.id),
                        label: { id in
                            guard let id,
                                  let profile = model.calibrationProfiles.first(where: { $0.id == id })
                            else { return "Current custom settings" }
                            return profile.name
                        },
                        selection: Binding(
                            get: { model.activeCalibrationProfile?.id },
                            set: { id in
                                if let id { model.activateCalibrationProfile(id) }
                                else { model.keepCurrentSettingsWithoutProfile() }
                            }
                        )
                    )
                    .frame(width: 300)
                }
            }

            Text("Recalibrate if your tap style or setup changes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .reactorCard()
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detection behavior")
                .font(.headline)

            behaviorRow(
                title: "Ignore impacts near typing",
                detail: "Uses key timing only. Wait briefly after typing before tapping."
            ) {
                Toggle("Ignore impacts near typing", isOn: $model.suppressTyping)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(ReactorTheme.accent)
                    .fixedSize()
            }
        }
        .reactorCard()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permissions", systemImage: "checkmark.shield").font(.headline)
            if !model.accessibilityPermission {
                HStack {
                    Text("Accessibility is needed to run system actions.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Accessibility") { openPrivacy("Privacy_Accessibility") }
                        .buttonStyle(.reactorButtonCompact)
                }
            }
            if !model.typingPermission {
                HStack {
                    Text("Input Monitoring helps suppress taps during typing.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Input Monitoring") { openPrivacy("Privacy_ListenEvent") }
                        .buttonStyle(.reactorButtonCompact)
                }
            }
            Button("Check permissions again") { model.refreshPermissions() }
                .buttonStyle(.plain).font(.caption)
        }
        .reactorCard()
    }

    private var connectionRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sensor connection", systemImage: "waveform.path")
                .font(.headline)
            Text(model.status).font(.callout).foregroundStyle(.secondary)
            if model.input == .helper {
                Text(model.helperStatus).font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items") { model.openHelperApprovalSettings() }
                    .buttonStyle(.reactorButtonCompact)
            }
            Button("Reconnect sensor") { model.reconnectSensor() }
                .buttonStyle(.reactorButtonCompact)
        }
        .reactorCard()
    }

    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func behaviorRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                control()
            }
            .frame(width: 240, alignment: .trailing)
        }
    }
}
