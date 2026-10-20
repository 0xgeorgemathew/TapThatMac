import SwiftUI
import TapCore

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection = .live
    @State private var calibrationPresented = false
    @State private var toast: String?
    @State private var toastToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    /// Short bundle version for the sidebar caption.
    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        ZStack {
            if calibrationPresented {
                CalibrationPane(
                    model: model,
                    calibration: model.calibration,
                    onDismissOnboarding: {
                        withAnimation(Motion.reduced(Motion.settle, reduceMotion)) { calibrationPresented = false }
                    }
                )
                .background(CalibrationBackdrop())
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 1.02)))
            } else {
                HStack(spacing: 0) {
                    Sidebar(model: model, selection: $selection, version: Self.appVersion)
                    pane
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .bottom) { toastView }
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { WindowDragArea().frame(height: 28) }
        .background(Theme.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .tint(Theme.signal)
        .frame(minWidth: 860, idealWidth: 960, minHeight: 600, idealHeight: 720)
        .background(SettingsWindowReader(model: model))
        .onAppear {
            model.reopenMainWindow = { openWindow(id: "main") }
            model.refreshPermissions()
        }
        // Every assignment, even a repeat of the same message, gets a toast.
        .onReceive(model.$acknowledgment.dropFirst().receive(on: RunLoop.main)) { show($0) }
    }

    @ViewBuilder private var pane: some View {
        ZStack {
            switch selection {
            case .live:
                TuningPane(model: model, openCalibration: {
                    model.calibration.prepareForPresentation()
                    withAnimation(Motion.reduced(Motion.settle, reduceMotion)) { calibrationPresented = true }
                })
                .transition(paneTransition)
            case .actions:
                ActionsPane(model: model, showLive: { selection = .live })
                    .transition(paneTransition)
            }
        }
        .animation(Motion.reduced(Motion.settle, reduceMotion) ?? .easeInOut(duration: 0.15), value: selection)
    }

    private var paneTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }

    // MARK: Toast

    /// Action results surface as a brief capsule at the bottom of the pane.
    @ViewBuilder private var toastView: some View {
        if let toast {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.signal)
                    .symbolBounce(value: toastToken, reduceMotion: reduceMotion)
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(Theme.canvas)
                    .overlay(Capsule().fill(Theme.tileHover))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            }
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .padding(.bottom, 22)
            .padding(.horizontal, 40)
            .id(toastToken)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { dismissToast() }
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private func show(_ message: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.2))
            if toastToken == token { dismissToast() }
        }
    }

    private func dismissToast() {
        withAnimation(Motion.reduced(Motion.fade, reduceMotion)) { toast = nil }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Binding var selection: SettingsSection
    let version: String?

    @Namespace private var namespace
    @FocusState private var focused: SettingsSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 48)
                .padding(.bottom, 26)

            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    navRow(section)
                }
            }

            Spacer(minLength: 24)

            ModeSelector(mode: $model.operatingMode)
                .padding(.bottom, 16)

            ArmedSummary(model: model, openActions: { select(.actions) })
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea()
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tap That Mac")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                if let version {
                    Text("Version \(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func navRow(_ section: SettingsSection) -> some View {
        let isSelected = selection == section
        return Button { select(section) } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.signal : Theme.muted)
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                Spacer(minLength: 0)
                if section == .live {
                    let verdict = model.liveVerdict
                    StatusDot(color: verdict.color, pulsing: false, size: 6)
                        .help(verdict.title)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.tileHover)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                        .matchedGeometryEffect(id: "nav", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused, equals: section)
        // The selected row's highlight already marks it; the ring appears
        // only when keyboard focus sits on a different row.
        .focusRing(RoundedRectangle(cornerRadius: 10, style: .continuous), focused: focused == section && !isSelected)
        .onKeyPress { press in
            let all = SettingsSection.allCases
            guard let index = all.firstIndex(of: section) else { return .ignored }
            switch press.key {
            case .downArrow where index + 1 < all.count: select(all[index + 1])
            case .upArrow where index > 0: select(all[index - 1])
            case .return, .space: select(section)
            default: return .ignored
            }
            return .handled
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func select(_ section: SettingsSection) {
        withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) { selection = section }
        focused = section
    }
}

/// Active / Test / Paused as three explained rows with a sliding highlight.
private struct ModeSelector: View {
    @Binding var mode: ActionAvailability.Mode
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Mode").padding(.horizontal, 10)
            VStack(spacing: 2) {
                ForEach(ActionAvailability.Mode.allCases, id: \.self) { option in
                    row(option)
                }
            }
            .padding(4)
            .background(Theme.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Operating mode")
    }

    private func row(_ option: ActionAvailability.Mode) -> some View {
        let isSelected = option == mode
        return Button {
            withAnimation(Motion.reduced(Motion.snappy, reduceMotion)) { mode = option }
        } label: {
            HStack(spacing: 10) {
                StatusDot(color: isSelected ? option.color : Theme.faint.opacity(0.6),
                          pulsing: isSelected && option == .active, size: 7)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.rawValue)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.ink : Theme.muted)
                    Text(option.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.thumbTop, Theme.thumbBottom],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "mode", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.rawValue): \(option.detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// What a double-tap will do right now, or why it won't.
private struct ArmedSummary: View {
    @ObservedObject var model: AppModel
    let openActions: () -> Void
    @State private var hovering = false
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let blocked = model.actionBlockReason
        Button(action: openActions) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Double-tap runs")
                HStack(spacing: 10) {
                    IconTile(symbol: model.doubleTapAction.symbol,
                             color: blocked == nil ? Theme.signal : Theme.warn, size: 30)
                        .scaleEffect(flash && !reduceMotion ? 1.12 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.doubleTapAction.shortName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(blocked ?? "Ready")
                            .font(.system(size: 11))
                            .foregroundStyle(blocked == nil ? Theme.ok : Theme.warn)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.faint)
                        .offset(x: hovering && !reduceMotion ? 2 : 0)
                }
            }
            .padding(12)
            .background(hovering ? Theme.tileHover : Theme.tile,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.reduced(Motion.fade, reduceMotion), value: hovering)
        // Every recognized double-tap gives the armed action a small nod.
        .onReceive(model.doubleTapRecognized) {
            guard !reduceMotion else { return }
            withAnimation(Motion.pop) { flash = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(Motion.settle) { flash = false }
            }
        }
        .help("Change the double-tap action")
    }
}

// MARK: - Calibration backdrop

/// Calibration is a full-window moment: the canvas with one soft signal glow.
private struct CalibrationBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RadialGradient(colors: [Theme.signal.opacity(scheme == .dark ? 0.12 : 0.08), .clear],
                       center: .center, startRadius: 10, endRadius: 460)
            .ignoresSafeArea()
    }
}

// MARK: - Window plumbing

// Track the whole settings window, including sections that do not contain a graph.
private struct SettingsWindowReader: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> WindowView { WindowView(model: model) }
    func updateNSView(_ view: WindowView, context: Context) {}
    final class WindowView: NSView {
        weak var model: AppModel?
        private var closeObserver: NSObjectProtocol?
        init(model: AppModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            model?.setupWindow = window
            if closeObserver == nil, let window {
                closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main
                ) { [weak model] _ in model?.handleWindowClose() }
            }
            if let window {
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = false
                window.backgroundColor = Palette.canvas
            }
        }
        deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
    }
}

/// Transparent AppKit view that only moves the window.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
