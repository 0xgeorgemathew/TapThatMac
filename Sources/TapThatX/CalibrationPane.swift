import SwiftUI
import TapCore

/// Calibration is intentionally an immersive gesture surface, not a form.
/// Choose the physical setup before collecting gestures and desk disturbances.
struct CalibrationPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calibration: CalibrationController
    var onDismissOnboarding: () -> Void = {}
    @State private var deskSetup = DeskSetup.openMac
    private var sessionSetup: DeskSetup {
        calibration.session.flatMap { DeskSetup(rawValue: $0.context.surface) } ?? deskSetup
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The shell's ReactorStage now provides the stage: a real vibrancy
        // window with the same radial accent glow, so calibration floats on
        // translucent glass instead of an opaque painted backdrop.
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 24)
            content
            Spacer(minLength: 24)
            footer
        }
        .padding(28)
        .task(id: automationKey) { await advanceFlowIfNeeded() }
        .onDisappear {
            calibration.interrupt(
                "The calibration screen was hidden. Please retry this gesture.",
                at: ProcessInfo.processInfo.systemUptime
            )
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if calibration.blocksActions { model.cancelCalibration() }
                onDismissOnboarding()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.reactorIconButton)
            .accessibilityLabel("Close calibration")

            Spacer()

            if calibration.stage != .idle {
                gestureProgress.transition(.opacity)
            }

            Spacer()

            Color.clear.frame(width: 34, height: 34)
        }
    }

    @ViewBuilder private var content: some View {
        switch calibration.stage {
        case .idle:
            introduction
        case .ready, .recording, .review:
            gestureMoment
        case .complete:
            completion
        case .failed:
            failure
        }
    }

    private var introduction: some View {
        VStack(spacing: 30) {
            GestureIndicator(activity: .lightPair, isActive: true, reduceMotion: reduceMotion)

            VStack(spacing: 10) {
                Text("Tune for your desk.")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(-1.1)
                Text("Use your normal desk setup, with the lid open or an external display active. Tap the Mac or desk where you want commands to work. Lap use is not supported.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Picker("Desk setup", selection: $deskSetup) {
                ForEach(DeskSetup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Button("Begin") { model.beginCalibration(setup: deskSetup) }
                .buttonStyle(.reactorButton(prominent: true))
                .disabled(!model.canStartCalibration)
        }
        .frame(maxWidth: 520)
    }

    private var gestureMoment: some View {
        VStack(spacing: 34) {
            if let activity = calibration.step?.activity {
                if activity.expectedContacts == 0 {
                    Image(systemName: activity == .surfaceBump ? "table.furniture" : "keyboard")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(ReactorTheme.accent)
                        .frame(height: 150)
                } else {
                    GestureIndicator(activity: activity, isActive: calibration.prompt == "Tap now",
                                     reduceMotion: reduceMotion)
                }

                VStack(spacing: 11) {
                    Text(displayName(for: activity))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .tracking(-1.2)
                    Text(instruction(for: activity))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            statusIndicator.frame(height: 46)
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder private var statusIndicator: some View {
        if calibration.stage == .review {
            if calibration.reviewMatchesExpectedGesture {
                Label("Captured", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(ReactorTheme.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 12) {
                    Text(calibration.review?.quality.issues.first ?? "The expected contacts were not captured. Try again.").foregroundStyle(.secondary)
                    Button("Retry") { calibration.retry() }
                        .buttonStyle(.reactorButtonCompact(prominent: true))
                }
            }
        } else {
            Text(calibration.prompt.isEmpty ? "Get ready" : calibration.prompt)
                .font(.headline)
                .foregroundStyle(calibration.prompt == "Tap now" ? ReactorTheme.accent : .secondary)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var completion: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(ReactorTheme.accent.opacity(0.13))
                    .frame(width: 164, height: 164)
                Image(systemName: "checkmark")
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(ReactorTheme.accent)
            }
            .reactorGlass(in: Circle())

            VStack(spacing: 9) {
                Text("Ready")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("Your taps now trigger your actions.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Done") { onDismissOnboarding() }
                .buttonStyle(.reactorButton(prominent: true))
                .disabled(!calibration.applied)
        }
    }

    private var failure: some View {
        VStack(spacing: 26) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(ReactorTheme.accent)
                .frame(width: 150, height: 150)
                .reactorGlass(in: Circle())

            VStack(spacing: 9) {
                Text("Let's try again")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text(calibration.message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Start over") {
                let setup = sessionSetup
                model.cancelCalibration()
                model.beginCalibration(setup: setup)
            }
            .buttonStyle(.reactorButton(prominent: true))
        }
    }

    @ViewBuilder private var footer: some View {
        if calibration.stage == .idle {
            VStack(spacing: 7) {
                Text("About two minutes, including a fresh verification round.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let reason = model.calibrationUnavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } else if let error = calibration.saveError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text(calibration.step?.partition == .verification
                 ? "Verifying fresh recordings · Settings are fixed"
                 : "Learning this desk setup · Processed on this Mac")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var gestureProgress: some View {
        HStack(spacing: 8) {
            ForEach(calibration.steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index < calibration.completedCount
                          ? ReactorTheme.accent
                          : index == calibration.completedCount && calibration.stage != .complete
                            ? ReactorTheme.accent.opacity(0.55)
                            : Color.secondary.opacity(0.18))
                    .frame(width: index == calibration.completedCount ? 28 : 8, height: 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78),
                               value: calibration.completedCount)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gesture \(min(calibration.completedCount + 1, calibration.steps.count)) of \(calibration.steps.count)")
    }

    private var automationKey: String {
        "\(String(describing: calibration.stage))-\(calibration.completedCount)-\(calibration.review?.id.uuidString ?? "none")"
    }

    @MainActor
    private func advanceFlowIfNeeded() async {
        do {
            switch calibration.stage {
            case .ready:
                try await Task.sleep(for: .milliseconds(calibration.completedCount == 0 ? 500 : 900))
                guard !Task.isCancelled else { return }
                model.recordCalibrationTrial()
            case .review where calibration.reviewMatchesExpectedGesture:
                try await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                calibration.confirm()
            case .complete where !calibration.applied:
                try await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                model.applyCalibration()
            default:
                break
            }
        } catch {
            // Cancellation is expected when the stage changes or the view closes.
        }
    }

    private func displayName(for activity: CalibrationActivity) -> String {
        switch activity {
        case .lightTap: "Light tap"
        case .lightPair: "Light double tap"
        case .knock: "Knock"
        case .knockPair: "Double knock"
        default: activity.title
        }
    }

    private func instruction(for activity: CalibrationActivity) -> String {
        let location = sessionSetup == .externalDisplay ? "on the desk" : "where you want commands to work: on the Mac or desk"
        switch activity {
        case .lightTap: return "Tap once, gently, \(location)."
        case .lightPair: return "Tap twice, gently, \(location). A quick one-two."
        case .knock: return "Knock once \(location)."
        case .knockPair: return "Knock twice \(location). A quick one-two."
        default: return activity.instruction
        }
    }
}

private struct GestureIndicator: View {
    let activity: CalibrationActivity
    let isActive: Bool
    let reduceMotion: Bool

    private var contactCount: Int { activity.expectedContacts == 2 ? 2 : 1 }
    private var isLight: Bool { activity == .lightTap || activity == .lightPair }

    var body: some View {
        ReactorGlassContainer(spacing: 16) {
            HStack(spacing: 18) {
                ForEach(0..<contactCount, id: \.self) { index in
                    ZStack {
                        Circle().fill(ReactorTheme.accent.opacity(isActive ? 0.2 : 0.08))
                        Circle()
                            .stroke(ReactorTheme.accent.opacity(isActive ? 0.8 : 0.28),
                                    lineWidth: isLight ? 2 : 4)
                            .padding(isLight ? 15 : 10)
                        Circle()
                            .fill(ReactorTheme.accent.opacity(isActive ? 0.95 : 0.55))
                            .frame(width: isLight ? 13 : 22, height: isLight ? 13 : 22)
                    }
                    .frame(width: isLight ? 102 : 126, height: isLight ? 102 : 126)
                    .reactorGlass(in: Circle())
                    .scaleEffect(isActive ? 1.08 : 1)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.62)
                            .delay(Double(index) * 0.22),
                        value: isActive
                    )
                }
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}
