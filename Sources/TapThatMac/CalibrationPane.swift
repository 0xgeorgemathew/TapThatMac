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
    /// Taps the detector has heard while this screen is up.
    @State private var heardTaps = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 24)
            content
            Spacer(minLength: 24)
            footer
        }
        .padding(28)
        .onReceive(model.tapDetected) { heardTaps += 1 }
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
            }
            .buttonStyle(IconButtonStyle(size: 32))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close calibration")

            Spacer()

            if calibration.stage != .idle {
                gestureProgress.transition(.opacity)
            }

            Spacer()

            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.top, 8)
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
            GestureIndicator(activity: .lightPair, isActive: true, taps: heardTaps, reduceMotion: reduceMotion)

            VStack(spacing: 12) {
                Text("Tune it to your desk")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                Text("Set up as you normally work, then tap where you want commands to work. It takes about two minutes and stays on this Mac.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SegmentedCapsule(title: "Desk setup", options: DeskSetup.allCases, label: \.rawValue,
                             selection: $deskSetup)
                .frame(maxWidth: 420)

            Button("Begin") { model.beginCalibration(setup: deskSetup) }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStartCalibration)
        }
        .frame(maxWidth: 540)
    }

    private var gestureMoment: some View {
        VStack(spacing: 34) {
            if let activity = calibration.step?.activity {
                if activity.expectedContacts == 0 {
                    QuietIndicator(symbol: activity == .surfaceBump ? "table.furniture" : "keyboard",
                                   active: calibration.stage == .recording, reduceMotion: reduceMotion)
                } else {
                    GestureIndicator(activity: activity, isActive: calibration.prompt == "Tap now",
                                     taps: heardTaps, reduceMotion: reduceMotion)
                }

                VStack(spacing: 11) {
                    Text(displayName(for: activity))
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.8)
                        .contentTransition(.opacity)
                    Text(instruction(for: activity))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .id(activity)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            }

            statusIndicator.frame(height: 46)
        }
        .frame(maxWidth: 560)
        .animation(Motion.reduced(Motion.settle, reduceMotion), value: calibration.step?.activity)
    }

    @ViewBuilder private var statusIndicator: some View {
        if calibration.stage == .review {
            if calibration.reviewMatchesExpectedGesture {
                HStack(spacing: 12) {
                    StatusBadge(title: "Captured", color: Theme.ok)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    if calibration.canRetrySave {
                        Button("Retry save") { calibration.retrySave() }
                            .buttonStyle(.primarySmall)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text(calibration.review?.quality.issues.first ?? "The expected contacts were not captured. Try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                    Button("Retry") { calibration.retry() }
                        .buttonStyle(.primarySmall)
                }
            }
        } else {
            let live = calibration.prompt == "Tap now"
            StatusBadge(title: calibration.prompt.isEmpty ? "Get ready" : calibration.prompt,
                        color: live ? Theme.signal : Theme.muted, pulsing: live)
                .accessibilityAddTraits(.updatesFrequently)
                .animation(Motion.reduced(Motion.fade, reduceMotion), value: calibration.prompt)
        }
    }

    private var completion: some View {
        VStack(spacing: 28) {
            DrawnCheck(reduceMotion: reduceMotion)

            VStack(spacing: 10) {
                Text("Ready")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                Text("Tuned to your taps. Try a double-tap.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
            }

            Button("Done") { onDismissOnboarding() }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!calibration.applied)
        }
    }

    private var failure: some View {
        VStack(spacing: 26) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .frame(width: 120, height: 120)
                .background(Theme.warn.opacity(0.1), in: Circle())
                .overlay(Circle().strokeBorder(Theme.warn.opacity(0.3), lineWidth: 1))

            VStack(spacing: 10) {
                Text("Let's try that again")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                Text(calibration.message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            Button("Start over") {
                let setup = sessionSetup
                model.cancelCalibration()
                model.beginCalibration(setup: setup)
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 540)
    }

    @ViewBuilder private var footer: some View {
        if calibration.stage == .idle {
            if let reason = model.calibrationUnavailableReason {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.warn)
            } else {
                Text("Processed on this Mac. Nothing leaves it.")
                    .font(.ttCaption)
                    .foregroundStyle(Theme.faint)
            }
        } else if let error = calibration.saveError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.danger)
        } else {
            Text(calibration.step?.partition == .verification
                 ? "Checking with fresh taps · settings are fixed"
                 : "Learning this desk · processed on this Mac")
                .font(.ttCaption)
                .foregroundStyle(Theme.faint)
        }
    }

    /// Segments like a meter: done steps lit, the current one half lit.
    private var gestureProgress: some View {
        HStack(spacing: 4) {
            ForEach(calibration.steps.indices, id: \.self) { index in
                let done = index < calibration.completedCount
                let current = index == calibration.completedCount && calibration.stage != .complete
                Capsule()
                    .fill(done
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.signal, Theme.signalDeep],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(current ? Theme.signal.opacity(0.35) : Theme.track))
                    .shadow(color: Theme.signal.opacity(done ? 0.4 : 0), radius: 4)
                    .frame(width: current ? 26 : 14, height: 6)
            }
        }
        .padding(5)
        .background(Theme.tile, in: Capsule())
        .animation(Motion.reduced(Motion.settle, reduceMotion), value: calibration.completedCount)
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

/// Tap pads: one per contact. While the prompt says "Tap now" they ripple in
/// the rhythm of the gesture; every tap the detector actually hears lights
/// the next pad, so you can see each tap land.
private struct GestureIndicator: View {
    let activity: CalibrationActivity
    let isActive: Bool
    let taps: Int
    let reduceMotion: Bool

    private var contactCount: Int { activity.expectedContacts == 2 ? 2 : 1 }
    private var isLight: Bool { activity == .lightTap || activity == .lightPair }

    var body: some View {
        HStack(spacing: 44) {
            ForEach(0..<contactCount, id: \.self) { index in
                TapPad(light: isLight, active: isActive, hit: taps > 0 && taps % contactCount == (index + 1) % contactCount,
                       hitToken: taps, delay: Double(index) * 0.22, reduceMotion: reduceMotion)
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}

private struct TapPad: View {
    let light: Bool
    let active: Bool
    let hit: Bool
    let hitToken: Int
    let delay: Double
    let reduceMotion: Bool
    @State private var flash = false

    private var diameter: CGFloat { light ? 104 : 126 }

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                Circle()
                    .stroke(Theme.signal, lineWidth: 1.5)
                    .phaseAnimator([false, true]) { ring, out in
                        ring.scaleEffect(out ? 1.45 : 0.9).opacity(out ? 0 : 0.6)
                    } animation: { out in
                        out ? .easeOut(duration: 1.1).delay(delay) : .linear(duration: 0)
                    }
            }
            Circle()
                .fill(RadialGradient(colors: [Theme.signal.opacity(active ? 0.24 : 0.1), Theme.signal.opacity(0.03)],
                                     center: .center, startRadius: 0, endRadius: diameter / 2))
            Circle()
                .strokeBorder(Theme.signal.opacity(active ? 0.7 : 0.25), lineWidth: light ? 1.5 : 3)
                .padding(light ? 16 : 12)
            Circle()
                .fill(Theme.signal.opacity(active ? 1 : 0.5))
                .frame(width: light ? 12 : 20, height: light ? 12 : 20)
                .shadow(color: Theme.signal.opacity(active ? 0.8 : 0), radius: 8)
            Circle()
                .fill(Theme.signal.opacity(flash ? 0.35 : 0))
        }
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        .frame(width: diameter, height: diameter)
        .scaleEffect(flash && !reduceMotion ? 0.94 : active && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : Motion.pop.delay(delay), value: active)
        .onChange(of: hitToken) {
            guard hit else { return }
            withAnimation(.easeOut(duration: 0.06)) { flash = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(reduceMotion ? nil : Motion.pop) { flash = false }
            }
        }
    }
}

/// Steps with no taps: keep still, or bump the desk.
private struct QuietIndicator: View {
    let symbol: String
    let active: Bool
    let reduceMotion: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 46, weight: .light))
            .foregroundStyle(Theme.signal)
            .frame(width: 126, height: 126)
            .background(Theme.signal.opacity(active ? 0.12 : 0.06), in: Circle())
            .overlay(Circle().strokeBorder(Theme.signal.opacity(active ? 0.4 : 0.18), lineWidth: 1))
            .animation(reduceMotion ? nil : Motion.settle, value: active)
            .frame(height: 150)
            .accessibilityHidden(true)
    }
}

/// A check that draws itself inside a lit circle.
private struct DrawnCheck: View {
    let reduceMotion: Bool
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.signal.opacity(0.12))
                .overlay(Circle().strokeBorder(Theme.signal.opacity(0.35), lineWidth: 1))
            Circle()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.5)
                .shadow(color: Theme.signal.opacity(0.6), radius: 8)
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: 52, height: 40)
        }
        .frame(width: 140, height: 140)
        .scaleEffect(drawn || reduceMotion ? 1 : 0.9)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { drawn = true }
        }
        .accessibilityHidden(true)
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }
    }
}
