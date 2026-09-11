import SwiftUI
import ServiceManagement
import TapCore

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var page = "Tuning"
    @State private var label = "Desk double taps"
    @State private var expectedDoubleKnocks = 1
    @State private var purpose = "Calibration"
    private let pages = ["Permissions", "Tuning", "Actions", "Recordings", "Advanced"]
    private let labels = ["Desk double taps", "Chassis double knocks", "Left double taps", "Right double taps", "Light double taps", "Table shaking", "Moving objects", "Typing", "Quiet interval"]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path").font(.system(size: 28, weight: .medium)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TapThatX").font(.system(size: 25, weight: .semibold))
                    Text("Make a small tap count.").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Pause", isOn: $model.paused).toggleStyle(.switch).fixedSize()
            }.padding(24)
            Picker("Settings section", selection: $page) {
                ForEach(pages, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case "Permissions": PermissionSetupView(model: model)
                    case "Actions": actions
                    case "Recordings": recordings
                    case "Advanced": advanced
                    default: tuning
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.actionStatus, systemImage: "info.circle").font(.callout)
                    Text(model.acknowledgment).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button("Enable & close") { model.enableAndCloseSettings() }
                    .buttonStyle(.borderedProminent).fixedSize()
                    .disabled(model.captureRemaining > 0 || model.paused || model.input == .simulated || (model.input == .sensor && model.sampleRate < 50))
            }.padding(20)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 640, idealHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowReader(model: model)).tint(.mint)
        .onAppear {
            model.refreshPermissions()
            if !model.accessibilityPermission || !model.typingPermission { page = "Permissions" }
        }
    }
    private var tuning: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Find your tap", "Tap twice while watching the signal. Actions stay paused while settings are open.")
            HStack {
                Label(model.status, systemImage: "waveform")
                Spacer()
                Text("\(model.rate, specifier: "%.1f") Hz received").monospacedDigit().foregroundStyle(.secondary)
            }.font(.callout)
            MotionGraphView(model: model).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("Threshold  \(model.amplitudeFloor, specifier: "%.3f") g").monospacedDigit()
                Spacer()
                Button("Try light taps") { model.setAmplitudeFloor(0.008) }
                Button("Reset") { model.setAmplitudeFloor(0.0175) }
            }
            Text("Drag the solid line above everyday movement. Lower it gradually for lighter taps. The dashed line includes background noise; a peak still needs the right timing.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            rateControls
            Toggle("Ignore impacts near typing", isOn: $model.suppressTyping)
            Text("Uses key timing only. Wait briefly after typing before tapping. A lower threshold is experimental and can also increase missed taps from ringing.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var rateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Sampling rate", selection: $model.sampleRate) {
                ForEach(SamplingRate.options, id: \.self) { rate in
                    Text("\(rate) Hz\(rate < 50 ? " (recording only)" : rate < 800 ? " (experimental)" : " (baseline)")").tag(rate)
                }
            }.disabled(model.captureRemaining > 0 || model.input != .sensor)
            Text(model.sampleRate < 50
                 ? "This rate records slow motion only. Brief taps can disappear between samples, so actions are unavailable. Choose 50 Hz or higher to test triggers."
                 : "800 Hz is the tested baseline. Lower rates reduce sensor work but may miss taps. Compare recordings before keeping a lower rate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Double-tap action", "Choose one action, or open the ring to choose each time.")
            Picker("Double-tap", selection: $model.doubleTapAction) {
                ForEach(DoubleTapAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if model.doubleTapAction == .ring {
                Text("Double-tap opens all actions. Single tap moves clockwise; double-tap chooses the highlighted action.")
                Text("Right / Down move clockwise. Left / Up move counterclockwise. All arrows wrap around. Return chooses; Escape cancels. You can also point and click.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Single taps move after a short pause so a double-tap can choose without moving first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.doubleTapAction == .lock {
                Text("Lock and Play / Pause open the ring, move to the action, and show a press before executing. Escape cancels the animation. A lock confirmation appears when you unlock.")
                    .foregroundStyle(.secondary)
            }
            if model.doubleTapAction.command?.assistantIntent != nil {
                Label("ChatGPT controls · Experimental", systemImage: "sparkles")
                Text("Requires a matching control in ChatGPT. Missing or ambiguous controls do nothing. Browser support requires a focused chatgpt.com page.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Check controls") { model.inspectAssistantControls() }
            }
            Divider()
            Toggle("Enable system actions", isOn: $model.actionsEnabled)
            Text("Settings and recordings temporarily pause actions. Enable & close finishes calibration and resumes your selected behavior.").font(.callout).foregroundStyle(.secondary)
            Button("Preview ring") { model.previewRing() }
            Text("Left and right labels are available for recording. They do not yet select different actions.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var recordings: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Build your baseline", "Record light taps, left and right pairs, and everyday movement separately.")
            Text("Each recording lasts 15 seconds. Keep still for 3 seconds, perform the labeled activity, then let the desk settle. For tap labels, make one double-tap. For movement labels, make no deliberate taps.")
                .font(.callout)
            Picker("Activity", selection: $label) {
                ForEach(labels, id: \.self) { Text($0).tag($0) }
            }.onChange(of: label) { _, value in expectedDoubleKnocks = value.contains("double") ? 1 : 0 }
            Picker("Dataset", selection: $purpose) {
                Text("Calibration").tag("Calibration"); Text("Verification").tag("Verification")
            }
            Stepper("Intended double-taps: \(expectedDoubleKnocks)", value: $expectedDoubleKnocks, in: 0...5)
            HStack {
                Button(model.captureRemaining > 0 ? "Recording: \(model.captureRemaining)s" : "Record 15 seconds") {
                    model.startCapture(label: label, purpose: purpose, expectedDoubleKnocks: expectedDoubleKnocks)
                }.disabled(model.captureRemaining > 0 || model.paused || model.status != "Streaming accelerometer")
                if model.captureRemaining > 0 { Button("Stop") { model.diagnostics.finishCapture() } }
                Spacer()
                Button("Save dataset") { model.saveCalibration() }.disabled(model.captures.isEmpty || model.captureRemaining > 0)
            }
            if model.captures.isEmpty {
                Label("No recordings this session", systemImage: "waveform.path").foregroundStyle(.secondary).padding(.vertical, 16)
            }
            ForEach(Array(model.captures.enumerated()), id: \.offset) { _, capture in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(capture.label).fontWeight(.medium)
                        Text("\(capture.purpose) • \(capture.samples.count) samples").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(capture.expectedDoubleKnocks ?? 0) intended").monospacedDigit()
                }.padding(.vertical, 4)
            }
            Text("Saved locally in Library/Application Support/TapThatX/calibration-captures.json. Saving replaces the prior dataset. XYZ motion and key timing only; no characters or uploads. Recordings do not train the detector automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Connection & diagnostics", model.diagnostics.model)
            Picker("Input", selection: $model.input) {
                ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack { Text(model.status); Spacer(); Button("Reconnect") { model.restart() } }
            if model.input == .simulated {
                HStack { Button("Single tap") { model.simulateKnock() }; Button("Double-tap") { model.simulateDouble() } }
            }
            if model.input == .helper {
                Text(model.helperStatus)
                HStack {
                    Button("Register helper") { model.installHelper() }
                    Button("Approval settings") { SMAppService.openSystemSettingsLoginItems() }
                    Button("Remove helper") { model.removeHelper() }
                }
            }
            Divider()
            Button("Manage permissions") { page = "Permissions" }
            Divider()
            HStack {
                Button("Missed tap") { model.mark("Missed tap; \(model.preset.rawValue)") }
                Button("False trigger") { model.mark("False trigger; \(model.preset.rawValue)") }
                Spacer()
                Button("Export…") { model.export() }
                Button("Clear log") { model.diagnostics.clear() }
            }
            ForEach(model.recentEvents) { event in
                Text("\(event.time, specifier: "%.2f")  \(event.kind): \(event.detail)")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
        }
    }
    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
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
