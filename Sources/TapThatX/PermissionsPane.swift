import AppKit
import SwiftUI

struct PermissionsPane: View {
    @ObservedObject var model: AppModel
    @State private var settingsError: String?

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(title: "A small setup. Then just tap.",
                           detail: "Keep TapThatX in Applications before granting access. Approve each permission in System Settings, then return here. Actions stay paused while this window is open.")

                VStack(spacing: 20) {
                    PermissionTile(title: "Accessibility",
                                   allowed: model.accessibilityPermission,
                                   detail: "Lets your chosen gestures lock the Mac, control media and activate app controls.") {
                        ActionExecutor.requestPermission()
                        openPrivacy("Privacy_Accessibility")
                    }
                    PermissionTile(title: "Input Monitoring",
                                   allowed: model.typingPermission,
                                   detail: "Helps ignore vibrations while you type. TapThatX uses key timing only; it never records what you type.") {
                        model.requestTypingPermission()
                        openPrivacy("Privacy_ListenEvent")
                    }
                }

                    Text("macOS requires you to switch these permissions on yourself. If it asks you to quit and reopen TapThatX, do that before testing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)

                    HStack(spacing: 14) {
                        Button("Check permissions again") { model.refreshPermissions() }
                            .buttonStyle(.reactorButton)
                        if let settingsError {
                            Text(settingsError).font(.callout).foregroundStyle(.red)
                                .accessibilityLabel(settingsError)
                        }
                    }
                    .padding(.horizontal, 6)

                    sensorCard

                    installCard
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
        .reactorCard()
    }

    private var installCard: some View {
        DisclosureGroup("Installing a shared build") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Copy TapThatX to Applications. If macOS blocks its first launch, try Privacy & Security → Open Anyway.")
                Text("For a build received directly from someone you trust, this Terminal command removes only TapThatX's download quarantine:")
                Text("xattr -dr com.apple.quarantine \"/Applications/TapThatX.app\"")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("This does not grant permissions, notarize the app or disable Gatekeeper globally. The DMG's Start Here file includes these steps before the app can open.")
            }
            .font(.callout)
            .padding(.top, 10)
        }
        .font(.title3.weight(.semibold))
        .reactorCard()
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

/// One permission tile. When the permission flips to granted the status pill
/// springs a scale pop, the symbol bounces (macOS 15+, gated), and the tile
/// flashes a brief accent edge. All of it is static under Reduce Motion.
private struct PermissionTile: View {
    let title: String
    let allowed: Bool
    let detail: String
    let request: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pillPop = false
    @State private var edgeFlash = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "circle")
                .font(.title2.weight(.medium))
                .foregroundStyle(allowed ? ReactorTheme.accent : Color.secondary)
                .reactorSymbolBounce(value: allowed, reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    Text(allowed ? "Allowed" : "Needs access")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(allowed ? ReactorTheme.accent : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            allowed ? ReactorTheme.accent.opacity(0.14) : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .scaleEffect(pillPop ? 1.1 : 1)
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !allowed {
                    Button("Allow \(title)…", action: request)
                        .buttonStyle(.reactorButton(prominent: true))
                }
            }
        }
        .reactorCard()
        .overlay(
            // Brief accent edge flash when access is granted.
            ReactorTheme.panelShape
                .strokeBorder(ReactorTheme.accent.opacity(0.8), lineWidth: 1.5)
                .opacity(edgeFlash ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onChange(of: allowed) { _, granted in
            guard granted, !reduceMotion else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pillPop = true }
            withAnimation(.easeIn(duration: 0.12)) { edgeFlash = true }
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.easeOut(duration: 0.5)) { edgeFlash = false }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pillPop = false }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
