import ServiceManagement
import SwiftUI

struct InputPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Connection",
                           detail: model.diagnostics.model)

                VStack(spacing: 20) {
                    sourceCard
                    if model.input == .simulated { simulatorCard }
                    if model.input == .helper { helperCard }
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Input", selection: $model.input) {
                ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Reconnect") { model.restart() }
                    .buttonStyle(.reactorButton)
            }
        }
        .reactorCard()
    }

    private var simulatorCard: some View {
        ReactorGlassContainer(spacing: 12) {
            HStack(spacing: 16) {
                Button("Single tap") { model.simulateKnock() }
                    .buttonStyle(.reactorButton)
                Button("Double-tap") { model.simulateDouble() }
                    .buttonStyle(.reactorButton)
                Spacer()
            }
        }
        .reactorCard()
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.helperStatus).font(.callout).foregroundStyle(.secondary)
            ReactorGlassContainer(spacing: 12) {
                HStack(spacing: 16) {
                    Button("Register helper") { model.installHelper() }
                        .buttonStyle(.reactorButton(prominent: true))
                    Button("Approval settings") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.reactorButton)
                    Button("Remove helper") { model.removeHelper() }
                        .buttonStyle(.reactorButton)
                    Spacer()
                }
            }
        }
        .reactorCard()
    }
}
