import SwiftUI

struct RecordingsPane: View {
    @ObservedObject var model: AppModel
    @Binding var label: String
    @Binding var expectedDoubleKnocks: Int
    private let labels = ["Desk double taps", "Chassis double knocks", "Left double taps", "Right double taps", "Light double taps", "Table shaking", "Moving objects", "Typing", "Quiet interval"]

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ReactorBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PaneHeader(title: "Diagnostic recordings",
                               detail: "Save motion for troubleshooting. Use Calibration for guided personal tuning.")

                    ReactorGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            introCard
                            setupCard
                            captureCard
                            recordingsCard
                        }
                    }

                    Text("Saved locally with a unique filename in Library/Application Support/TapThatX. These unverified recordings are never used for calibration. XYZ motion and key timing only; no characters or uploads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var introCard: some View {
        Text("Each recording lasts 15 seconds. Keep still for 3 seconds, perform the labeled activity, then let the desk settle. For tap labels, make one double-tap. For movement labels, make no deliberate taps.")
            .font(.callout)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .reactorGlass(in: surface)
            .reactorEdgeHighlight(in: surface)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Activity", selection: $label) {
                ForEach(labels, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: label) { _, value in expectedDoubleKnocks = value.contains("double") ? 1 : 0 }
            Stepper("Intended double-taps: \(expectedDoubleKnocks)", value: $expectedDoubleKnocks, in: 0...5)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var captureCard: some View {
        HStack(spacing: 14) {
            Button(model.captureRemaining > 0 ? "Recording: \(model.captureRemaining)s" : "Record 15 seconds") {
                model.startCapture(label: label, purpose: "Diagnostic", expectedDoubleKnocks: expectedDoubleKnocks)
            }
            .buttonStyle(.reactorBigButton(prominent: true))
            .disabled(model.calibration.blocksActions || model.captureRemaining > 0 || model.paused || model.status != "Streaming accelerometer")
            if model.captureRemaining > 0 {
                Button("Stop") { model.diagnostics.finishCapture() }
                    .buttonStyle(.reactorBigButton)
            }
            Spacer()
            Button("Save recordings") { model.saveDiagnosticRecordings() }
                .buttonStyle(.reactorBigButton)
                .disabled(model.captures.isEmpty || model.captureRemaining > 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    @ViewBuilder private var recordingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.captures.isEmpty {
                ContentUnavailableView("No recordings this session", systemImage: "waveform.path")
            }
            ForEach(Array(model.captures.enumerated()), id: \.offset) { _, capture in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(capture.label).fontWeight(.medium)
                        Text("\(capture.purpose) • \(capture.samples.count) samples").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(capture.expectedDoubleKnocks ?? 0) intended").monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }
}
