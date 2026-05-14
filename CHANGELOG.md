# Changelog

All notable changes to MacStream Host will be documented here.

## Unreleased

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
