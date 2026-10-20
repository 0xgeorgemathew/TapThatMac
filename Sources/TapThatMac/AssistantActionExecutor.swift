import AppKit
import ApplicationServices
import TapCore

/// Inspect only the focused window, on a gesture; no background UI polling.
struct AssistantActionExecutor {
    static let bundleIdentifier = "com.openai.codex"
    static let browserIdentifiers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox"]
    struct Button {
        let element: AXUIElement
        let labels: [String]
    }
    private func buttons(in app: NSRunningApplication) -> [Button]? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var window = unsafeBitCast(focused, to: AXUIElement.self)
        if Self.browserIdentifiers.contains(app.bundleIdentifier ?? "") {
            guard let page = chatPage(in: window) else { return nil }
            window = page
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        var queue = [window], index = 0
        var found: [Button] = []
        while index < queue.count {
            // An incomplete scan must never choose an apparently unique action.
            guard index < 800, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let element = queue[index]; index += 1
            if index > 1 {
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                // Embedded web pages are not controls belonging to the host page.
                if role as? String == "AXWebArea", Self.browserIdentifiers.contains(app.bundleIdentifier ?? "") { continue }
            }
            func attribute(_ key: String) -> CFTypeRef? {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(element, key as CFString, &value)
                return value
            }
            if attribute(kAXRoleAttribute) as? String == kAXButtonRole,
               attribute(kAXEnabledAttribute) as? Bool == true {
                let labels = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute($0) as? String }
                found.append(Button(element: element, labels: labels))
            }
            if let children = attribute(kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        return found
    }
    private func chatPage(in window: AXUIElement) -> AXUIElement? {
        var queue = [window], index = 0
        var pages: [AXUIElement] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        while index < queue.count {
            guard index < 400, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let element = queue[index]; index += 1
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if role as? String == "AXWebArea" { pages.append(element); continue }
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if let children = children as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        guard pages.count == 1 else { return nil }
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(pages[0], "AXURL" as CFString, &value)
        let url = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
        return AssistantControls.isChatGPTPage(url) ? pages[0] : nil
    }
    func execute(_ intent: AssistantIntent, stillEnabled: @escaping () -> Bool, completion: @escaping (String) -> Void) {
        guard stillEnabled() else { completion("Actions paused"); return }
        guard ActionExecutor.trusted else { completion("Accessibility permission required"); return }
        // Prefer the desktop app's current window, even while another app is active.
        // Browser automation remains scoped to its currently focused ChatGPT page.
        let desktop = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first
        let front = NSWorkspace.shared.frontmostApplication
        let app = desktop ?? front.flatMap { Self.browserIdentifiers.contains($0.bundleIdentifier ?? "") ? $0 : nil }
        guard let app, let controls = buttons(in: app),
              AssistantControls.match(intent, labels: controls.map(\.labels)) != nil else {
            completion("No matching ChatGPT controls. Open the pending prompt in its current window."); return
        }
        guard stillEnabled() else { completion("Actions paused"); return }
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard stillEnabled() else { completion("Action cancelled: settings changed"); return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                completion("ChatGPT could not take focus"); return
            }
            // Re-read after activation; a previously discovered button may be stale.
            guard let current = self.buttons(in: app),
                  let selected = AssistantControls.match(intent, labels: current.map(\.labels)) else {
                completion("ChatGPT prompt changed or controls are ambiguous"); return
            }
            guard stillEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                completion("Action cancelled: focus or settings changed"); return
            }
            let result = AXUIElementPerformAction(current[selected].element, kAXPressAction as CFString)
            completion(result == .success ? "Activated ChatGPT: \(intent.rawValue)" : "ChatGPT did not accept the control action")
        }
    }
    func inspect() -> String {
        guard ActionExecutor.trusted else { return "Accessibility permission required" }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first,
              let buttons = buttons(in: app) else { return "ChatGPT controls could not be inspected completely" }
        let labels = buttons.map(\.labels)
        return "ChatGPT controls · approve/reject: \(AssistantControls.match(.accept, labels: labels) != nil ? "available" : "not found") · dictation: \(AssistantControls.match(.dictation, labels: labels) != nil ? "available" : "not found")"
    }
}
