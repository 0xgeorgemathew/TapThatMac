import AppKit
import SwiftUI

final class AcknowledgmentController {
    private var panel: NSPanel?
    private var generation = 0
    /// True when the main window is in front and shows the message itself.
    private let isRedundant: () -> Bool

    init(isRedundant: @escaping () -> Bool = { false }) {
        self.isRedundant = isRedundant
    }

    func show(_ message: String) {
        dismiss()
        guard !isRedundant() else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let width = min(460.0, screen.visibleFrame.width)
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 48, width: width, height: 84)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: ToastHUD(message: message))
        self.panel = panel; panel.orderFrontRegardless()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.generation == token else { return }; self?.dismiss()
        }
    }
    func dismiss() { generation += 1; panel?.orderOut(nil); panel = nil }
}

/// The on-screen confirmation: a graphite capsule that rises into place.
private struct ToastHUD: View {
    let message: String
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.signal)
                .symbolBounce(value: shown, reduceMotion: reduceMotion)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background {
            Capsule()
                .fill(LinearGradient(colors: [Theme.discTop, Theme.discBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.18), radius: 16, y: 6)
        }
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .offset(y: shown || reduceMotion ? 0 : 10)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(reduceMotion ? nil : Motion.snappy) { shown = true } }
    }
}
