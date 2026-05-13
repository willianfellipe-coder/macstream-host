// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Text(headlineTitle)
            .bold()
        Text(headlineDetail)
            .font(.caption)

        Divider()

        // Status rows (non-interactive).
        Text(keepAwakeLine)
        Text(agentLine)
        Text(privacyLine)

        Divider()

        if isRunning {
            Button("Parar modo remoto") {
                Task { await appState.stopRemoteWorkMode() }
            }
        } else {
            Button("Iniciar modo remoto") {
                Task {
                    await appState.prepareRemoteWorkMode()
                    await appState.startRemoteWorkMode()
                }
            }
        }

        if isRunning {
            Button("Reiniciar mecanismo de vídeo") {
                Task { await appState.restartSunshine() }
            }

            Button("Regerar configuração + reiniciar") {
                Task { await appState.regenerateAndRestartVideo() }
            }

            Button("Bloquear host") {
                Task { await appState.lockHostForPrivacy() }
            }
        }

        Button("Atualizar diagnóstico") {
            Task { await appState.refresh() }
        }

        Divider()

        if appState.privacyOverlayActive {
            Button("Desbloquear tela") {
                // Menu bar fallback: only works when no password is required.
                _ = appState.dismissPrivacyOverlay(passwordCandidate: nil)
            }
            .disabled(appState.overlayUnlockRequiresPassword)
        }

        Button("Abrir MacStream Host") {
            openMainWindow()
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        Button("Sair") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var keepAwakeLine: String {
        appState.powerAssertionStatus.isActive
            ? "Keep-awake: ativo (Mac não dorme)"
            : "Keep-awake: inativo"
    }

    private var agentLine: String {
        appState.agentStatus.isRunning
            ? "Agente residente: ativo"
            : "Agente residente: aguardando"
    }

    private var privacyLine: String {
        "Privacidade: \(appState.hostPrivacyStatus.displayLabel)"
    }

    private var isRunning: Bool {
        appState.remoteWorkSession.state == .running
            || appState.remoteWorkSession.state == .degraded
            || appState.remoteWorkSession.state == .starting
    }

    private var headlineTitle: String {
        if appState.privacyOverlayActive {
            return "MacStream — host trancado"
        }
        switch appState.remoteWorkSession.state {
        case .running: return "MacStream — em uso remoto"
        case .ready: return "MacStream — pronto"
        case .starting: return "MacStream — iniciando…"
        case .stopping: return "MacStream — encerrando…"
        case .degraded: return "MacStream — em uso (avisos)"
        case .blocked: return "MacStream — bloqueado"
        case .notReady: return "MacStream — preparar"
        }
    }

    private var headlineDetail: String {
        let next = appState.remoteWorkSession.nextStep
        return next.isEmpty ? "Acesso remoto produtivo do Mac." : next
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
