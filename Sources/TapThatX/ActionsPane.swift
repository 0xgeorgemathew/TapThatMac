import SwiftUI
import TapCore

struct ActionsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Double-tap action",
                       detail: "Choose one action, or open the ring to choose each time.")
            Form {
                Section {
                    Picker("Double-tap", selection: $model.doubleTapAction) {
                        ForEach(DoubleTapAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                if model.doubleTapAction == .ring {
                    Section {
                        Text("Double-tap opens all actions. Single tap moves clockwise; double-tap chooses the highlighted action.")
                        Text("Right / Down move clockwise. Left / Up move counterclockwise. All arrows wrap around. Return chooses; Escape cancels. You can also point and click.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Single taps move after a short pause so a double-tap can choose without moving first.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if model.doubleTapAction == .lock {
                    Section {
                        Text("Lock and Play / Pause open the ring, move to the action, and show a press before executing. Escape cancels the animation. A lock confirmation appears when you unlock.")
                            .foregroundStyle(.secondary)
                    }
                }
                if model.doubleTapAction.command?.assistantIntent != nil {
                    Section {
                        Label("ChatGPT controls · Experimental", systemImage: "sparkles")
                        Text("Requires a matching control in ChatGPT. Missing or ambiguous controls do nothing. Browser support requires a focused chatgpt.com page.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Check controls") { model.inspectAssistantControls() }
                    }
                }
                Section {
                    Toggle("Enable system actions", isOn: $model.actionsEnabled)
                    Text("Settings and recordings temporarily pause actions. Enable & close finishes calibration and resumes your selected behavior.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Preview ring") { model.previewRing() }
                    Text("Left and right labels are available for recording. They do not yet select different actions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
    }
}
