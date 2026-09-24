import SwiftUI
import AppKit
import TapCore

@main
struct TapThatXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra {
            MenuContents(model: model)
        } label: {
            MenuBarIcon(paused: model.paused)
        }
        Window("TapThatX Settings", id: "setup") {
            SetupView(model: model).onAppear { delegate.model = model }
        }
        // Full-size content view: the titlebar is transparent and the traffic
        // lights float over the glass content, as in modern macOS chrome.
        // hiddenTitleBar exists since macOS 11 and picks up the macOS 26+
        // rounded Liquid Glass refinements automatically, so no version fork
        // is needed at the macOS 14 deployment target.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 660)
    }
}

private struct MenuBarIcon: View {
    let paused: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var launched = false
    var body: some View {
        iconView
            .accessibilityLabel("TapThatX")
            .onAppear {
                guard !launched else { return }
                launched = true
                if CommandLine.arguments.contains("--show-setup") || !ActionExecutor.trusted || !CGPreflightListenEventAccess() {
                    openWindow(id: "setup")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = loadMenuBarImage(paused: paused) {
            Image(nsImage: icon)
        } else {
            Image(systemName: paused ? "pause.circle" : "waveform.path")
        }
    }

    private func loadMenuBarImage(paused: Bool) -> NSImage? {
        let name = paused ? "MenuBarIconPaused" : "MenuBarIcon"
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            return image
        }
        return nil
    }
}

private struct MenuContents: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Text(model.actionBlockReason ?? "Actions enabled")
        Divider()
        Text("Double-tap: \(model.doubleTapAction.rawValue)")
        Toggle("Pause recognition", isOn: $model.paused)
        Button("Open command ring") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.previewRing() } }
        Button("Save last 15 seconds") { model.saveRecentActivity() }
        Button("Settings…") { openWindow(id: "setup"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Text(model.acknowledgment)
        Button("Quit TapThatX") { model.shutdown(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
