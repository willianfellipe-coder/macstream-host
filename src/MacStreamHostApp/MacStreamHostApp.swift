// SPDX-License-Identifier: GPL-3.0-or-later

import MacStreamCore
import SwiftUI

@main
@MainActor
struct MacStreamHostApp: App {
    @StateObject private var appState: AppState
    @State private var privacyOverlayController: PrivacyOverlayController?

    init() {
        _appState = StateObject(wrappedValue: AppState.localDiagnostics())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.refresh()
                }
                .onAppear {
                    if privacyOverlayController == nil {
                        privacyOverlayController = PrivacyOverlayController(
                            requiresPassword: { [weak appState] in
                                appState?.overlayUnlockRequiresPassword ?? false
                            },
                            onUnlock: { [weak appState] candidate in
                                appState?.dismissPrivacyOverlay(passwordCandidate: candidate) ?? false
                            }
                        )
                    }
                }
                .onChange(of: appState.privacyOverlayActive) { _, isActive in
                    if isActive {
                        privacyOverlayController?.show()
                    } else {
                        privacyOverlayController?.hide()
                    }
                }
        }
        .windowStyle(.titleBar)

        MenuBarExtra(
            "MacStream Host",
            systemImage: menuBarSymbol,
            isInserted: menuBarBinding
        ) {
            MenuBarContent(appState: appState)
        }
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(
            get: { appState.runtimeSettings.showMenuBarItem },
            set: { _ in /* toggled from Settings, not from the menu chrome */ }
        )
    }

    private var menuBarSymbol: String {
        if appState.privacyOverlayActive {
            return "lock.display"
        }
        switch appState.remoteWorkSession.state {
        case .running, .degraded: return "dot.radiowaves.left.and.right"
        case .starting, .stopping: return "arrow.triangle.2.circlepath"
        case .blocked: return "exclamationmark.triangle.fill"
        default: return "display"
        }
    }
}
