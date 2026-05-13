// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

@MainActor
final class PrivacyOverlayController {
    private var backdropWindows: [NSWindow] = []
    private var unlockPanel: NSWindow?
    private let requiresPassword: () -> Bool
    private let onUnlock: (String?) -> Bool

    init(
        requiresPassword: @escaping () -> Bool,
        onUnlock: @escaping (String?) -> Bool
    ) {
        self.requiresPassword = requiresPassword
        self.onUnlock = onUnlock
    }

    /// Builds a multi-window blackout that is invisible to screen capture.
    /// Backdrop windows cover every display with a solid black surface; the
    /// unlock panel floats over the main screen and is the only target that
    /// captures input. Setting `sharingType = .none` removes both layers from
    /// CGWindowList and ScreenCaptureKit feeds, so a remote Moonlight viewer
    /// still sees the live desktop and can keep working through the Mac.
    func show() {
        guard backdropWindows.isEmpty else { return }

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.isMovable = false
            window.ignoresMouseEvents = true
            window.sharingType = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hasShadow = false
            window.orderFrontRegardless()
            backdropWindows.append(window)
        }

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
        for window in backdropWindows { window.orderOut(nil) }
        backdropWindows.removeAll()
        unlockPanel?.orderOut(nil)
        unlockPanel = nil
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
