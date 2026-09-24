import ServiceManagement
import SwiftUI

struct InputPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Connection",
                       detail: model.diagnostics.model)
            Form {
                Section {
                    Picker("Input", selection: $model.input) {
                        ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    HStack { Text(model.status); Spacer(); Button("Reconnect") { model.restart() } }
                }
                if model.input == .simulated {
                    Section {
                        HStack { Button("Single tap") { model.simulateKnock() }; Button("Double-tap") { model.simulateDouble() } }
                    }
                }
                if model.input == .helper {
                    Section {
                        Text(model.helperStatus)
                        HStack {
                            Button("Register helper") { model.installHelper() }
                            Button("Approval settings") { SMAppService.openSystemSettingsLoginItems() }
                            Button("Remove helper") { model.removeHelper() }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
    }
}
