import SwiftUI
import TapCore

/// Sidebar sections of the main window, in display order.
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
        case .live: "waveform"
        case .actions: "bolt.fill"
        }
    }
}

/// Pane title with an optional one-line detail and a trailing accessory.
struct PaneHeader<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.ttTitle)
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// Standard pane scroll container: one content column with a steady rhythm.
struct PaneScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 72)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Presentation of model state

/// The one sentence the app says about whether it's listening.
struct LiveVerdict: Equatable {
    let title: String
    let tone: Tone
    let pulsing: Bool

    enum Tone { case ok, warn, danger, idle }

    var color: Color {
        switch tone {
        case .ok: Theme.ok
        case .warn: Theme.warn
        case .danger: Theme.danger
        case .idle: Theme.muted
        }
    }
}

extension AppModel {
    var liveVerdict: LiveVerdict {
        if paused { return LiveVerdict(title: "Paused", tone: .idle, pulsing: false) }
        if status != "Streaming accelerometer" && input != .simulated {
            return LiveVerdict(title: "Waiting for sensor", tone: .danger, pulsing: false)
        }
        if liveWarmingUp { return LiveVerdict(title: "Settling", tone: .warn, pulsing: true) }
        if operatingMode == .test { return LiveVerdict(title: "Listening · test", tone: .warn, pulsing: true) }
        return LiveVerdict(title: "Listening", tone: .ok, pulsing: true)
    }
}

extension ActionAvailability.Mode {
    var detail: String {
        switch self {
        case .active: "Runs your action"
        case .test: "Shows what would run"
        case .paused: "Stops listening"
        }
    }

    var color: Color {
        switch self {
        case .active: Theme.ok
        case .test: Theme.warn
        case .paused: Theme.faint
        }
    }
}

extension DoubleTapAction {
    var symbol: String { command?.symbol ?? "circle.dotted.circle" }

    /// The name without the "ChatGPT: " family prefix.
    var shortName: String { command?.shortName ?? "Command ring" }

    var maturity: (label: String, color: Color) {
        switch self {
        case .ring: ("Pre-alpha", Theme.impulse)
        case .approve, .reject, .dictation: ("Experimental", Theme.gate)
        default: ("Works", Theme.signal)
        }
    }

    var summary: String {
        switch self {
        case .ring: "Opens a wheel of every action. Each single tap moves one step clockwise; a double-tap runs the highlighted one."
        case .lock: "Locks the screen. The ring flashes first so you can see what your taps did; press Escape to cancel."
        case .playPause: "Plays or pauses whatever is playing. The ring flashes first; press Escape to cancel."
        case .next: "Skips to the next track in the app that's playing."
        case .previous: "Goes back to the previous track."
        case .approve: "Presses Approve once on the ChatGPT page you have open."
        case .reject: "Presses Reject on the ChatGPT page you have open."
        case .dictation: "Starts or stops dictation on the ChatGPT page you have open."
        }
    }
}

extension Command {
    /// The family before the colon ("ChatGPT"), if any.
    var family: String? {
        guard let range = rawValue.range(of: ": ") else { return nil }
        return String(rawValue[..<range.lowerBound])
    }

    var shortName: String {
        guard let range = rawValue.range(of: ": ") else { return rawValue }
        return String(rawValue[range.upperBound...])
    }
}
