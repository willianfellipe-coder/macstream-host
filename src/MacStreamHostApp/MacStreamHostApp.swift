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
                        privacyOverlayController = PrivacyOverlayController(onUnlock: {
                            appState.dismissPrivacyOverlay()
                        })
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
    }
}
