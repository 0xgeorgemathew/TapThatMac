import SwiftUI
import AppKit
import TapCore

struct TuningPane: View {
    @ObservedObject var model: AppModel
    let openCalibration: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var graphScale: MotionGraphScale = .detail
    @State private var graphDuration = 8.0
    @State private var graphHeld = false
    /// Bumped on every tap and double-tap; drives the counters' brief glow.
    @State private var tapPulse = 0
    @State private var pairPulse = 0

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(title: "Live", detail: "Every tap the sensor feels, as it happens.") {
                    let verdict = model.liveVerdict
                    StatusBadge(title: verdict.title, color: verdict.color, pulsing: verdict.pulsing)
                        .animation(Motion.reduced(Motion.fade, reduceMotion), value: verdict)
                }
                .padding(.bottom, 4)

                if !model.accessibilityPermission || !model.typingPermission { permissionCard }
                if model.status != "Streaming accelerometer" && !model.paused && model.input != .simulated {
                    connectionCard
                }
                signalCard
                profileCard
                behaviorCard
            }
        }
        .onReceive(model.tapDetected) { tapPulse += 1 }
        .onReceive(model.doubleTapRecognized) { pairPulse += 1 }
    }

    // MARK: Signal

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 0) {
                Stat(value: "\(model.knocks)", label: "taps", pulse: tapPulse, color: Theme.signal)
                Spacer(minLength: 20)
                Stat(value: "\(model.recognizedPairs)", label: "double-taps", pulse: pairPulse, color: Theme.signal)
                Spacer(minLength: 20)
                Stat(value: model.rate > 0 ? String(format: "%.0f", model.rate) : "–",
                     unit: "Hz", label: "sample rate", pulse: 0, color: Theme.ink)
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
                controls
            }

            MotionGraphView(model: model, scale: graphScale, duration: graphDuration, held: graphHeld)
                .frame(height: 300)

            HStack(spacing: 18) {
                LegendItem(title: "Motion", color: Theme.signal)
                LegendItem(title: "Light-tap impulse", color: Theme.impulse)
                LegendItem(title: "Adaptive gate", color: Theme.gate.opacity(0.7), mark: .dashes)
                Spacer(minLength: 0)
                Text(graphHeld ? "Held · hover to inspect" : "Drag the gold line · ↑↓ when focused")
                    .font(.ttCaption)
                    .foregroundStyle(Theme.faint)
                    .contentTransition(.opacity)
            }

            thresholdTile
        }
        .card(orb: Theme.signal)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            SegmentedCapsule(title: "Signal scale", options: MotionGraphScale.allCases,
                             label: { $0 == .detail ? "Detail" : "Linear" }, selection: $graphScale)
                .help("Detail stretches the quiet range so light taps stand out")
            SegmentedCapsule(title: "Time window", options: [2.0, 8.0],
                             label: { "\(Int($0)) s" }, selection: $graphDuration)
            Button {
                withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) { graphHeld.toggle() }
            } label: {
                Image(systemName: graphHeld ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IconButtonStyle(size: 30))
            .help(graphHeld ? "Resume the live trace" : "Hold the trace to inspect it. The sensor keeps listening.")
            .accessibilityLabel(graphHeld ? "Resume live trace" : "Hold trace")
        }
        .fixedSize()
    }

    private var thresholdTile: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "gauge.with.dots.needle.33percent", color: Theme.gate, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Threshold")
                        .font(.ttHeadline)
                    Text(String(format: "%.4f g", model.amplitudeFloor))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.gate)
                        .contentTransition(.numericText(value: model.amplitudeFloor))
                        .animation(Motion.reduced(Motion.snappy, reduceMotion), value: model.amplitudeFloor)
                }
                Text("A tap has to rise above the gold line. Lower catches lighter taps.")
                    .font(.ttCaption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Button("Light taps") { model.setAmplitudeFloor(0.008) }
                .buttonStyle(.secondarySmall)
                .help("Set the threshold to 0.0080 g")
            Button("Default") { model.setAmplitudeFloor(0.0175) }
                .buttonStyle(.secondarySmall)
                .help("Set the threshold to 0.0175 g")
        }
        .disabled(graphHeld)
        .tile()
    }

    // MARK: Profile

    private var profileCard: some View {
        let profile = model.activeCalibrationProfile
        let hasProfiles = !model.calibrationProfiles.isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconTile(symbol: "scope", color: profile == nil ? Theme.warn : Theme.signal, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.name ?? (hasProfiles ? "Custom threshold" : "Not calibrated yet"))
                        .font(.ttHeadline)
                    Text(profile != nil
                         ? "Tuned to your taps. Recalibrate if your desk or tap style changes."
                         : hasProfiles
                            ? "You moved the threshold by hand. Pick a profile below to go back to it."
                            : "Two minutes of tapping teaches it your desk and your touch.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                if profile == nil {
                    Button("Calibrate…", action: openCalibration).buttonStyle(.primary)
                } else {
                    Button("Recalibrate…", action: openCalibration).buttonStyle(.secondary)
                }
            }

            if hasProfiles && (profile == nil || model.calibrationProfiles.count > 1) {
                HStack(spacing: 12) {
                    Text("Tap profile")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 8)
                    CapsuleMenuPicker(
                        title: "Tap profile",
                        options: [Optional<UUID>.none] + model.calibrationProfiles.map(\.id),
                        label: { id in
                            guard let id, let match = model.calibrationProfiles.first(where: { $0.id == id })
                            else { return "Current custom settings" }
                            return match.name
                        },
                        selection: Binding(
                            get: { model.activeCalibrationProfile?.id },
                            set: { id in
                                if let id { model.activateCalibrationProfile(id) }
                                else { model.keepCurrentSettingsWithoutProfile() }
                            }
                        )
                    )
                    .frame(width: 280)
                }
                .tile(padding: 10)
            }
        }
        .card()
    }

    private var behaviorCard: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "keyboard", color: Theme.impulse, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ignore taps while typing or clicking")
                    .font(.ttHeadline)
                Text("A trackpad click shakes the Mac like a tap. Uses timing only, never what you type or where you click.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Toggle("Ignore taps while typing or clicking", isOn: $model.suppressTyping)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.signal)
        }
        .card()
    }

    // MARK: Attention

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Two permissions to go")
                    .font(.ttHeadline)
                Spacer()
                Button("Check again") {
                    withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) { model.refreshPermissions() }
                }
                .buttonStyle(.quiet)
            }
            VStack(spacing: 8) {
                PermissionRow(granted: model.accessibilityPermission, symbol: "accessibility",
                              title: "Accessibility",
                              detail: "Lets a double-tap lock the screen, control media or press a ChatGPT button.",
                              open: { openPrivacy("Privacy_Accessibility") })
                PermissionRow(granted: model.typingPermission, symbol: "keyboard",
                              title: "Input Monitoring",
                              detail: "Lets it ignore taps that land while you're typing. Key timing only.",
                              open: { openPrivacy("Privacy_ListenEvent") })
            }
        }
        .card(orb: Theme.warn)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var connectionCard: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "sensor.tag.radiowaves.forward", color: Theme.danger, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("The sensor isn't streaming")
                    .font(.ttHeadline)
                Text(model.status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                if model.input == .helper {
                    Text(model.helperStatus)
                        .font(.ttCaption)
                        .foregroundStyle(Theme.faint)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Reconnect") { model.reconnectSensor() }
                    .buttonStyle(.primarySmall)
                if model.input == .helper {
                    Button("Open Login Items") { model.openHelperApprovalSettings() }
                        .buttonStyle(.quiet)
                }
            }
        }
        .card(orb: Theme.danger)
    }

    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// A big tabular numeral over a small label. A change makes it glow briefly.
private struct Stat: View {
    let value: String
    var unit: String?
    let label: String
    let pulse: Int
    let color: Color

    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.ttNumeral(30))
                    .monospacedDigit()
                    .tracking(-0.8)
                    .contentTransition(.numericText())
                    .animation(Motion.reduced(Motion.snappy, reduceMotion), value: value)
                    .foregroundStyle(lit ? color : Theme.ink)
                    .shadow(color: color.opacity(lit ? 0.6 : 0), radius: 10)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .onChange(of: pulse) {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.08)) { lit = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.6)) { lit = false }
            }
        }
    }
}

private struct PermissionRow: View {
    let granted: Bool
    let symbol: String
    let title: String
    let detail: String
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: granted ? "checkmark" : symbol, color: granted ? Theme.ok : Theme.warn, size: 30)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(granted, color: Theme.faint)
                    .foregroundStyle(granted ? Theme.muted : Theme.ink)
                Text(detail)
                    .font(.ttCaption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ok)
            } else {
                Button("Open Settings", action: open).buttonStyle(.secondarySmall)
            }
        }
        .tile(padding: 10)
        .animation(Motion.reduced(Motion.snappy, reduceMotion), value: granted)
    }
}
