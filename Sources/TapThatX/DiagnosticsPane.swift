import SwiftUI

struct DiagnosticsPane: View {
    @ObservedObject var model: AppModel
    let setSelection: (SettingsSection) -> Void

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ReactorBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PaneHeader(title: "Diagnostics")

                    ReactorGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            permissionsCard
                            markingCard
                            eventsCard
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var permissionsCard: some View {
        Button("Manage permissions") { setSelection(.permissions) }
            .buttonStyle(.reactorBigButton)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .reactorGlass(in: surface)
            .reactorEdgeHighlight(in: surface)
    }

    private var markingCard: some View {
        HStack(spacing: 14) {
            Button("Missed tap") { model.mark("Missed tap; \(model.preset.rawValue)") }
                .reactorGlassButton()
            Button("False trigger") { model.mark("False trigger; \(model.preset.rawValue)") }
                .reactorGlassButton()
            Spacer()
            Button("Export…") { model.export() }
                .reactorGlassButton()
            Button("Clear log") { model.diagnostics.clear() }
                .reactorGlassButton()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    @ViewBuilder private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.recentEvents) { event in
                Text("\(event.time, specifier: "%.2f")  \(event.kind): \(event.detail)")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }
}
