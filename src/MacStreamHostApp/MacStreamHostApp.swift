// SPDX-License-Identifier: GPL-3.0-or-later

import MacStreamCore
import SwiftUI

@main
@MainActor
struct MacStreamHostApp: App {
    @StateObject private var appState: AppState

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
        }
        .windowStyle(.titleBar)
    }
}
