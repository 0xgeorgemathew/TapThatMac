import SwiftUI
import TapCore

struct CalibrationPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calibration: CalibrationController
    @State private var surface = "Laptop"
    @State private var placement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Calibrate your taps",
                       detail: "Record your light taps and knocks, then check a suggested sensitivity with new recordings.")
            Form {
                if calibration.stage == .idle {
                    Section {
                        Text("Allow about 3–4 minutes for 16 short recordings. Use the same surface and laptop position throughout. You’ll record background movement, light taps, knocks and pairs. Actions stay paused until you finish or cancel.")
                        Picker("Contact surface", selection: $surface) {
                            Text("Laptop").tag("Laptop"); Text("Desk").tag("Desk")
                        }
                        TextField("Placement, e.g. wooden desk, laptop on stand", text: $placement)
                            .onChange(of: placement) { _, value in placement = String(value.prefix(160)) }
                        Text("XYZ motion and key timing are saved locally as you confirm or retry each step. No typed characters, audio or uploads. A short calibration cannot guarantee rejection of every everyday movement.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Begin calibration") { model.beginCalibration(surface: surface, placement: placement) }
                            .reactorProminentButton().disabled(!model.canStartCalibration || placement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let reason = model.calibrationUnavailableReason { Text(reason).foregroundStyle(.secondary) }
                    }
                } else {
                    Section {
                        ProgressView(value: Double(calibration.completedCount), total: Double(CalibrationStep.sequence.count))
                        Text("\(calibration.completedCount) of \(CalibrationStep.sequence.count) confirmed recordings")
                            .font(.caption).foregroundStyle(.secondary)
                        if let step = calibration.step, calibration.blocksActions {
                            Text(step.activity.title).font(.title2.bold())
                            Text(step.activity.instruction)
                            if step.partition == .verification { Text("Verification · the suggested setting is fixed").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if calibration.stage == .ready {
                        Section {
                            Button("Start this recording") { model.recordCalibrationTrial() }
                                .reactorProminentButton().disabled(!model.canStartCalibration)
                            if let reason = model.calibrationUnavailableReason { Text(reason).foregroundStyle(.secondary) }
                        }
                    }
                    if calibration.stage == .recording {
                        Section {
                            Text(calibration.prompt).font(.largeTitle.bold()).frame(maxWidth: .infinity, minHeight: 90)
                                .accessibilityAddTraits(.updatesFrequently)
                            ProgressView(value: calibration.progress)
                            Text("Keep watching this screen. No need to click or press a key when you tap.").foregroundStyle(.secondary)
                        }
                    }
                    if calibration.stage == .review, let trial = calibration.review {
                        Section {
                            Text(calibration.message)
                            Text("\(trial.samples.count) samples · \(trial.quality.measuredRate, specifier: "%.0f") Hz")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(trial.quality.issues, id: \.self) { Text($0).foregroundStyle(.orange) }
                            HStack {
                                Button("Yes, I did that — save & continue") { calibration.confirm() }
                                    .disabled(!calibration.canConfirm)
                                Button("Retry this step") { calibration.retry() }
                            }
                            Text("Confirm what you actually did, even if detection missed it. Retry if you tapped too early, missed the prompt, or made extra contacts.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if calibration.stage == .complete || calibration.stage == .failed {
                        Section {
                            Text(calibration.message)
                            if calibration.stage == .complete, let floor = calibration.floor {
                                Text("Suggested threshold: \(floor, specifier: "%.4f") g")
                                Text("This adjusts sensitivity for this placement. It does not identify a contact as skin or knuckle, or prove reliability on a different surface.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button(calibration.applied ? "Applied" : "Use this sensitivity") { model.applyCalibration() }
                                    .reactorProminentButton().disabled(calibration.applied || !model.canStartCalibration)
                            }
                            Button("Start a new session") { _ = calibration.cancel(at: ProcessInfo.processInfo.systemUptime) }
                        }
                    }
                    if calibration.blocksActions {
                        Section { Button("Cancel calibration") { model.cancelCalibration() } }
                    }
                }
                if let error = calibration.saveError { Section { Text(error).foregroundStyle(.red) } }
                if !calibration.message.isEmpty && calibration.stage == .ready {
                    Section { Text(calibration.message).foregroundStyle(.secondary) }
                }
                if let url = calibration.archiveURL {
                    Section {
                        Button("Show saved session") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Text("Each session has its own file. Interrupted and unconfirmed attempts are excluded from tuning. Existing sessions are never loaded as training data.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped)
        }.onDisappear {
            calibration.interrupt("The calibration screen was hidden. Please retry this recording.", at: ProcessInfo.processInfo.systemUptime)
        }
    }
}
