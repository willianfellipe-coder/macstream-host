# Changelog

All notable changes to MacStream Host will be documented here.

## Unreleased

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
