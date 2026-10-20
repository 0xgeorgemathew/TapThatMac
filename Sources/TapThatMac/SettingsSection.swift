import SwiftUI

/// Sidebar sections of the settings window, in display order.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case live, actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .actions: "Actions"
        }
    }

    var icon: String {
        switch self {
        // Monochrome symbols throughout: multicolor-capable glyphs can render
        // untinted in sidebars, which broke accent consistency.
        case .live: "waveform"
        case .actions: "bolt.fill"
        }
    }
}

/// Pinned pane header above every pane's grouped content. The pane scaffold
/// owns the horizontal padding; the header only adds vertical breathing room.
struct PaneHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Calibration-scale display type: large rounded semibold with
            // tight tracking, matched to the reference screen's headers.
            Text(title)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .tracking(-1.1)
            if let detail {
                Text(detail).font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
