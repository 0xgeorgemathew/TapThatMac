import SwiftUI

struct DiagnosticsPane: View {
    @ObservedObject var model: AppModel
    let setSelection: (SettingsSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Diagnostics")
            Form {
                Section {
                    Button("Manage permissions") { setSelection(.permissions) }
                }
                Section {
                    HStack {
                        Button("Missed tap") { model.mark("Missed tap; \(model.preset.rawValue)") }
                        Button("False trigger") { model.mark("False trigger; \(model.preset.rawValue)") }
                        Spacer()
                        Button("Export…") { model.export() }
                        Button("Clear log") { model.diagnostics.clear() }
                    }
                }
                Section {
                    ForEach(model.recentEvents) { event in
                        Text("\(event.time, specifier: "%.2f")  \(event.kind): \(event.detail)")
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
    }
}
