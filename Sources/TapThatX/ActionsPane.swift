import SwiftUI
import TapCore

struct ActionsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Double-tap action",
                           detail: "Choose one action, or open the ring to choose each time.")

                VStack(spacing: 20) {
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
    }

    private var actionPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Double-tap").font(.title3.weight(.semibold))
            ReactorGlassMenuPicker(
                title: "Double-tap",
                options: DoubleTapAction.allCases,
                label: \.rawValue,
                selection: $model.doubleTapAction
            )
            .frame(minWidth: 300, maxWidth: 420)
        }
        .reactorCard()
    }

    private var ringHelpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Double-tap opens all actions. Single tap moves clockwise; double-tap chooses the highlighted action.")
            Text("Right / Down move clockwise. Left / Up move counterclockwise. All arrows wrap around. Return chooses; Escape cancels. You can also point and click.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Single taps move after a short pause so a double-tap can choose without moving first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .reactorCard()
    }

    private var lockHelpCard: some View {
        Text("Lock and Play / Pause open the ring, move to the action, and show a press before executing. Escape cancels the animation. A lock confirmation appears when you unlock.")
            .foregroundStyle(.secondary)
            .reactorCard()
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ChatGPT controls · Experimental", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text("Requires a matching control in ChatGPT. Missing or ambiguous controls do nothing. Browser support requires a focused chatgpt.com page.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Check controls") { model.inspectAssistantControls() }
                .buttonStyle(.reactorButton)
        }
        .reactorCard()
    }

    private var systemActionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable system actions", isOn: $model.actionsEnabled)
                .toggleStyle(.switch)
                // Native control, accent-tinted so the switch matches
                // the one accent when on.
                .tint(ReactorTheme.accent)
            Text("Settings and recordings temporarily pause actions. Enable & close finishes calibration and resumes your selected behavior.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Preview ring") { model.previewRing() }
                .buttonStyle(.reactorButton(prominent: true))
            Text("Left and right labels are available for recording. They do not yet select different actions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .reactorCard()
    }
}
