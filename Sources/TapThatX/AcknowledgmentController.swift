import AppKit
import SwiftUI

final class AcknowledgmentController {
    private var panel: NSPanel?
    private var generation = 0
    func show(_ message: String) {
        dismiss()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let width = min(430.0, screen.visibleFrame.width)
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 60, width: width, height: 60)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: Text(message).font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)))
        self.panel = panel; panel.orderFrontRegardless()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard self?.generation == token else { return }; self?.dismiss()
        }
    }
    func dismiss() { generation += 1; panel?.orderOut(nil); panel = nil }
}
