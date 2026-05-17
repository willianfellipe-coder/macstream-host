// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

/// AppDelegate that pins activation policy to `.regular` (dock icon + window
/// + menu bar item) and force-activates on launch + on re-open. Without this
/// the combination of `MenuBarExtra` + macOS quit-and-reopen (which fires
/// after every TCC permission toggle) leaves SwiftUI in a state where the
/// main window stays alive but never comes to the foreground — the user sees
/// "the app didn't open" because System Settings is in front and the window
/// stays on whichever Space it was last on.
final class MacStreamAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

@main
@MainActor
struct MacStreamHostApp: App {
    @NSApplicationDelegateAdaptor(MacStreamAppDelegate.self) private var appDelegate
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
                    appState.startLiveMonitors()
                }
                .onAppear {
                    if privacyOverlayController == nil {
                        privacyOverlayController = PrivacyOverlayController(
                            requiresPassword: { [weak appState] in
                                appState?.overlayUnlockRequiresPassword ?? false
                            },
                            onUnlock: { [weak appState] candidate in
                                appState?.dismissPrivacyOverlay(passwordCandidate: candidate) ?? false
                            },
                            onDimResult: { [weak appState] result in
                                appState?.reportPrivacyLockDimResult(result.summary, didDimAny: result.didDimAny)
                            }
                        )
                    }
                }
                .onChange(of: appState.privacyOverlayActive) { _, isActive in
                    if isActive {
                        // Suppress the floating unlock panel while a Moonlight
                        // session is active: the panel renders a black-ish
                        // surface that ScreenCaptureKit still picks up despite
                        // sharingType=.none, AND its window level intercepts
                        // mouse events forwarded from the remote client. When
                        // streaming, only dim physical displays; the remote
                        // user unlocks via the menu bar item.
                        privacyOverlayController?.show(
                            suppressPanel: appState.remoteWorkSession.state.isStreamingActive
                        )
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
