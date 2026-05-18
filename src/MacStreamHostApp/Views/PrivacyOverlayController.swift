// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

@MainActor
final class PrivacyOverlayController {
    private let brightness = DisplayBrightnessController()
    private var unlockPanel: NSWindow?
    private var lastResult: DisplayDimResult?
    private let requiresPassword: () -> Bool
    private let onUnlock: (String?) -> Bool
    private let onDimResult: (DisplayDimResult) -> Void

    init(
        requiresPassword: @escaping () -> Bool,
        onUnlock: @escaping (String?) -> Bool,
        onDimResult: @escaping (DisplayDimResult) -> Void = { _ in }
    ) {
        self.requiresPassword = requiresPassword
        self.onUnlock = onUnlock
        self.onDimResult = onDimResult
    }

    var lastDimSummary: String? { lastResult?.summary }

    /// Drops every physical display except the one hosting the dashboard
    /// to brightness 0 (built-in) or zero gamma (external), so the local
    /// viewer goes dark while the framebuffer continues to be produced
    /// normally — Moonlight keeps seeing the live desktop and the remote
    /// user can keep working through the Mac. The dashboard's display
    /// stays lit so the floating unlock panel (and the dashboard "Bloquear"
    /// button) remain visible to the local user; otherwise gamma=0 / brightness=0
    /// would also hide the unlock UI itself.
    ///
    /// Sidecar/AirPlay displays are skipped because dimming a wireless
    /// display can affect its framebuffer. When the caller passes
    /// `suppressPanel: true` (because a Moonlight session is active), we
    /// deliberately skip the floating unlock panel: even with
    /// `sharingType = .none`, ScreenCaptureKit on macOS Sequoia still
    /// leaks the panel into the captured frame and the panel intercepts
    /// forwarded remote input. In that case the remote user can unlock
    /// through the menu bar instead.
    func show(suppressPanel: Bool = false) {
        guard unlockPanel == nil else { return }

        // Pick the display we keep lit so the unlock UI stays visible to
        // the local user. Preference order:
        //   1. The display containing the currently-key (focused) window
        //   2. The display containing any visible MacStream main window
        //   3. NSScreen.main (the menu-bar screen)
        //
        // When `suppressPanel = true` there is no floating unlock panel
        // to keep visible — the engine is actively streaming and the
        // local user is using the iPad. In that mode every display
        // gets a chance to dim (within the streaming-safe knobs), and
        // unlocking is routed through the menu bar.
        let hostScreen = interactiveScreen() ?? NSScreen.main
        let keepLitDisplayID = suppressPanel
            ? nil
            : hostScreen.flatMap { displayID(for: $0) }

        // The Sunshine engine captures `CGMainDisplayID()` by default.
        // Telling the dim controller about it means gamma blackout is
        // skipped specifically for that display while the brightness
        // paths (panel backlight only — invisible to ScreenCaptureKit)
        // still run. So the built-in MacBook lid still goes dark while
        // the remote feed keeps painting normally.
        let mainDisplay = CGMainDisplayID()

        let result = brightness.dimAllDisplays(
            except: keepLitDisplayID,
            streamedDisplayID: suppressPanel ? mainDisplay : nil,
            streamingActive: suppressPanel
        )
        lastResult = result
        onDimResult(result)

        if !suppressPanel, let panelScreen = hostScreen {
            let panelSize = NSSize(width: 380, height: 220)
            let origin = NSPoint(
                x: panelScreen.frame.midX - panelSize.width / 2,
                y: panelScreen.frame.midY - panelSize.height / 2
            )
            let panel = KeyableBorderlessWindow(
                contentRect: NSRect(origin: origin, size: panelSize),
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: panelScreen
            )
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.sharingType = .none
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let hosting = NSHostingController(
                rootView: PrivacyOverlayContent(
                    requiresPassword: requiresPassword(),
                    onUnlock: { [weak self] candidate in
                        self?.onUnlock(candidate) ?? false
                    }
                )
            )
            hosting.view.frame = NSRect(origin: .zero, size: panelSize)
            panel.contentView = hosting.view

            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            unlockPanel = panel
        }

        // Only steal focus when we're actually showing a UI. With
        // `suppressPanel = true` (active Moonlight session) we want the
        // remote client to keep typing into whatever app they were
        // using — pulling MacStream Host to the front would redirect
        // keyboard events from `CGEventPost` into the dashboard window
        // and the user perceives that as a frozen mouse + dead
        // keyboard on the iPad.
        if !suppressPanel {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Returns the screen the user is actively interacting with, falling
    /// through a priority chain: key window → main window → any visible
    /// main window → nil. The lock UX positions the unlock panel here
    /// and skips this screen when dimming the other displays.
    private func interactiveScreen() -> NSScreen? {
        if let key = NSApp.keyWindow, let screen = key.screen { return screen }
        if let main = NSApp.mainWindow, let screen = main.screen { return screen }
        if let any = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
           let screen = any.screen {
            return screen
        }
        return NSScreen.main
    }

    /// Extracts the `CGDirectDisplayID` from an `NSScreen` so we can
    /// pass it down to the brightness controller. The key
    /// "NSScreenNumber" is the documented way to retrieve the
    /// underlying displayID for an NSScreen on macOS.
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(value.uint32Value)
    }

    func hide() {
        brightness.restoreAllDisplays()
        unlockPanel?.orderOut(nil)
        unlockPanel = nil
        lastResult = nil
    }
}

private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PrivacyOverlayContent: View {
    let requiresPassword: Bool
    let onUnlock: (String?) -> Bool
    @State private var passwordCandidate: String = ""
    @State private var showingMismatchError: Bool = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: requiresPassword ? "lock.shield" : "lock.display")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
            Text("Host bloqueado para uso remoto")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Só você (no Mac) vê esta janela. O cliente remoto continua acessando o desktop normalmente.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if requiresPassword {
                SecureField("Senha do MacStream", text: $passwordCandidate)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordFocused)
                    .frame(maxWidth: 240)
                    .onSubmit(attemptUnlock)

                if showingMismatchError {
                    Label("Senha incorreta", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Button(action: attemptUnlock) {
                Label("Desbloquear", systemImage: "lock.open")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(requiresPassword && passwordCandidate.isEmpty)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        )
        .padding(8)
        .onAppear {
            if requiresPassword {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    passwordFocused = true
                }
            }
        }
    }

    private func attemptUnlock() {
        let candidate: String? = requiresPassword ? passwordCandidate : nil
        let unlocked = onUnlock(candidate)
        if unlocked {
            passwordCandidate = ""
            showingMismatchError = false
        } else {
            showingMismatchError = true
            passwordCandidate = ""
            passwordFocused = true
        }
    }
}
