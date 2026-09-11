import AppKit
import ApplicationServices
import TapCore

struct ActionExecutor {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func execute(_ command: Command, enabled: Bool) -> String {
        guard command.assistantIntent == nil else { return "Not sent: ChatGPT requires assistant controls" }
        guard enabled else { return "Dry run: \(command.rawValue)" }
        guard Self.trusted else { return "Not sent: Accessibility permission is required" }
        if command == .lock {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false) else {
                return "Not sent: could not create lock shortcut"
            }
            down.flags = [.maskControl, .maskCommand]; up.flags = [.maskControl, .maskCommand]
            down.post(tap: .cghidEventTap)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            // Give the system shortcut handler a normal key press duration.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { up.post(tap: .cghidEventTap) }
            return "Lock shortcut sent — waiting for macOS lock confirmation"
        }
        // Compatibility-sensitive system media events; no player is launched.
        let key: Int = command == .playPause ? 16 : (command == .next ? 17 : 18)
        func event(down: Bool) -> CGEvent? {
            NSEvent.otherEvent(with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                subtype: 8, data1: (key << 16) | ((down ? 0xA : 0xB) << 8), data2: -1)?.cgEvent
        }
        guard let down = event(down: true), let up = event(down: false) else { return "Not sent: media event creation failed" }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return "\(command.rawValue) command sent — playback not verified"
    }
}
