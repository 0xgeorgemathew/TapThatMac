import AppKit
import SwiftUI

struct PermissionsPane: View {
    @ObservedObject var model: AppModel
    @State private var settingsError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "A small setup. Then just tap.",
                       detail: "Keep TapThatX in Applications before granting access. Approve each permission in System Settings, then return here. Actions stay paused while this window is open.")
            Form {
                Section {
                    permission("Accessibility", allowed: model.accessibilityPermission,
                               detail: "Lets your chosen gestures lock the Mac, control media and activate app controls.") {
                        ActionExecutor.requestPermission()
                        openPrivacy("Privacy_Accessibility")
                    }
                    permission("Input Monitoring", allowed: model.typingPermission,
                               detail: "Helps ignore vibrations while you type. TapThatX uses key timing only; it never records what you type.") {
                        model.requestTypingPermission()
                        openPrivacy("Privacy_ListenEvent")
                    }
                } footer: {
                    // Grouped-form footers misalign on macOS: the block needs a
                    // leading frame and wrapped lines need leading text alignment.
                    Text("macOS requires you to switch these permissions on yourself. If it asks you to quit and reopen TapThatX, do that before testing.")
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Button("Check permissions again") { model.refreshPermissions() }
                    if let settingsError {
                        Text(settingsError).font(.callout).foregroundStyle(.red).accessibilityLabel(settingsError)
                    }
                }
                Section {
                    Label(model.status, systemImage: "waveform")
                    Text("Sensor access is checked separately. Shared ad-hoc builds use direct access; the authenticated helper requires an Apple-signed build. These permissions do not unlock the helper.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Installing a shared build") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Copy TapThatX to Applications. If macOS blocks its first launch, try Privacy & Security → Open Anyway.")
                            Text("For a build received directly from someone you trust, this Terminal command removes only TapThatX’s download quarantine:")
                            Text("xattr -dr com.apple.quarantine \"/Applications/TapThatX.app\"")
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("This does not grant permissions, notarize the app or disable Gatekeeper globally. The DMG’s Start Here file includes these steps before the app can open.")
                        }.font(.callout).padding(.top, 10)
                    }
                }
            }
            .formStyle(.grouped)
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
    }

    private func permission(_ title: String, allowed: Bool, detail: String,
                            request: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle")
                .font(.headline)
                .foregroundStyle(allowed ? ReactorTheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !allowed { Button("Allow \(title)…", action: request) }
            }
            Spacer()
            Text(allowed ? "Allowed" : "Needs access")
                .foregroundStyle(allowed ? ReactorTheme.accent : Color.secondary)
        }.padding(.vertical, 4)
    }

    private func openPrivacy(_ pane: String) {
        settingsError = nil
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
              NSWorkspace.shared.open(url) else {
            settingsError = "Open System Settings → Privacy & Security and select the permission manually."
            return
        }
    }
}
