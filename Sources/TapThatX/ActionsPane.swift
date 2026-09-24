import SwiftUI
import TapCore

struct ActionsPane: View {
    @ObservedObject var model: AppModel

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ReactorBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PaneHeader(title: "Double-tap action",
                               detail: "Choose one action, or open the ring to choose each time.")

                    ReactorGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            actionPickerCard

                            if model.doubleTapAction == .ring {
                                ringHelpCard
                            } else if model.doubleTapAction == .lock {
                                lockHelpCard
                            }

                            if model.doubleTapAction.command?.assistantIntent != nil {
                                assistantCard
                            }

                            systemActionsCard
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Double-tap").font(.title3.weight(.semibold))
            Picker("Double-tap", selection: $model.doubleTapAction) {
                ForEach(DoubleTapAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var ringHelpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Double-tap opens all actions. Single tap moves clockwise; double-tap chooses the highlighted action.")
            Text("Right / Down move clockwise. Left / Up move counterclockwise. All arrows wrap around. Return chooses; Escape cancels. You can also point and click.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Single taps move after a short pause so a double-tap can choose without moving first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var lockHelpCard: some View {
        Text("Lock and Play / Pause open the ring, move to the action, and show a press before executing. Escape cancels the animation. A lock confirmation appears when you unlock.")
            .foregroundStyle(.secondary)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .reactorGlass(in: surface)
            .reactorEdgeHighlight(in: surface)
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ChatGPT controls · Experimental", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text("Requires a matching control in ChatGPT. Missing or ambiguous controls do nothing. Browser support requires a focused chatgpt.com page.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Check controls") { model.inspectAssistantControls() }
                .buttonStyle(.reactorBigButton)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var systemActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable system actions", isOn: $model.actionsEnabled)
            Text("Settings and recordings temporarily pause actions. Enable & close finishes calibration and resumes your selected behavior.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Preview ring") { model.previewRing() }
                .buttonStyle(.reactorBigButton(prominent: true))
            Text("Left and right labels are available for recording. They do not yet select different actions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }
}
