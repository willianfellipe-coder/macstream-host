// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

@MainActor
final class PrivacyOverlayController {
    private var windows: [NSWindow] = []
    private let onUnlock: () -> Void

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
    }

    func show() {
        guard windows.isEmpty else { return }

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
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hasShadow = false

            let hosting = NSHostingController(
                rootView: PrivacyOverlayContent(onUnlock: { [weak self] in
                    self?.onUnlock()
                })
            )
            hosting.view.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentView = hosting.view

            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}

struct PrivacyOverlayContent: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.display")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Host bloqueado para uso remoto")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("Esta tela ficou opaca enquanto o iPad usa o Mac via Moonlight. O streaming continua sem interrupção.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onUnlock()
                } label: {
                    Label("Desbloquear", systemImage: "lock.open")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 8)
            }
        }
    }
}
