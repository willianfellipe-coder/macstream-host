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

    /// Drops every built-in physical display to brightness 0 so the local
    /// viewer goes dark while the framebuffer continues to be produced
    /// normally — Moonlight keeps seeing the live desktop and the remote user
    /// can keep working through the Mac. Sidecar/AirPlay displays are skipped
    /// because dimming a wireless display can affect its framebuffer. A small
    /// "Desbloquear" panel floats on the main screen so the local user can
    /// dismiss the overlay. We **never** fall back to an NSWindow blackout —
    /// that overlay leaks into ScreenCaptureKit and into the Moonlight feed.
    func show() {
        guard unlockPanel == nil else { return }

        let result = brightness.dimAllDisplays()
        lastResult = result
        onDimResult(result)

        if let mainScreen = NSScreen.main {
            let panelSize = NSSize(width: 380, height: 220)
            let origin = NSPoint(
                x: mainScreen.frame.midX - panelSize.width / 2,
                y: mainScreen.frame.midY - panelSize.height / 2
            )
            let panel = KeyableBorderlessWindow(
                contentRect: NSRect(origin: origin, size: panelSize),
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: mainScreen
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

        NSApp.activate(ignoringOtherApps: true)
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
