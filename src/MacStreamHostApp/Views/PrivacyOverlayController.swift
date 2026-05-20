// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import MacStreamCore
import SwiftUI

@MainActor
final class PrivacyOverlayController {
    enum Mode {
        /// Classic dim-only privacy lock. Floating unlock panel + dim of
        /// physical displays. Equivalent to the pre-secure behavior.
        case classic(suppressPanel: Bool)
        /// Asymmetric secure overlay: full-screen black NSWindow on every
        /// non-streamed display, with the password panel only on a safe
        /// non-streamed display. The streamed display uses panel/backlight
        /// dimming plus a watchdog so the overlay never leaks to Moonlight.
        case secure(streamingActive: Bool, streamedDisplayID: CGDirectDisplayID?)
    }

    /// Bundle of closures the secure overlay needs. Kept as a struct so
    /// the controller signature stays manageable and tests can inject
    /// fixed values without subclassing.
    struct SecureContext {
        let allowMacOSAuthentication: () -> Bool
        let allowAppPassword: () -> Bool
        let macOSAuthAvailable: () -> Bool
        let isAppPasswordSet: () -> Bool
        let lockoutUntil: () -> Date?
        /// Fire-and-forget: kicks off the LocalAuthentication prompt.
        /// AppState flips `privacyOverlayMode` on success, which the App
        /// layer's `onChange` observer routes back to `hide()`.
        let onBiometric: () -> Void
        /// Synchronous: returns true on correct password (AppState will
        /// already have transitioned to `.none`).
        let onAppPassword: (String) -> Bool
    }

    private let brightness = DisplayBrightnessController()
    private var unlockPanel: NSWindow?
    private var secureWindows: [NSWindow] = []
    private var lastResult: DisplayDimResult?
    private let requiresPassword: () -> Bool
    private let onUnlock: (String?) -> Bool
    private let onDimResult: (DisplayDimResult) -> Void
    private let secureContext: SecureContext?
    private var brightnessWatchdog: Timer?

    /// Active secure-mode parameters, captured at `show(...)` time so the
    /// screen-parameter observer can rebuild without re-resolving.
    private var activeSecureMode: (streamingActive: Bool, streamedDisplayID: CGDirectDisplayID?)?
    private var screenObserver: NSObjectProtocol?

    init(
        requiresPassword: @escaping () -> Bool,
        onUnlock: @escaping (String?) -> Bool,
        onDimResult: @escaping (DisplayDimResult) -> Void = { _ in },
        secureContext: SecureContext? = nil
    ) {
        self.requiresPassword = requiresPassword
        self.onUnlock = onUnlock
        self.onDimResult = onDimResult
        self.secureContext = secureContext
    }

    var lastDimSummary: String? { lastResult?.summary }

    // MARK: - Public entry point

    /// Routes to the right rendering strategy for the requested mode.
    /// `hide()` is the unconditional inverse for both.
    func show(mode: Mode) {
        switch mode {
        case .classic(let suppressPanel):
            showClassic(suppressPanel: suppressPanel)
        case .secure(let streamingActive, let streamedDisplayID):
            showSecure(streamingActive: streamingActive, streamedDisplayID: streamedDisplayID)
        }
    }

    // MARK: - Classic mode (existing behavior)

    /// Classic dim path. Drops every physical display except the one
    /// hosting the dashboard to brightness 0 (built-in) or zero gamma
    /// (external). Optionally shows a floating unlock panel on the
    /// dashboard's screen. See the design notes inline for why the panel
    /// is suppressed during streaming.
    private func showClassic(suppressPanel: Bool) {
        guard unlockPanel == nil, secureWindows.isEmpty else { return }

        let hostScreen = interactiveScreen() ?? NSScreen.main
        let keepLitDisplayID = suppressPanel
            ? nil
            : hostScreen.flatMap { displayID(for: $0) }

        // The Sunshine engine captures `CGMainDisplayID()` by default.
        // Telling the dim controller about it skips gamma blackout
        // specifically for that display while brightness paths (panel
        // backlight only — invisible to SCK) still run.
        let mainDisplay = CGMainDisplayID()

        let result = brightness.dimAllDisplays(
            except: keepLitDisplayID,
            streamedDisplayID: suppressPanel ? mainDisplay : nil,
            streamingActive: suppressPanel
        )
        lastResult = result
        onDimResult(result)

        if !suppressPanel, let panelScreen = hostScreen {
            let panelSize = NSSize(width: 380, height: 220)
            let origin = NSPoint(
                x: panelScreen.frame.midX - panelSize.width / 2,
                y: panelScreen.frame.midY - panelSize.height / 2
            )
            let panel = KeyableBorderlessWindow(
                contentRect: NSRect(origin: origin, size: panelSize),
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: panelScreen
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

        // Only steal focus when we're actually showing a UI. With
        // `suppressPanel = true` (active Moonlight session) we want the
        // remote client to keep typing into whatever app they were
        // using — pulling MacStream Host to the front would redirect
        // keyboard events from `CGEventPost` into the dashboard window
        // and the user perceives that as a frozen mouse + dead
        // keyboard on the iPad.
        if !suppressPanel {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Secure mode

    /// Asymmetric secure overlay. The streamed display cannot host any
    /// `NSWindow` because ScreenCaptureKit captures it even with
    /// `sharingType = .none`. The streamed display therefore uses
    /// panel/backlight dimming plus a watchdog; password UI exists only
    /// on a non-streamed physical display.
    ///
    /// Per-display strategy:
    ///   - Streamed display (Sunshine's capture target), while streaming:
    ///       panel/backlight dimming only. No NSWindow, no password UI.
    ///       A watchdog reapplies dimming while locked so brightness-key
    ///       changes do not leave the host visible.
    ///   - Every other display: a full-screen black NSWindow covering
    ///       the entire `screen.frame` (including the menu bar area),
    ///       with the password panel hosted on the "safe display"
    ///       (NSScreen.main if it's non-streamed, otherwise the first
    ///       non-streamed screen). Remaining non-streamed displays get
    ///       a pure-black panel.
    ///
    /// When `streamingActive = false`, every display gets the secure
    /// window — Sunshine isn't sampling anything so there's nothing to
    /// leak into.
    private func showSecure(streamingActive: Bool, streamedDisplayID: CGDirectDisplayID?) {
        // Tear down any classic surfaces left over from a previous mode.
        unlockPanel?.orderOut(nil)
        unlockPanel = nil
        secureWindows.forEach { $0.orderOut(nil) }
        secureWindows.removeAll()
        stopBrightnessWatchdog()

        activeSecureMode = (streamingActive, streamedDisplayID)

        let screens = NSScreen.screens
        let safeScreen = pickSafeScreen(among: screens, streamedDisplayID: streamedDisplayID, streamingActive: streamingActive)

        for screen in screens {
            let id = displayID(for: screen)
            let isStreamedDisplay = streamingActive && streamedDisplayID != nil && id == streamedDisplayID
            // Do not put any NSWindow on the streamed display. Empirical
            // Moonlight validation shows ScreenCaptureKit still captures
            // this overlay even with sharingType = .none.
            if isStreamedDisplay {
                continue
            }
            let isSafePanel = (screen === safeScreen)
            let window = makeSecureWindow(on: screen, withUnlockPanel: isSafePanel)
            secureWindows.append(window)
            window.orderFrontRegardless()
            if isSafePanel {
                // Only the safe-panel window becomes key — that's where
                // the user types the password. Other displays are pure
                // black; they don't need keyboard focus.
                window.makeKeyAndOrderFront(nil)
            }
        }

        // The streamed display cannot receive a window without leaking
        // into Moonlight, so keep its panel/backlight dimmed and enforce
        // that state while the secure lock is active.
        let result = brightness.dimAllDisplays(
            except: nil,
            streamedDisplayID: streamingActive ? streamedDisplayID : nil,
            streamingActive: streamingActive
        )
        lastResult = result
        onDimResult(result)
        if streamingActive {
            startBrightnessWatchdog(streamedDisplayID: streamedDisplayID)
        }

        // Watch for monitor (un)plug events so we don't end up with
        // stale windows on a display that's gone or a missing window on
        // a display that just appeared.
        installScreenObserverIfNeeded()

        // During streaming, DO NOT activate the app — that would
        // redirect Sunshine's CGEventPost-injected events into our
        // SecureField. The user clicks the secure window's password
        // field locally to focus it (which is real HID, OK).
        if !streamingActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Builds a single per-display secure window. When `withUnlockPanel`
    /// is true the SwiftUI password panel is hosted as the contentView;
    /// otherwise the window stays pure black with no controls.
    private func makeSecureWindow(on screen: NSScreen, withUnlockPanel: Bool) -> SecureLockWindow {
        let window = SecureLockWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.setFrame(screen.frame, display: true)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.sharingType = .none
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        if withUnlockPanel, let context = secureContext {
            let hosting = NSHostingController(
                rootView: SecureLockOverlayContent(
                    allowMacOSAuthentication: context.allowMacOSAuthentication(),
                    allowAppPassword: context.allowAppPassword(),
                    macOSAuthAvailable: context.macOSAuthAvailable(),
                    isAppPasswordSet: context.isAppPasswordSet(),
                    lockoutUntil: context.lockoutUntil(),
                    onBiometric: { context.onBiometric() },
                    onAppPassword: { candidate in _ = context.onAppPassword(candidate) }
                )
            )
            hosting.view.frame = NSRect(origin: .zero, size: screen.frame.size)
            hosting.view.autoresizingMask = [.width, .height]
            window.contentView = hosting.view
        } else {
            let blackView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            blackView.autoresizingMask = [.width, .height]
            blackView.wantsLayer = true
            blackView.layer?.backgroundColor = NSColor.black.cgColor
            window.contentView = blackView
        }
        return window
    }

    /// Picks the display the user will see the password panel on.
    /// Priority:
    ///   1. NSScreen.main if it's NOT the streamed display (or no
    ///      streaming is active)
    ///   2. First screen in `NSScreen.screens` whose displayID != streamed
    ///   3. Any screen — the streaming-active guard above already
    ///      rejected single-display streamed scenarios at the AppState
    ///      pre-flight, so we should never fall through to "all screens
    ///      are streamed" in practice
    private func pickSafeScreen(
        among screens: [NSScreen],
        streamedDisplayID: CGDirectDisplayID?,
        streamingActive: Bool
    ) -> NSScreen? {
        if !streamingActive || streamedDisplayID == nil {
            return NSScreen.main ?? screens.first
        }
        if let main = NSScreen.main, displayID(for: main) != streamedDisplayID {
            return main
        }
        for screen in screens where displayID(for: screen) != streamedDisplayID {
            return screen
        }
        return nil
    }

    private func installScreenObserverIfNeeded() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildSecureWindowsAfterScreenChange()
            }
        }
    }

    private func removeScreenObserver() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    private func rebuildSecureWindowsAfterScreenChange() {
        guard let mode = activeSecureMode else { return }
        // Tear everything down and recreate from scratch — simpler than
        // diffing screens, and rare enough (plug/unplug events) that the
        // brief flicker is acceptable.
        secureWindows.forEach { $0.orderOut(nil) }
        secureWindows.removeAll()
        showSecure(streamingActive: mode.streamingActive, streamedDisplayID: mode.streamedDisplayID)
    }

    private func startBrightnessWatchdog(streamedDisplayID: CGDirectDisplayID?) {
        stopBrightnessWatchdog()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = self.brightness.dimAllDisplays(
                    except: nil,
                    streamedDisplayID: streamedDisplayID,
                    streamingActive: true
                )
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        brightnessWatchdog = timer
    }

    private func stopBrightnessWatchdog() {
        brightnessWatchdog?.invalidate()
        brightnessWatchdog = nil
    }

    // MARK: - Screen helpers

    /// Returns the screen the user is actively interacting with, falling
    /// through a priority chain: key window → main window → any visible
    /// main window → nil. The lock UX positions the unlock panel here
    /// and skips this screen when dimming the other displays.
    private func interactiveScreen() -> NSScreen? {
        if let key = NSApp.keyWindow, let screen = key.screen { return screen }
        if let main = NSApp.mainWindow, let screen = main.screen { return screen }
        if let any = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
           let screen = any.screen {
            return screen
        }
        return NSScreen.main
    }

    /// Extracts the `CGDirectDisplayID` from an `NSScreen` so we can
    /// pass it down to the brightness controller. The key
    /// "NSScreenNumber" is the documented way to retrieve the
    /// underlying displayID for an NSScreen on macOS.
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let value = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(value.uint32Value)
    }

    // MARK: - Hide

    func hide() {
        stopBrightnessWatchdog()
        brightness.restoreAllDisplays()
        unlockPanel?.orderOut(nil)
        unlockPanel = nil
        secureWindows.forEach { $0.orderOut(nil) }
        secureWindows.removeAll()
        activeSecureMode = nil
        removeScreenObserver()
        lastResult = nil
    }
}

private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Borderless full-screen window for the secure-lock overlay. Same
/// canBecomeKey contract as `KeyableBorderlessWindow`, plus an event
/// filter that drops synthetic keyboard input (CGEventPost from the
/// Moonlight engine). Real HID events pass through. This prevents the
/// remote user from typing into the password field even if focus
/// accidentally ends up here.
private final class SecureLockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // Only filter keyboard events — mouse events from the local
        // user (real HID) and synthetic mouse events from Sunshine on
        // OTHER displays don't reach this window anyway.
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged:
            if let cgEvent = event.cgEvent {
                let stateID = cgEvent.getIntegerValueField(.eventSourceStateID)
                // kCGEventSourceStateHIDSystemState = 1 → real keyboard.
                // Anything else (0 = combined session, -1 = private) is
                // synthetic injection. Drop it.
                if stateID != 1 {
                    return
                }
            }
        default:
            break
        }
        super.sendEvent(event)
    }
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
