import ServiceManagement
import SwiftUI

struct InputPane: View {
    @ObservedObject var model: AppModel

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ReactorBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PaneHeader(title: "Connection",
                               detail: model.diagnostics.model)

                    ReactorGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            sourceCard
                            if model.input == .simulated { simulatorCard }
                            if model.input == .helper { helperCard }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Input", selection: $model.input) {
                ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Reconnect") { model.restart() }
                    .buttonStyle(.reactorBigButton)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var simulatorCard: some View {
        HStack(spacing: 14) {
            Button("Single tap") { model.simulateKnock() }
                .buttonStyle(.reactorBigButton)
            Button("Double-tap") { model.simulateDouble() }
                .buttonStyle(.reactorBigButton)
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.helperStatus).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("Register helper") { model.installHelper() }
                    .buttonStyle(.reactorBigButton(prominent: true))
                Button("Approval settings") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.reactorBigButton)
                Button("Remove helper") { model.removeHelper() }
                    .buttonStyle(.reactorBigButton)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }
}
