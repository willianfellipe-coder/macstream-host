# Changelog

All notable changes to MacStream Host will be documented here.

## Unreleased

### Restore Sunshine.app packaging and prevent flat-helper regressions (2026-05-19)

User report: after recent changes, Moonlight could not connect to
MacStream Host. The previous investigation incorrectly treated it as a
network issue. It was local engine startup.

**Root cause:** Sunshine had been flattened into
`Contents/MacOS/MacStreamEngine` and launched through
`responsibility_spawnattrs_setdisclaim`. On macOS 26 that process could
hang in the AVFoundation/VideoToolbox dummy-frame encoder probe before
opening HTTP, HTTPS/nvhttp, Web UI, or RTSP sockets. The process looked
alive, but `lsof` showed no listening Sunshine ports, so Moonlight had
nothing to connect to.

**Fix:**
- Package Sunshine as a real nested app at
  `Contents/Resources/sunshine/Sunshine.app`.
- Prefer the nested `Sunshine.app/Contents/MacOS/Sunshine` binary in
  `DefaultSunshineBinaryResolver`; keep `MacStreamEngine` only as a
  legacy fallback.
- Remove `ResponsibilityDisclaim.swift` and launch Sunshine with normal
  `Process()` semantics.
- Make ownership validation compare the resolved binary path, not just
  the config path.
- Make `start()` replace stale owned processes from the broken
  flat-helper layout.
- Make `restart()` clear stale ownership mismatch and start fresh.
- Report a running process with unreachable Web UI as `degraded`
  instead of healthy.
- Delete the obsolete LIEF `embed_lsuielement.py` helper so future
  packaging work cannot accidentally recreate the flat Mach-O helper
  path.

**Runtime validation performed:**
- Installed clean app in `/Applications`.
- Confirmed `macstreamctl paths` resolves to the nested
  `Sunshine.app`.
- Confirmed `/Applications/MacStream Host.app/Contents/MacOS/MacStreamEngine`
  is absent.
- Confirmed `codesign --verify --deep --strict` passes.
- Confirmed Sunshine runs as `Sunshine`, ownership points to the nested
  app, Web UI is reachable, and TCP `47984`, `47989`, `47990`, `48010`
  listen locally.
- Confirmed Moonlight discovers the host, pairs, and connects after the
  nested engine Screen Recording grant is applied and the engine is
  restarted.

**Docs:** Added `docs/SUNSHINE_ENGINE_RUNBOOK.md` with root cause,
non-negotiable regression guards, packaging checks, TCC requirements,
Moonlight error triage, and validation commands.

**Tests:** `SunshineManagerTests` now covers resolver priority, stale
owned process replacement, restart mismatch recovery, legacy engine
rejection when embedded Sunshine is expected, and degraded Web UI
status.

### Secure lock mode: black overlay with mandatory password unlock (2026-05-18)

User report: the existing "Bloquear host" only dimmed displays — anyone
physically at the Mac could wake the panel and see the desktop, which
isn't a real security boundary. Implemented an opt-in **Modo bloqueio
seguro** that lives alongside the existing dim-only mode (selectable in
Settings → Modo de bloqueio do host).

**Strategy: asymmetric per-display rendering.** A documented
ScreenCaptureKit limitation on macOS Sequoia/26 means
`NSWindow.sharingType = .none` is not a reliable exclusion mechanism —
a black full-screen NSWindow on the streamed display would leak into
the Moonlight feed. The only proven invisible-to-SCK technique is
`brightness=0` on the panel itself (panel-side, SCK never sees it).

Per-display behavior when secure lock activates:

| Display | Streaming OFF | Streaming ON, NOT captured | Streaming ON, IS captured |
|---|---|---|---|
| Built-in MacBook | NSWindow preto + brightness=0 + gamma=0 | NSWindow preto + brightness=0 + gamma=0 | **brightness=0 só** (sem NSWindow, sem UI) |
| LG external | NSWindow preto + gamma=0 | NSWindow preto + gamma=0 | brightness path (no-op) + sem NSWindow |
| Painel de senha | em qualquer | só nos não-capturados | só nos não-capturados |

**Pre-flight rejects two cases**:
- No unlock method available (no app password set AND LocalAuth
  unavailable). User is routed to Settings → Bloqueio seguro.
- Streaming + only display is the streamed one. User must disconnect
  Moonlight or plug a second display before locking.

**Auth methods (both opt-in via Settings)**:
- **MacStream app password** (existing `AppPasswordStore`, Keychain).
- **Touch ID / senha do macOS** via new
  [LocalAuthenticationService.swift](src/MacStreamCore/Managers/LocalAuthenticationService.swift)
  (wraps `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`).

**Anti-bypass**:
- The classic `dismissPrivacyOverlay(passwordCandidate: nil)` (tray
  bypass) **refuses** to unlock when mode is `.secure`. Test coverage:
  `testClassicDismissDoesNotUnlockSecureMode`. The tray item is
  replaced with a passive indicator during secure mode.
- The dashboard also hides its inline unlock button in secure mode —
  the remote Moonlight viewer could otherwise click it through the
  streamed display.
- `SecureLockWindow.sendEvent(_:)` filters keyboard events by
  `kCGEventSourceStateID`: real HID (state == 1) passes, synthetic
  injection from `CGEventPost` (state ∈ {0, -1}) is dropped. So even
  if focus accidentally lands on the password SecureField, Sunshine
  can't type into it from the remote client.

**Lockout**:
- Configurable `secureMaxUnlockAttempts` (default 5). On hit, enters a
  temporal lockout (30s × extra attempt, capped at 5min) — modeled as
  `@Published secureLockoutUntil: Date?`. Counter resets on successful
  auth. **Temporal**, not permanent — no risk of being permanently
  locked out.

**Multi-display geometry change**:
- `PrivacyOverlayController` observes
  `NSApplication.didChangeScreenParametersNotification` while in
  secure mode and rebuilds the per-display window stack when the user
  plugs/unplugs a monitor.

**Auto-release on Moonlight disconnect**:
- Existing `streamEndWatcher` is reused for secure mode too — once
  the remote viewer disconnects there's nothing to protect against,
  so the lock auto-releases (matches classic mode UX).

**Files**:
- New: [src/MacStreamCore/Managers/LocalAuthenticationService.swift](src/MacStreamCore/Managers/LocalAuthenticationService.swift)
- New: [src/MacStreamHostApp/Views/SecureLockOverlayContent.swift](src/MacStreamHostApp/Views/SecureLockOverlayContent.swift)
- Modified: [DomainModels.swift](src/MacStreamCore/Models/DomainModels.swift) (HostPrivacyMode adds `.secureOverlay`; HostPrivacyPolicy adds three secure-* fields with backwards-compatible Codable migration)
- Modified: [AppState.swift](src/MacStreamCore/Services/AppState.swift) (PrivacyOverlayMode enum replaces the single Bool; pre-flight, lockout, biometric/password dismiss methods; DisplayInventoryProviding for testability)
- Modified: [PrivacyOverlayController.swift](src/MacStreamHostApp/Views/PrivacyOverlayController.swift) (Mode-based `show()`; asymmetric per-display rendering; SecureLockWindow with HID-only event filter)
- Modified: [MacStreamHostApp.swift](src/MacStreamHostApp/MacStreamHostApp.swift) (routes on `privacyOverlayMode` enum; passes SecureContext closures to the controller)
- Modified: [ContentView.swift](src/MacStreamHostApp/Views/ContentView.swift) (dashboard button switches on mode; new "Bloqueio seguro" Settings GroupBox)
- Modified: [MenuBarContent.swift](src/MacStreamHostApp/Views/MenuBarContent.swift) (tray item disabled in secure mode)

**Tests**: 16 new tests bring the suite to 151/151.
- 9 in `AppStateTests` covering pre-flight (no auth, biometric available, app password set), correct/wrong password, biometric path, lockout temporal backoff, classic-dismiss-refuses-secure.
- 4 in new `LocalAuthenticationServiceTests` covering the mock's availability/auth/error paths.
- 4 in new `HostPrivacyPolicyCodableTests` covering legacy JSON decode (no secure fields) + round-trip preservation + defaults backwards compatibility.

### Document the iPad cursor duplication (2026-05-18)

User report: with the iPad on a Magic Keyboard / external mouse, the
Moonlight session shows two cursors simultaneously — the iPad's native
system pointer rendered on top of the streamed host cursor. This is
**not** a MacStream regression: Sunshine doesn't expose a cursor
visibility knob, none of the recent commits (multi-display lock, lock
toggle, low-latency profile) touched cursor rendering, and `strings` on
the engine confirms there's no `capture_cursor` / `show_cursor` /
`hide_cursor` config key. The duplication is iPadOS rendering its own
pointer on top of every app (including the Moonlight video layer) when
a trackpad/mouse is paired.

Fix is on the iPad side. Documented in `docs/POST_INSTALL.md`
troubleshooting table: tap the screen once during the session to enter
"mouse capture mode" (iPad pointer disappears, only host cursor stays).
Alternatively, set Moonlight iOS settings → `Touchscreen mode` to
`Touchscreen as trackpad`.

### Dashboard lock/unlock toggle (2026-05-18)

The "Bloquear host" action in the main dashboard
([ContentView.swift:166-193](src/MacStreamHostApp/Views/ContentView.swift#L166-L193))
now toggles to "Desbloquear host" while `appState.privacyOverlayActive`
is true. Before this fix the dashboard button stayed labelled "Bloquear
host" even when the lock was active, and the only way to unlock from
the GUI was via the menu bar item — surprising UX after the multi-
display lock fix made the dashboard's display stay lit.

The unlock branch reuses `appState.dismissPrivacyOverlay(passwordCandidate: nil)`
(same call the tray uses), painted with `.tint(.orange)` for
consistency with `AccessibilityRecoveryBanner`. When
`appState.overlayUnlockRequiresPassword` is true the inline button is
disabled with a help tooltip routing the user to the floating panel
(which has the password field). No new state was added.

### Multi-display lock without freezing the remote stream (2026-05-18)

End-to-end rework of the privacy lock so it dims **every** physical
display attached to the Mac (built-in panel + LG ULTRAWIDE external)
without breaking the Moonlight session.

- **Gamma blackout fallback for externals.**
  [DisplayBrightnessController.swift](src/MacStreamHostApp/Views/DisplayBrightnessController.swift)
  gained `CGSetDisplayTransferByFormula`-based gamma blackout. External
  displays (LG via DisplayPort/HDMI) don't accept
  `DisplayServicesSetBrightness` or `IODisplaySetFloatParameter`, so
  brightness-only paths used to skip them. Gamma blackout is the only
  knob that physically darkens those panels without putting them in
  standby.
- **Keep the dashboard's display lit so the unlock UI stays visible.**
  `PrivacyOverlayController.show(suppressPanel:)` picks an
  `interactiveScreen()` (priority: key window → main window → any
  visible main window → `NSScreen.main`) and dims everything **except**
  that display when `suppressPanel = false`. The floating unlock panel
  is positioned on that screen. Without this, gamma=0 / brightness=0
  hides the unlock panel itself.
- **Don't freeze the Moonlight cursor when locking during an active
  stream.** Three concurrent root causes:
  1. **Gamma blackout corrupts the ScreenCaptureKit feed.** SCStream
     samples the framebuffer post-gamma on the streamed display, so
     gamma=0 turned the remote feed black AND caused SCK to drop frames.
     Fix: `dimAllDisplays(except:streamedDisplayID:streamingActive:)`
     now skips gamma on the `streamedDisplayID` (the engine's
     `CGMainDisplayID()`) but still attempts brightness paths — the
     panel backlight on a MacBook is invisible to SCK.
  2. **`NSApp.activate(ignoringOtherApps:)` redirected
     `CGEventPost`-injected keyboard events to the dashboard window.**
     Fix: when `suppressPanel = true` (stream is live), the controller
     deliberately does **not** activate the app.
  3. **The floating unlock panel leaked into the captured frame as a
     black rectangle and intercepted forwarded mouse events** on
     macOS Sequoia/Tahoe despite `sharingType = .none`. Fix: don't
     create the panel during streaming (`suppressPanel = true`).
     Unlocking during a stream is routed through the menu bar item.
- **Built-in MacBook panel still goes dark even while streaming from
  it.** The brightness path (DisplayServices → IOKit) only touches the
  backlight, which SCStream cannot see. So the local viewer goes dark
  while the remote viewer keeps seeing the live desktop.

Behavior matrix:

| Display state | Lock mode | Method order |
|---|---|---|
| Built-in, not streaming | normal lock | DisplayServices → IOKit → gamma |
| Built-in, streaming | normal lock | DisplayServices → IOKit (no gamma) |
| External, not streaming | normal lock | gamma → DisplayServices → IOKit |
| External, streaming, **is** the streamed display | normal lock | DisplayServices → IOKit (no gamma) |
| External, streaming, **not** the streamed display | normal lock | gamma → DisplayServices → IOKit |
| Any display containing the active window | not streaming | **skipped** (keeps unlock panel visible) |

Sidecar / AirPlay receivers are still skipped entirely — dimming a
wireless display can affect its framebuffer.

### Stop the Tailscale CLI shim error spam (2026-05-18)

Sunshine ships a `/usr/local/bin/tailscale` shim that, when the GUI
helper isn't reachable, prints "The Tailscale CLI failed to start: The
operation couldn't be completed. (Tailscale.CLIError error 1.)" to
**stdout** with exit code **0** — looking exactly like a successful
"no Tailscale IP" response. `NetworkDiagnosticsManager` was accepting
the string as an address candidate, surfacing the error in the
dashboard.

Fix in [NetworkDiagnosticsManager.swift](src/MacStreamCore/Managers/NetworkDiagnosticsManager.swift):
the shim's output is now regex-validated against IPv4 / IPv6 patterns
before being accepted. Cache results for 60s to avoid burning shell
processes. The dashboard's "Endereços para Moonlight" row no longer
shows the false error.

### Kill the ghost Dock icon (2026-05-18)

User report: even with the dashboard closed, the Dock kept showing
"MacStream Host". Investigation revealed the icon wasn't a pinned
shortcut — it was a legitimate LaunchServices Dock entry owned by the
two background processes (`macstream-agent` + `MacStreamEngine`) that
share `Identifier=org.macstream.host` with the GUI bundle. Neither
helper called `setActivationPolicy(.accessory)` at boot, so macOS
grouped them under the parent bundle's Dock tile.

Three concurrent fixes — none alone is enough, because any process
claiming `.regular` policy under `org.macstream.host` keeps the Dock
entry alive.

- **`src/macstream-agent/main.swift`**: import AppKit and call
  `NSApplication.shared.setActivationPolicy(.accessory)` as the very
  first line of `main()`. The agent now disappears from the Dock and
  the AppSwitcher.
- **`scripts/embed_lsuielement.py`** (new): LIEF-based patcher that
  injects a `__TEXT,__info_plist` Mach-O section with
  `LSUIElement=true` and `CFBundleIdentifier=org.macstream.host`
  into the engine binary. Idempotent. Invoked by `package_dmg.sh`
  immediately after copying the engine into the bundle and before
  the final `codesign --sign` (which seals the new section).
  Requires `python3 -m pip install --user lief` on the build
  machine; degrades gracefully with a warning otherwise.
- **`src/MacStreamHostApp/MacStreamHostApp.swift`**:
  `MacStreamAppDelegate` now returns false from
  `applicationShouldTerminateAfterLastWindowClosed` (closing the
  dashboard no longer quits the tray app) and, when
  `startInBackground` is on, observes
  `NSWindow.willCloseNotification` to demote the activation policy
  back to `.accessory` after the last main window closes. So:
  tray → "Abrir dashboard" → policy promotes to `.regular`,
  Dock icon appears; close window → policy demotes to `.accessory`,
  Dock icon disappears.

Verification: `swift -e` enumerating `NSWorkspace.shared.runningApplications`
now reports `activationPolicy = .accessory` for both helpers. The CGWindowList
shows zero Dock tiles (layer 20) under any MacStream owner while the
dashboard is closed. 135/135 tests still pass; 29/29 runtime validation
still green.

### Tier 2: low-latency Sunshine profile (2026-05-17)

Optional `lowLatencyMode` toggle in `MacStreamHostSettings` (default
**off**, opt-in) that tweaks `sunshine.conf` for LAN-only setups:

- `fec_percentage = 0` (default is 20%) — saves video bitrate on
  reliable LAN links.
- `min_threads = 4` — Sunshine spins up encoder threads upfront
  instead of growing the pool lazily.
- `min_log_level = warning` to drop info-level chatter that competes
  with the encoder thread for CPU.

Wired through `ConfigurationManager.generateSunshineConfig(profile:)`
and a Settings toggle in the Advanced tab. Tests:
`ConfigurationManagerTests.testLowLatencyProfileWritesFecAndThreads`.

### Tier 1: background auto-start + tray-first UX (2026-05-17)

User requested a polish pass: server should start with the Mac and run
exclusively in the menu bar, no dashboard window opening at boot.

- **`startInBackground` setting (default off).** `MacStreamHostSettings`
  gained a Bool; when true and `loginItemEnabled` is also true, the
  agent boots, registers a `SMAppService.mainApp` login item, and the
  GUI launches with `setActivationPolicy(.accessory)` — no Dock tile,
  no auto-focused window. The dashboard opens on demand from the tray.
- **Complete tray menu.** `MenuBarContent.swift` now exposes every
  meaningful action from the dashboard: start/stop engine, pair
  device, lock/unlock host, open dashboard, quit. Status rows mirror
  the dashboard's health checks live.
- **Dashboard cleanup.** Removed the legacy "Iniciar agora" full-width
  banner that competed with the new tray-first flow. The dashboard
  itself now stays in tray context — closing the window doesn't quit
  the app; reopening from the tray re-promotes activation policy to
  `.regular` and the Dock icon reappears just for the duration of the
  visible window.

### Accessibility recovery + stable codesign identity (2026-05-17)

- **Stable self-signed identity:** `scripts/setup_local_codesign_identity.sh`
  rewritten to import the private key as DER PKCS#8 (the only format
  `security import` accepts as `-t priv`) and verify by actually
  signing a probe binary instead of relying on `find-identity`
  (self-signed certs don't surface there). `package_dmg.sh` now auto-
  resolves `MacStream Local Dev` and signs every binary in the bundle
  with it, so cdhash and the designated requirement stay stable across
  rebuilds — TCC grants survive `./scripts/package_dmg.sh` cycles.
- **Unified codesign identifier across the bundle:** `package_dmg.sh`
  now passes `--identifier "org.macstream.host"` to `macstream-agent`
  and `macstreamctl` (previously they took the codesign default
  `<basename>`). With `responsibility_spawnattrs_setdisclaim` in place,
  the engine's TCC checks are attributed to the agent's identifier — a
  single Accessibility entry for `MacStream Host.app` now covers the
  whole helper chain. Before this fix, keyboard and mouse forwarding
  from Moonlight failed silently because the agent had identifier
  `macstream-agent` and `AXIsProcessTrusted()` returned false.
- **`AccessibilityProbe` + `macstreamctl axprobe`:** new `axprobe`
  subcommand on `macstreamctl` calls `AXIsProcessTrusted()` and prints
  `AX_TRUSTED=true|false`. Used by `scripts/validate-runtime.sh`
  (section 8) for a definitive, identity-bound check.
- **HealthCheck + dashboard banner:** `HealthCheckID.sunshineAccessibility`
  added. `AppState.hasSunshineAccessibilityFailure` mirrors the existing
  Screen Recording flag. `AccessibilityRecoveryBanner` in
  `ContentView.swift` surfaces the issue with a one-click reset, deep
  link to System Settings, and engine restart button.
- **Live AX monitor:** `AppState.startLiveMonitors()` now polls
  `AXIsProcessTrusted()` every refresh tick and, on a `false → true`
  transition with the engine alive, automatically respawns the engine
  so Sunshine's cached trust check is re-evaluated.
- **GUI activation fix:** `MacStreamAppDelegate` was added to force
  `.regular` activation policy and `activate(ignoringOtherApps:)` on
  launch and reopen, so the dashboard window always comes to the front
  after macOS's "Quit & Reopen" TCC dialog.
- **`audio_sink` empty-string bug:** `ConfigurationManager` now omits
  the line entirely when no sink is configured. Sunshine's macOS audio
  module was reading the trailing space as a device name (`' '`),
  failing with `opening microphone ' ' failed`, and refusing to fall
  back to the Tap API. Defaults flipped to `.nativeSystemAudio`.

### BlackHole completely removed from installation (2026-05-16)

Sunshine `v2026.516+` captures system audio via the macOS Tap API on
macOS 14.2+, so we no longer ship the BlackHole virtual driver. This
removes the admin password prompt, the reboot requirement, and the
"Configurar roteamento de áudio" path from the dashboard entirely.

- **Bundle no longer contains `BlackHole2ch.pkg`.** `package_dmg.sh`
  no longer copies the .pkg into `Contents/Resources/dependencies/`.
  `Resources/dependencies/`, `scripts/fetch_blackhole.sh`, and
  `scripts/check-blackhole-installed.sh` were deleted from the repo.
- **`DependencyInstalling` protocol shrinks to Sunshine-only.** Removed
  `downloadAndOpenBlackHoleInstaller`, `embeddedBlackHoleInstallerURL`,
  and `installEmbeddedBlackHole`. The `PrivilegedInstaller` helper was
  deleted (no remaining consumer).
- **`DependencyManifest.defaultArtifacts()` returns only Sunshine.**
  `blackHoleArtifact()` factory was removed.
- **UI cleanup**: removed the "Configurar roteamento de áudio" button,
  `BlackHoleInstallExplainer` sheet, "Usar roteamento dedicado" toggle,
  and the audio-routing-to-BlackHole section of the Audio tab. The
  Settings picker for capture mode collapsed to a static "Tap API
  nativa" label.
- **Agent no longer warns about a missing BlackHole driver** when the
  user is on `audioCaptureMode = .blackHole2ch`. That mode still exists
  as an opt-in for users with an externally-installed BlackHole, but
  the install path is documented as "manual" rather than guided.

### Sunshine 2026.516.143833 + dashboard live monitors (2026-05-16)

- **Bumped the embedded engine to Sunshine `v2026.516.143833` (stable).**
  Previously pinned to the `v2026.508.45922` prerelease. The stable bump
  pulls in the security fix [`GHSA-ph75-mgxh-mv57`](https://github.com/LizardByte/Sunshine/security/advisories/GHSA-ph75-mgxh-mv57)
  plus the macOS Tap API audio capture path, mouse wheel + modifier
  input fixes, and the `adjust_thread_priority` / `set_thread_name`
  perf work. SHA-256 pins, `UPSTREAMS.md`, `fetch_sunshine.sh` and
  `DependencyManifest.sunshineArtifact` all updated.
- **Native macOS audio capture is now the default.** `MacStreamHostSettings`
  defaults to `audioCaptureMode = .nativeSystemAudio`, which leaves
  Sunshine's `audio_sink` blank and lets the engine route audio through
  the system Tap API on macOS 14.2+. BlackHole is demoted to an
  optional Multi-Output Device fallback — the dependency row, setup
  checklist and onboarding step no longer show yellow when the driver
  is missing in native mode.
- **Stable Sunshine identity (`sunshine_state.json`).** A new
  `SunshineIdentityStore` generates a persistent `uniqueid` once and
  mirrors it into `~/.config/sunshine/sunshine_state.json` before each
  engine boot, so Moonlight clients no longer see the host as a "new"
  computer after every restart. Reset-pairings flow available from
  the engine view.
- **Live CoreAudio + foreground refresh monitors.** `AudioDeviceMonitor`
  subscribes to `kAudioHardwarePropertyDevices`; `AppState.startLiveMonitors()`
  also drives a 5s foreground refresh. Status flips the moment a driver
  is added/removed without the user reopening the window.
- **Engine respawn supervisor.** The agent restarts the engine after
  unexpected death (rate-limited to 3 attempts / 60s) so post-sleep
  crashes don't take the dashboard down.


### Milestone: Moonlight streaming works end-to-end (2026-05-14)

First confirmed end-to-end Moonlight session from iPad: live video via
VideoToolbox, mouse + touchpad forwarding, keyboard input injection, and
host display dim that doesn't leak into the remote feed. Validated on
macOS 26.5.0 / Apple Silicon. Audio path is wired but not yet validated
from a remote client.

- **Flattened Sunshine into the parent bundle.** The streaming engine no
  longer ships as a nested `Sunshine.app`; the binary lives at
  `MacStream Host.app/Contents/MacOS/MacStreamEngine` alongside the host
  app, with its dylibs in `Contents/Frameworks/` and assets in
  `Contents/Resources/assets/`. Codesigned with `--identifier
  org.macstream.host` so macOS treats both binaries as parts of the
  same .app for TCC purposes. Eliminates the previous "two apps, two
  Screen Recording entries" model.
- **Branded the engine as "Motor MacStream" in user-facing surfaces.**
  Operation messages, banners, setup checklist, dependency rows, and
  the Moonlight pairing guide no longer expose the Sunshine name.
  BlackHole is presented as "Roteamento de áudio do MacStream".
  Internal names (`SunshineManager`, `sunshine.conf`, log files) are
  kept to match upstream.
- **Host lock no longer breaks the remote stream.** The floating unlock
  panel is now suppressed when a Moonlight session is active (it was
  leaking into the captured frame as a black rectangle and intercepting
  forwarded mouse events on macOS 26). Physical displays still dim via
  DisplayServices; the remote feed stays clean and the touchpad
  continues to work.
- **Host lock auto-releases on client disconnect.** A background watcher
  tails `~/.config/sunshine/sunshine.log` while the host is locked and
  dismisses the privacy overlay when it sees `CLIENT DISCONNECTED`
  after the lock activation. The auto-dismiss skips the password gate
  — there is no remote viewer left to protect against.
- **Extended `tccutil reset` to cover all three legacy bundle IDs**
  (`org.macstream.host`, `org.macstream.host.engine.sunshine`,
  `dev.lizardbyte.app.Sunshine`) so users upgrading from any previous
  layout get a clean grant flow.
- **Improved Accessibility hint:** the permission detail now explicitly
  tells the user that `MacStreamEngine` must be added separately to
  Privacy → Accessibility for keyboard injection to work — ad-hoc
  signing means the helper has a different cdhash than the parent and
  TCC keys grants per-cdhash.
- **`responsibility_spawnattrs_setdisclaim` shim added** so the engine
  inherits the parent's TCC identity for non-Screen-Recording checks
  (microphone, AppleEvents). Apple excludes Screen Recording from
  disclaim on macOS 14+, so this alone doesn't unify capture — the
  flatten above does.
- **`scripts/setup_local_codesign_identity.sh` (WIP, not yet working):**
  scaffolds a self-signed local identity for stable cdhash between
  builds; currently blocked because `security import` of the OpenSSL-
  generated PKCS#12 imports the cert but never pairs it with the
  private key. Header documents the next direction (Swift Security
  framework instead of PKCS#12).

### Regression tests

- `SunshineSessionTrackerTests` (7 cases): empty log, only-connect,
  disconnect-before-since, disconnect-after-since, reconnect-after-
  disconnect, malformed-line resilience, ignores-unrelated-lines.
- `StatusRuleTests.testRemoteWorkModeIsStreamingActive`: positive
  (running, degraded, starting) + negative (notReady, ready,
  stopping, blocked).
- `SunshineManagerTests.testResolverPrefersFlatHelperEngineOverEverything`
  + `testResolverFallsBackToLegacyInnerBundleWhenFlatHelperMissing`:
  resolver covers new layout AND in-place upgrade fallback.
- `AppStateTests.testResetSunshineScreenRecordingGrantInvokesTccutilForBothBundleIds`:
  all three bundle IDs are reset in order.

### Bug fix discovered during test extraction

- The first implementation of the host-lock auto-release used
  `ISO8601DateFormatter` with `.withSpaceBetweenDateAndTime` to parse
  Sunshine's `[2026-05-14 12:33:21.869]` timestamps, but the option is
  strict about which separator it accepts; combined with the code's
  `replacingOccurrences(of: " ", with: "T")` transformation the parser
  silently rejected every line and the watcher never fired. The
  extracted `SunshineSessionTracker` now uses a `DateFormatter` with an
  explicit pattern, fixing the auto-release in production.

## Previously

- Created initial SwiftPM foundation for the MVP.
- Added SwiftUI app shell and moved runtime flows to real local managers.
- Added core protocols, domain models, health checks, configuration validation, and unit tests.
- Added safe diagnostic scripts and development packaging.
- Added real safe `ConfigurationManager` for isolated Sunshine config and `apps.json` generation.
- Added safe Sunshine discovery/status for CLI diagnostics.
- Added safe Sunshine process ownership with CLI start/stop/restart that refuses external Sunshine processes.
- Wired the SwiftUI Sunshine screen to local diagnostics, isolated config generation, and owned process control.
- Added safe CoreAudio enumeration and BlackHole 2ch detection for CLI diagnostics.
- Added safe local network diagnostics for IP addresses, Sunshine ports, and Tailscale address detection.
- Added safe macOS permission diagnostics using public APIs where available.
- Added persistent runtime settings shared by app and CLI.
- Added safe LaunchAgent install/load/unload/remove for the current user without sudo.
- Added real log reading, `doctor --json`, and soft reset for MacStream Host owned state.
- Added `preflight` for real local test preparation and `support-bundle` export with best-effort sanitization.
- Added Sunshine runtime log diagnostics for Screen Recording and encoder/display failures.
- Removed an unrecognized Sunshine config option after local validation against Sunshine `2025.924.154138`.
- Added unsigned local `.app` bundling and optional development DMG script.
