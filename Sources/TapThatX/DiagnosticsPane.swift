import SwiftUI

struct DiagnosticsPane: View {
    @ObservedObject var model: AppModel
    let setSelection: (SettingsSection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "Diagnostics")

                VStack(spacing: 20) {
                    permissionsCard
                    markingCard
                    eventsCard
                }
            }
        }
    }

    private var permissionsCard: some View {
        Button("Manage permissions") { setSelection(.permissions) }
            .buttonStyle(.reactorButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .reactorCard()
    }

    private var markingCard: some View {
        ReactorGlassContainer(spacing: 8) {
            HStack(spacing: 14) {
                Button("Missed tap") { model.mark("Missed tap; \(model.preset.rawValue)") }
                    .buttonStyle(.reactorButtonCompact)
                Button("False trigger") { model.mark("False trigger; \(model.preset.rawValue)") }
                    .buttonStyle(.reactorButtonCompact)
                Spacer()
                Button("Export…") { model.export() }
                    .buttonStyle(.reactorButtonCompact)
                Button("Clear log") { model.diagnostics.clear() }
                    .buttonStyle(.reactorButtonCompact)
            }
        }
        .reactorCard()
    }

    @ViewBuilder private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.recentEvents) { event in
                Text("\(event.time, specifier: "%.2f")  \(event.kind): \(event.detail)")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    // Fresh events slide in from the leading edge with a fade.
                    .transition(
                        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -12))
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85),
            value: model.recentEvents.first?.id
        )
        .reactorCard()
    }
}
