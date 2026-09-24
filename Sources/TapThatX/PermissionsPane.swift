import AppKit
import SwiftUI

struct PermissionsPane: View {
    @ObservedObject var model: AppModel
    @State private var settingsError: String?

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: ReactorTheme.surfaceRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ReactorBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PaneHeader(title: "A small setup. Then just tap.",
                               detail: "Keep TapThatX in Applications before granting access. Approve each permission in System Settings, then return here. Actions stay paused while this window is open.")

                    ReactorGlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            permissionCard("Accessibility", allowed: model.accessibilityPermission,
                                           detail: "Lets your chosen gestures lock the Mac, control media and activate app controls.") {
                                ActionExecutor.requestPermission()
                                openPrivacy("Privacy_Accessibility")
                            }
                            permissionCard("Input Monitoring", allowed: model.typingPermission,
                                           detail: "Helps ignore vibrations while you type. TapThatX uses key timing only; it never records what you type.") {
                                model.requestTypingPermission()
                                openPrivacy("Privacy_ListenEvent")
                            }
                        }
                    }

                    Text("macOS requires you to switch these permissions on yourself. If it asks you to quit and reopen TapThatX, do that before testing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)

                    HStack(spacing: 14) {
                        Button("Check permissions again") { model.refreshPermissions() }
                            .buttonStyle(.reactorBigButton)
                        if let settingsError {
                            Text(settingsError).font(.callout).foregroundStyle(.red)
                                .accessibilityLabel(settingsError)
                        }
                    }
                    .padding(.horizontal, 6)

                    sensorCard

                    installCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.status, systemImage: "waveform")
                .font(.title3.weight(.semibold))
            Text("Sensor access is checked separately. Shared ad-hoc builds use direct access; the authenticated helper requires an Apple-signed build. These permissions do not unlock the helper.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private var installCard: some View {
        DisclosureGroup("Installing a shared build") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Copy TapThatX to Applications. If macOS blocks its first launch, try Privacy & Security → Open Anyway.")
                Text("For a build received directly from someone you trust, this Terminal command removes only TapThatX’s download quarantine:")
                Text("xattr -dr com.apple.quarantine \"/Applications/TapThatX.app\"")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("This does not grant permissions, notarize the app or disable Gatekeeper globally. The DMG’s Start Here file includes these steps before the app can open.")
            }
            .font(.callout)
            .padding(.top, 10)
        }
        .font(.title3.weight(.semibold))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
    }

    private func permissionCard(_ title: String, allowed: Bool, detail: String,
                                request: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle")
                .font(.title2.weight(.medium))
                .foregroundStyle(allowed ? ReactorTheme.accent : Color.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    Text(allowed ? "Allowed" : "Needs access")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(allowed ? ReactorTheme.accent : Color.secondary)
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !allowed {
                    Button("Allow \(title)…", action: request)
                        .buttonStyle(.reactorBigButton)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .reactorGlass(in: surface)
        .reactorEdgeHighlight(in: surface)
        .accessibilityElement(children: .contain)
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
