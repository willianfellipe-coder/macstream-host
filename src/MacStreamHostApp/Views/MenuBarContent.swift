// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // Headline — status at a glance.
        Text(headlineTitle).bold()
        Text(headlineDetail).font(.caption)

        Divider()

        // Quick status (non-interactive).
        Text(keepAwakeLine)
        Text(agentLine)
        Text(privacyLine)
        if let pairing = pairingAddressLine {
            Text(pairing)
        }

        Divider()

        // Primary remote-work toggle.
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

        // Engine maintenance — only while running so the user can't
        // accidentally restart a not-yet-started engine.
        if isRunning {
            Button("Reiniciar motor de vídeo") {
                Task { await appState.restartSunshine() }
            }

            Button("Regerar configuração + reiniciar") {
                Task { await appState.regenerateAndRestartVideo() }
            }
        }

        Divider()

        // Host privacy — lock + unlock pair. Unlock is only shown when
        // the overlay is actually active so the menu stays compact.
        if appState.privacyOverlayActive {
            Button("Desbloquear tela do host") {
                _ = appState.dismissPrivacyOverlay(passwordCandidate: nil)
            }
            .disabled(appState.overlayUnlockRequiresPassword)
        } else {
            Button("Bloquear tela do host") {
                Task { await appState.lockHostForPrivacy() }
            }
            .disabled(!appState.runtimeSettings.hostPrivacyPolicy.allowManualLock)
        }

        Divider()

        // Diagnostics & ancillary actions.
        Button("Abrir painel web (Sunshine)") {
            Task { await appState.openSunshineWebUI() }
        }

        Button("Atualizar diagnóstico") {
            Task { await appState.refresh() }
        }

        Button("Exportar pacote de suporte") {
            Task { _ = await appState.exportRemoteWorkSupportBundle() }
        }

        Divider()

        // App lifecycle — dashboard + quit.
        Button("Abrir dashboard MacStream") {
            openMainWindow()
        }
        .keyboardShortcut("o", modifiers: .command)

        Button("Sair do MacStream Host") {
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

    /// First non-loopback address from the network diagnostic. Lets the
    /// user paste it into Moonlight's "Add Host Manually" without having
    /// to open the dashboard. Returns nil when nothing useful is
    /// available so the line is suppressed.
    private var pairingAddressLine: String? {
        guard let first = appState.dashboard.networkStatus.localAddresses.first else {
            return nil
        }
        return "Endereço: \(first)"
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

    /// Brings the SwiftUI WindowGroup window to the front. If the app
    /// was launched in background mode (accessory policy, no Dock icon),
    /// also promotes the activation policy to `.regular` so the user
    /// sees the Dock icon while interacting with the dashboard.
    private func openMainWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
