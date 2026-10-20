import SwiftUI
import TapCore

struct ActionsPane: View {
    @ObservedObject var model: AppModel
    var showLive: () -> Void = {}

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let groups: [(title: String, tag: (String, Color)?, actions: [DoubleTapAction])] = [
        ("Works today", nil, [.lock, .playPause, .next, .previous]),
        ("Every action on one wheel", ("Pre-alpha", Theme.impulse), [.ring]),
        ("ChatGPT controls", ("Experimental", Theme.gate), [.approve, .reject, .dictation]),
    ]

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 20) {
                PaneHeader(title: "Actions", detail: "Choose what a double-tap does.")
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Eyebrow(group.title)
                                if let tag = group.tag { Tag(text: tag.0, color: tag.1) }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                                     count: max(group.actions.count, 3)), spacing: 10) {
                                ForEach(group.actions, id: \.self) { action in
                                    ActionTile(action: action, selected: model.doubleTapAction == action,
                                               namespace: namespace) {
                                        withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) {
                                            model.doubleTapAction = action
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .card()

                detailCard
                    .id(model.doubleTapAction)
                    .transition(.opacity)
                    .animation(Motion.reduced(Motion.fade, reduceMotion), value: model.doubleTapAction)

                if model.doubleTapAction != .ring { previewCard }
            }
        }
    }

    private var detailCard: some View {
        let action = model.doubleTapAction
        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconTile(symbol: action.symbol, color: action.maturity.color, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action == .ring ? "Command ring" : action.rawValue)
                            .font(.system(size: 17, weight: .bold))
                            .tracking(-0.2)
                        Tag(text: action.maturity.label, color: action.maturity.color)
                    }
                }
                Text(action.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if action == .ring {
                    Text("Arrow keys and Return work too. Escape closes it. Expect missed and extra taps while the ring is tuned.")
                        .font(.ttCaption)
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try the ring safely") { model.previewRing() }
                        .buttonStyle(.primary)
                        .help("Opens the ring without running anything, in every mode")
                        .padding(.top, 4)
                } else if action.command?.assistantIntent != nil {
                    Text("Needs a matching button on a focused chatgpt.com page or in the ChatGPT app. If it can't find exactly one, it does nothing.")
                        .font(.ttCaption)
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Check controls") { model.inspectAssistantControls() }
                        .buttonStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Button(action: showLive) {
                        Text("Try it: tap twice, and watch it land in ")
                            .foregroundStyle(Theme.faint)
                        + Text("Live →")
                            .foregroundStyle(Theme.signal)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .font(.ttCaption)
                }
            }
            if action == .ring {
                Spacer(minLength: 0)
                MiniRingDemo()
                    .frame(width: 196)
            }
        }
        .card(orb: action.maturity.color)
    }

    private var previewCard: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "circle.dotted.circle", color: Theme.impulse, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview the command ring")
                    .font(.ttHeadline)
                Text("Explore it without running anything, in every mode.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            Button("Preview") { model.previewRing() }
                .buttonStyle(.secondary)
        }
        .card(padding: 18)
    }
}

/// One choosable action: icon, name, and a check when it's the one.
private struct ActionTile: View {
    let action: DoubleTapAction
    let selected: Bool
    let namespace: Namespace.ID
    let choose: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    IconTile(symbol: action.symbol, color: selected ? Theme.signal : Theme.muted, size: 30)
                        .symbolBounce(value: selected, reduceMotion: reduceMotion)
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().strokeBorder(Theme.hairline, lineWidth: 1.5)
                        if selected {
                            Circle().fill(Theme.signal)
                                .shadow(color: Theme.signal.opacity(0.6), radius: 5)
                                .matchedGeometryEffect(id: "check", in: namespace)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(Theme.onSignal)
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                Spacer(minLength: 10)
                if let family = action.command?.family {
                    Text(family.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.faint)
                }
                Text(action.shortName)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Theme.signal.opacity(0.1) : hovering ? Theme.tileHover : Theme.tile)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.signal.opacity(0.55) : Theme.hairline, lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: Theme.signal.opacity(selected ? 0.18 : 0), radius: 10)
            .scaleEffect(hovering && !selected && !reduceMotion ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusRing(RoundedRectangle(cornerRadius: 14, style: .continuous), focused: focused)
        .onHover { hovering = $0 }
        .animation(Motion.reduced(Motion.snappy, reduceMotion), value: hovering)
        .accessibilityLabel(action.rawValue)
        .accessibilityValue(action.maturity.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A small looping demonstration of the ring: two single taps step the
/// highlight clockwise, then a double-tap chooses. Static under Reduce Motion.
struct MiniRingDemo: View {
    @State private var index = 0
    @State private var firstTap = false
    @State private var chosen = false
    @State private var caption = "Double-tap opens it"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                ZStack {
                    RingDisc(shadow: false)
                    RingSelectionHighlight(flash: chosen)
                        .rotationEffect(.degrees(Double(index) * RingGeometry.sweep))
                        .animation(reduceMotion ? nil : RingMotion.selection, value: index)
                        .animation(reduceMotion ? nil : RingMotion.confirmation, value: chosen)
                    ForEach(Array(Command.allCases.enumerated()), id: \.element) { offset, command in
                        RingItemLabel(command: command, selected: offset == index % RingGeometry.count, compact: true)
                            .position(RingGeometry.position(offset, size: size, radius: 0.36))
                    }
                    Circle()
                        .fill(Color.black.opacity(scheme == .dark ? 0.2 : 0.035))
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                        .overlay {
                            Circle().trim(from: 0, to: chosen ? 1 : 0)
                                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(1)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: chosen)
                        }
                        .overlay {
                            TapDots(first: firstTap || chosen, second: chosen, reduceMotion: reduceMotion)
                        }
                        .frame(width: size * RingGeometry.hub * 0.8, height: size * RingGeometry.hub * 0.8)
                }
                .frame(width: size, height: size)
            }
            .aspectRatio(1, contentMode: .fit)

            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.muted)
                .contentTransition(.opacity)
                .animation(Motion.reduced(Motion.fade, reduceMotion), value: caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ring demonstration: each single tap moves one step clockwise; a double-tap chooses.")
        .task(id: reduceMotion) { await loop() }
    }

    @MainActor
    private func loop() async {
        guard !reduceMotion else {
            caption = "Tap to move · tap twice to choose"
            return
        }
        func pause(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
        do {
            while !Task.isCancelled {
                chosen = false; firstTap = false
                caption = "Double-tap opens it"
                try await pause(1.4)
                for _ in 0..<2 {
                    caption = "Tap moves one step"
                    firstTap = true
                    try await pause(0.45)
                    firstTap = false
                    index += 1
                    try await pause(0.75)
                }
                caption = "Tap twice to choose"
                firstTap = true
                try await pause(0.22)
                chosen = true
                try await pause(1.6)
            }
        } catch {
            // Cancelled when the card goes away.
        }
    }
}
