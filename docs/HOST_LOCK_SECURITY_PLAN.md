# Host lock security plan

This document records the agreed plan for the `develop` branch before
implementation work starts. The goal is to make host locking secure by
default without regressing Moonlight streaming.

## Branch policy

- `main` remains the stable milestone branch.
- `develop` is the permanent development branch, created from
  `main` at merge `349b3bd`.
- Host-lock implementation work happens on `develop`.
- `main` receives this work only after automated tests and manual
  Moonlight validation pass.

## Product decisions

- The main "Bloquear host" action should use secure lock by default.
- The legacy dim-only overlay remains available as an advanced fallback.
- Unlock should prefer Touch ID / macOS user password when available.
- A MacStream app password is still mandatory as a fallback and is stored
  separately in the macOS Keychain.
- The app never reads or stores the user's macOS login password; it only
  asks macOS to authenticate the local user through LocalAuthentication.

## First-lock flow

When the user clicks "Bloquear host" and no MacStream password exists:

1. Do not activate the overlay yet.
2. Show a local setup sheet in MacStream Host.
3. Require a non-empty password and matching confirmation.
4. Save the password in the Keychain.
5. Continue into secure lock immediately after a successful save.

If Touch ID / macOS password is available, it is offered during unlock,
but it does not remove the requirement for the MacStream fallback
password.

## Capture-safety rules

The remote Moonlight viewer must never see the lock UI, password field,
or secure overlay.

- Treat an active or potentially active Sunshine capture conservatively.
- Never create a password-panel `NSWindow` on the streamed display
  during capture risk.
- The streamed display must not receive any `NSWindow`, including
  `sharingType = .none` windows, because empirical Moonlight validation
  showed that ScreenCaptureKit still captures them.
- The streamed display uses only panel/backlight dimming plus an active
  watchdog that reapplies dimming while secure lock is enabled.
- Render the password panel only on a non-streamed physical display.
- If capture risk exists and there is no non-streamed physical display,
  refuse secure lock with a clear recovery message.
- Keep filtering synthetic Moonlight keyboard events from secure lock
  windows so the remote client cannot type into the local unlock panel.

## Implementation shape

- Add an explicit secure-lock readiness result in core so UI code can
  distinguish: ready, missing app password, no safe display, and lockout.
- Make secure overlay the default `HostPrivacyPolicy` mode for new
  settings.
- Keep backward-compatible settings decoding for existing installs.
- Update the dashboard and menu bar to route lock attempts through the
  secure readiness flow.
- Keep classic overlay dismissal separate from secure unlock; tray/menu
  actions must not bypass secure mode.
- Update `README.md`, `docs/POST_INSTALL.md`, and `docs/architecture.md`
  after implementation.

## Test matrix

Automated tests must cover:

- New default host lock mode is secure overlay.
- Legacy settings still decode safely.
- First lock without a MacStream password requests password setup and
  does not enter secure overlay.
- Touch ID / macOS authentication availability does not bypass fallback
  password setup.
- Saving the fallback password and continuing enters secure overlay.
- Touch ID / macOS authentication unlocks secure overlay.
- Correct MacStream password unlocks secure overlay.
- Wrong MacStream password increments attempts and enters temporal
  lockout at the configured threshold.
- Secure overlay refuses a single-display capture-risk scenario.
- Secure overlay allows a multi-display capture-risk scenario.
- Classic dismiss paths do not unlock secure overlay.

Manual QA must cover:

- One physical display plus active Moonlight: secure lock is refused with
  a clear message.
- Two physical displays plus active Moonlight: the streamed display is
  dimmed with watchdog and no window; the safe display gets the overlay
  and password panel.
- Moonlight continues to receive desktop video and input.
- Lock UI never appears in Moonlight.
- Remote keyboard input cannot type into the secure panel.
- Touch ID / macOS password unlock works locally.
- MacStream password unlock works locally.
- Moonlight disconnect auto-releases the local overlay.

## Final validation

Before merging back to `main`:

```bash
swift test
./scripts/package_dmg.sh
codesign --verify --deep --strict --verbose=2 .build/package/MacStream\ Host.app
```

The final gate is a manual Moonlight session proving that secure lock
does not leak the overlay or interrupt remote work.
