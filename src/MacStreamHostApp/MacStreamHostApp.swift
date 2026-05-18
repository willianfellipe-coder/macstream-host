// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

/// AppDelegate that pins activation policy on launch + on re-open. Two
/// distinct modes:
///
/// - `MacStreamHostSettings.startInBackground == false` (default):
///   Behaves like a normal Mac app. `.regular` policy, Dock icon, main
///   window shown, MenuBarExtra also visible. Activates on launch and
///   on re-open so the window comes to the front after macOS's
///   "Quit & Reopen" TCC dialog.
///
/// - `MacStreamHostSettings.startInBackground == true`:
///   Behaves as a tray-only background app. `.accessory` policy, no
///   Dock icon, the main window is dismissed right after WindowGroup
///   instantiates it. The user reaches the dashboard via the menu bar
///   item ("Abrir dashboard"). This is the mode for auto-start at
///   login: the system boots, server comes up, MacStream Host runs
///   silently in the tray ready to accept Moonlight clients.
final class MacStreamAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by MacStreamHostApp.init() before applicationDidFinishLaunching
    /// fires, so the delegate knows which mode to enter.
    static var startInBackground: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.startInBackground {
            NSApp.setActivationPolicy(.accessory)
            // Dismiss the WindowGroup window that SwiftUI creates by default.
            // We do it on the next run-loop tick because the window may not
            // have been added to NSApp.windows yet at this point.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.canBecomeMain {
                    window.orderOut(nil)
                }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // The user clicked the Dock icon (regular mode) or invoked the
        // app while the window is closed. Promote to regular if we were
        // in accessory mode so the user gets a Dock icon + window.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
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
        let state = AppState.localDiagnostics()
        _appState = StateObject(wrappedValue: state)
        // Communicate the mode to the AppDelegate BEFORE
        // applicationDidFinishLaunching fires. The delegate reads this
        // static when the run loop spins up.
        MacStreamAppDelegate.startInBackground = state.runtimeSettings.startInBackground
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
