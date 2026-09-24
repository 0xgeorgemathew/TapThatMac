import SwiftUI
import TapCore

struct TuningPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Find your tap",
                       detail: "Tap twice while watching the signal. Actions stay paused while settings are open.")
            Form {
                Section {
                    HStack {
                        Label(model.status, systemImage: "waveform")
                        Spacer()
                        Text("\(model.rate, specifier: "%.1f") Hz received").monospacedDigit().foregroundStyle(.secondary)
                    }.font(.callout)
                    MotionGraphView(model: model).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Text("Threshold  \(model.amplitudeFloor, specifier: "%.4f") g").monospacedDigit()
                        Spacer()
                        Button("Try light taps") { model.setAmplitudeFloor(0.008) }
                        Button("Reset") { model.setAmplitudeFloor(0.0175) }
                    }
                } footer: {
                    // Grouped-form footers misalign on macOS: the block needs a
                    // leading frame and wrapped lines need leading text alignment.
                    Text("Drag the solid line above everyday movement. Lower it gradually for lighter taps. The dashed line includes background noise; a peak still needs the right timing.")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Picker("Sampling rate", selection: $model.sampleRate) {
                        ForEach(SamplingRate.options, id: \.self) { rate in
                            Text("\(rate) Hz\(rate < 50 ? " (recording only)" : rate < 800 ? " (experimental)" : " (baseline)")").tag(rate)
                        }
                    }.disabled(model.captureRemaining > 0 || model.input != .sensor)
                } footer: {
                    Text(model.sampleRate < 50
                         ? "This rate records slow motion only. Brief taps can disappear between samples, so actions are unavailable. Choose 50 Hz or higher to test triggers."
                         : "Guided Calibration uses 800 Hz to sample brief contacts. Lower rates can miss taps between samples and remain experimental.")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Toggle("Ignore impacts near typing", isOn: $model.suppressTyping)
                } footer: {
                    Text("Uses key timing only. Wait briefly after typing before tapping. A lower threshold is experimental and can also increase missed taps from ringing.")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
    }
}
