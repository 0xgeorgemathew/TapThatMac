import SwiftUI

/// Vertical navigation rail with one shared glass surface.
struct NavDock: View {
    @Binding var selection: SettingsSection?
    var appVersion: String?

    @FocusState private var focusedSection: SettingsSection?

    var body: some View {
        ReactorGlassContainer(spacing: 6) {
            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    DockRow(
                        section: section,
                        isSelected: selection == section,
                        isFocused: focusedSection == section,
                        focus: $focusedSection,
                        select: { select(section) },
                        move: { step in moveSelection(from: section, by: step) }
                    )
                }

                HStack(spacing: 6) {
                    Text("Tap That Mac")
                    if let appVersion {
                        Text(appVersion)
                    }
                }
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .padding(10)
        }
        .frame(width: 216)
        .reactorGlass(in: ReactorTheme.panelShape)
        .reactorEdgeHighlight(in: ReactorTheme.panelShape)
        .reactorGlassLift()
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.leading, 16)
        .padding(.top, 60)
        .padding(.bottom, 16)
        // Seed focus on the selected row so arrow-key navigation works as
        // soon as the window opens, like the previous sidebar.
        .onAppear { focusedSection = selection ?? .live }
    }

    private func select(_ section: SettingsSection) {
        selection = section
        focusedSection = section
    }

    private func moveSelection(from section: SettingsSection, by step: Int) {
        let sections = SettingsSection.allCases
        guard let index = sections.firstIndex(of: section) else { return }
        let next = sections.index(index, offsetBy: step)
        guard sections.indices.contains(next) else { return }
        select(sections[next])
    }
}

private struct DockRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let isFocused: Bool
    let focus: FocusState<SettingsSection?>.Binding
    let select: () -> Void
    let move: (Int) -> Void

    @State private var hovering = false

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? ReactorTheme.accent : Color.primary.opacity(0.6))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    rowShape.fill(ReactorTheme.accent.opacity(0.14))
                } else if hovering {
                    rowShape.fill(Color.primary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(rowShape)
        .reactorFocusRing(in: rowShape, focused: isFocused)
        .onHover { hovering = $0 }
        .focused(focus, equals: section)
        .onKeyPress { press in
            switch press.key {
            case .downArrow, .rightArrow: move(1)
            case .upArrow, .leftArrow: move(-1)
            case .return, .space: select()
            default: return .ignored
            }
            return .handled
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
