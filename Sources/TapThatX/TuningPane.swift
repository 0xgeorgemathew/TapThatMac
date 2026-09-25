import SwiftUI
import TapCore

struct TuningPane: View {
    @ObservedObject var model: AppModel
    let openCalibration: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Live motion envelope in g from `AppModel.liveAmplitude` (~10 Hz).
    @State private var liveAmplitude = 0.0
    /// In-flight one-shot tap pulse rings over the graph.
    @State private var tapPulses: [UUID] = []
    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Find your tap",
                           detail: "Tap twice while watching the signal. Actions stay paused while settings are open.")

                VStack(spacing: 20) {
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
            guard !reduceMotion else { return }
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

            MotionGraphView(model: model)
                .frame(height: 300)
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
                    Button("Reset threshold") { model.setAmplitudeFloor(0.0175) }
                        .buttonStyle(.reactorButtonCompact)
                }
            }

            Text("Drag the gold line just above everyday movement. The dashed line shows the background-noise floor; a peak still needs valid double-tap timing.")
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
                    Text(model.activeCalibrationProfile?.name ?? "No tap profile")
                        .font(.headline)
                    Text(model.activeCalibrationProfile == nil
                         ? "Teach TapThatX your light and natural taps."
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

            Text("Run calibration again whenever your taps or your setup change.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .reactorCard()
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detection behavior")
                .font(.headline)

            behaviorRow(
                title: "Sampling rate",
                detail: model.sampleRate < 50
                    ? "This rate records slow motion only. Brief taps can disappear between samples, so actions are unavailable. Choose 50 Hz or higher to test triggers."
                    : "Guided Calibration uses 800 Hz to sample brief contacts. Lower rates can miss taps between samples and remain experimental."
            ) {
                ReactorGlassMenuPicker(
                    title: "Sampling rate",
                    options: SamplingRate.options,
                    label: { rate in
                        "\(rate) Hz\(rate < 50 ? " (recording only)" : rate < 800 ? " (experimental)" : " (baseline)")"
                    },
                    selection: $model.sampleRate
                )
                .frame(maxWidth: .infinity)
                .disabled(model.captureRemaining > 0 || model.input != .sensor)
            }

            Divider()
                .overlay(Color.primary.opacity(0.08))

            behaviorRow(
                title: "Ignore impacts near typing",
                detail: "Uses key timing only. Wait briefly after typing before tapping. A lower threshold is experimental and can also increase missed taps from ringing."
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
