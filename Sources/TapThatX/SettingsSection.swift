import SwiftUI

/// Sidebar sections of the settings window, in display order.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case permissions, tuning, calibration, actions, recordings, input, diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .permissions: "Permissions"
        case .tuning: "Tap Tuning"
        case .calibration: "Calibration"
        case .actions: "Actions"
        case .recordings: "Recordings"
        case .input: "Input Source"
        case .diagnostics: "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        // Monochrome symbols throughout: multicolor-capable glyphs can render
        // untinted in sidebars, which broke accent consistency.
        case .permissions: "checkmark.shield"
        case .tuning: "waveform"
        case .calibration: "target"
        case .actions: "bolt.fill"
        case .recordings: "record.circle"
        case .input: "cable.connector"
        case .diagnostics: "ladybug"
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
