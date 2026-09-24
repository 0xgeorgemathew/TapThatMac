import SwiftUI
import TapCore

/// Calibration is intentionally an immersive gesture surface, not a form.
/// The only choices exposed to the user are starting, retrying, or leaving.
struct CalibrationPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calibration: CalibrationController
    var onDismissOnboarding: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            calibrationBackdrop

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                content
                Spacer(minLength: 24)
                footer
            }
            .padding(28)
        }
        .task(id: automationKey) { await advanceFlowIfNeeded() }
        .onDisappear {
            calibration.interrupt(
                "The calibration screen was hidden. Please retry this gesture.",
                at: ProcessInfo.processInfo.systemUptime
            )
        }
    }

    private var calibrationBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [ReactorTheme.accent.opacity(0.13), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button {
                if calibration.blocksActions { model.cancelCalibration() }
                model.markCalibrationOnboardingSeen()
                onDismissOnboarding()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .reactorGlass(in: Circle(), interactive: true)
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
                Text("Four taps. That’s it.")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(-1.1)
                Text("Light tap. Tap. Single. Double.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Begin") { model.beginCalibration() }
                .reactorProminentButton()
                .controlSize(.large)
                .disabled(!model.canStartCalibration)
        }
        .frame(maxWidth: 520)
    }

    private var gestureMoment: some View {
        VStack(spacing: 34) {
            if let activity = calibration.step?.activity {
                GestureIndicator(
                    activity: activity,
                    isActive: calibration.prompt == "Tap now",
                    reduceMotion: reduceMotion
                )

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
                    Text("Try that once more").foregroundStyle(.secondary)
                    Button("Retry") { calibration.retry() }
                        .reactorGlassButton()
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
                Text("Your taps now feel like yours.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Done") { onDismissOnboarding() }
                .reactorProminentButton()
                .controlSize(.large)
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
                Text("Let’s try again")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text("Make the light tap softer and the firm tap more distinct.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Start over") {
                model.cancelCalibration()
                model.beginCalibration()
            }
            .reactorProminentButton()
            .controlSize(.large)
        }
    }

    @ViewBuilder private var footer: some View {
        if calibration.stage == .idle {
            VStack(spacing: 7) {
                Text("Four gestures. About 30 seconds.")
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
            Text("Processed on this Mac")
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
        case .knock: "Tap"
        case .knockPair: "Double tap"
        default: activity.title
        }
    }

    private func instruction(for activity: CalibrationActivity) -> String {
        switch activity {
        case .lightTap: "Tap once, gently."
        case .lightPair: "Tap twice, gently — a quick one-two."
        case .knock: "Tap once, naturally."
        case .knockPair: "Tap twice, naturally — a quick one-two."
        default: activity.instruction
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
