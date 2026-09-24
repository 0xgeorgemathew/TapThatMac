import SwiftUI
import TapCore

struct TuningPane: View {
    @ObservedObject var model: AppModel
    let openCalibration: () -> Void

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ReactorBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PaneHeader(title: "Find your tap",
                               detail: "Tap twice while watching the signal. Actions stay paused while settings are open.")

                    ReactorGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            profileCard
                            signalCard
                            sampleRateCard
                            typingCard
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 26)).foregroundStyle(ReactorTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(ReactorTheme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.activeCalibrationProfile?.name ?? "No tap profile")
                        .font(.headline)
                    Text(model.activeCalibrationProfile == nil
                         ? "Teach TapThatX your light and natural taps."
                         : "Your personal tap settings are active.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.activeCalibrationProfile == nil ? "Calibrate…" : "Recalibrate…") {
                    openCalibration()
                }
                .buttonStyle(.reactorBigButton(prominent: true))
            }

            if model.calibrationProfiles.count > 1 {
                Picker("Tap profile", selection: Binding(
                    get: { model.activeCalibrationProfile?.id },
                    set: { id in
                        if let id { model.activateCalibrationProfile(id) }
                        else { model.keepCurrentSettingsWithoutProfile() }
                    }
                )) {
                    Text("Current custom settings").tag(Optional<UUID>.none)
                    ForEach(model.calibrationProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            }

            Text("Run calibration again whenever your taps or setup feel different.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.status, systemImage: "waveform")
                Spacer()
                Text("\(model.rate, specifier: "%.1f") Hz received").monospacedDigit().foregroundStyle(.secondary)
            }.font(.callout)

            MotionGraphView(model: model)
                .frame(height: 260)
                .clipShape(surface)
                .reactorGlass(in: surface)
                .reactorEdgeHighlight(in: surface)

            HStack {
                Text("Threshold  \(model.amplitudeFloor, specifier: "%.4f") g").monospacedDigit()
                Spacer()
                Button("Try light taps") { model.setAmplitudeFloor(0.008) }
                    .reactorGlassButton()
                Button("Reset") { model.setAmplitudeFloor(0.0175) }
                    .reactorGlassButton()
            }

            Text("Drag the solid line above everyday movement. Lower it gradually for lighter taps. The dashed line includes background noise; a peak still needs the right timing.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var sampleRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sampling rate", selection: $model.sampleRate) {
                ForEach(SamplingRate.options, id: \.self) { rate in
                    Text("\(rate) Hz\(rate < 50 ? " (recording only)" : rate < 800 ? " (experimental)" : " (baseline)")").tag(rate)
                }
            }.disabled(model.captureRemaining > 0 || model.input != .sensor)

            Text(model.sampleRate < 50
                 ? "This rate records slow motion only. Brief taps can disappear between samples, so actions are unavailable. Choose 50 Hz or higher to test triggers."
                 : "Guided Calibration uses 800 Hz to sample brief contacts. Lower rates can miss taps between samples and remain experimental.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var typingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Ignore impacts near typing", isOn: $model.suppressTyping)
            Text("Uses key timing only. Wait briefly after typing before tapping. A lower threshold is experimental and can also increase missed taps from ringing.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }
}
