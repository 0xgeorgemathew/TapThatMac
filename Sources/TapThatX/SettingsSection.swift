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
        case .permissions: "lock.shield"
        case .tuning: "waveform"
        case .calibration: "hand.tap.fill"
        case .actions: "hand.tap"
        case .recordings: "record.circle"
        case .input: "cable.connector"
        case .diagnostics: "ladybug"
        }
    }
}

/// Pinned pane header: the shared `heading()` recipe, now above every pane's
/// grouped form. The form below owns all scrolling.
struct PaneHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .tracking(-1.0)
            if let detail {
                Text(detail).font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
