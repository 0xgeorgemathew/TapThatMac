import SwiftUI

struct RecordingsPane: View {
    @ObservedObject var model: AppModel
    @Binding var label: String
    @Binding var expectedDoubleKnocks: Int
    private let labels = ["Desk double taps", "Chassis double knocks", "Left double taps", "Right double taps", "Light double taps", "Table shaking", "Moving objects", "Typing", "Quiet interval"]

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Diagnostic recordings",
                           detail: "Save motion for troubleshooting. Use Calibration for guided personal tuning.")

                VStack(spacing: 20) {
                    introCard
                    setupCard
                    captureCard
                    recordingsCard
                }

                Text("Saved locally with a unique filename in Library/Application Support/TapThatX. These unverified recordings are never used for calibration. XYZ motion and key timing only; no characters or uploads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var introCard: some View {
        Text("Each recording lasts 15 seconds. Keep still for 3 seconds, perform the labeled activity, then let the desk settle. For tap labels, make one double-tap. For movement labels, make no deliberate taps.")
            .font(.callout)
            .reactorCard()
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReactorGlassMenuPicker(
                title: "Activity",
                options: labels,
                label: { $0 },
                selection: $label
            )
            .frame(minWidth: 300, maxWidth: 420)
            .onChange(of: label) { _, value in expectedDoubleKnocks = value.contains("double") ? 1 : 0 }
            Stepper("Intended double-taps: \(expectedDoubleKnocks)", value: $expectedDoubleKnocks, in: 0...5)
        }
        .reactorCard()
    }

    private var captureCard: some View {
        ReactorGlassContainer(spacing: 12) {
            HStack(spacing: 16) {
                Button(model.captureRemaining > 0 ? "Recording: \(model.captureRemaining)s" : "Record 15 seconds") {
                    model.startCapture(label: label, purpose: "Diagnostic", expectedDoubleKnocks: expectedDoubleKnocks)
                }
                .buttonStyle(.reactorButton(prominent: true))
                .disabled(model.calibration.blocksActions || model.captureRemaining > 0 || model.paused || model.status != "Streaming accelerometer")
                if model.captureRemaining > 0 {
                    Button("Stop") { model.diagnostics.finishCapture() }
                        .buttonStyle(.reactorButton)
                }
                Spacer()
                Button("Save recordings") { model.saveDiagnosticRecordings() }
                    .buttonStyle(.reactorButton)
                    .disabled(model.captures.isEmpty || model.captureRemaining > 0)
            }
        }
        .reactorCard()
    }

    @ViewBuilder private var recordingsCard: some View {
        Group {
            if model.captures.isEmpty {
                ContentUnavailableView("No recordings this session", systemImage: "waveform.path")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
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
            }
        }
        .reactorCard()
    }
}
