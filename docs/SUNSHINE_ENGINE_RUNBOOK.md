# Sunshine engine runbook

This runbook records the 2026-05-19 MacStream Host regression where
Moonlight could discover and pair with the host, but the video engine
either never opened ports or failed at stream start. Keep it updated
whenever the embedded Sunshine layout, process ownership rules, TCC
identity, or packaging script changes.

## Root cause

The broken build flattened Sunshine into:

```text
MacStream Host.app/Contents/MacOS/MacStreamEngine
```

and launched it through `responsibility_spawnattrs_setdisclaim`. That
made the process appear to inherit some parent TCC behavior, but on
macOS 26 it could hang inside Sunshine's AVFoundation/VideoToolbox
dummy-frame probe before HTTP, HTTPS/nvhttp, Web UI, or RTSP sockets
opened.

Observed proof from the failing host:

- `MacStreamEngine` was alive, but `lsof -p <pid>` showed no listening
  Sunshine sockets.
- Sunshine stdout stopped after `Trying encoder [videotoolbox]` /
  `Creating encoder [h264_videotoolbox]`.
- `sample <pid>` showed the main thread stuck below
  `video::probe_encoders()`, `video::validate_encoder(...)`, and
  `platf::av_display_t::dummy_img(...)`.
- Moonlight could not connect because there was no server port to
  connect to. This was not a LAN, firewall, or client-network issue.

The fixed layout restores a real nested app bundle:

```text
MacStream Host.app/Contents/Resources/sunshine/Sunshine.app/Contents/MacOS/Sunshine
```

The nested app has its own stable bundle identity:

```text
org.macstream.host.engine.sunshine
```

LaunchServices, TCC, AVFoundation, ScreenCaptureKit, and VideoToolbox
now see a normal app-bundle context instead of a bare helper binary.

## Non-negotiable regression guards

Do not reintroduce the flat engine as the preferred runtime path.

`DefaultSunshineBinaryResolver` must prefer:

```text
/Applications/MacStream Host.app/Contents/Resources/sunshine/Sunshine.app/Contents/MacOS/Sunshine
```

before any legacy fallback such as:

```text
/Applications/MacStream Host.app/Contents/MacOS/MacStreamEngine
```

The legacy path may remain as a fallback for old bundles only. If both
paths exist, the nested `Sunshine.app` must win.

Do not reintroduce `responsibility_spawnattrs_setdisclaim`. Sunshine
must be launched with normal `Process()` semantics so the executable
and bundle identity match the nested app that macOS authorizes.

Ownership matching must compare the actual resolved binary path. A
running process that points at the same config file but uses the legacy
`MacStreamEngine` path is not a valid owned process when the resolver
currently points at `Sunshine.app`.

`start()` must replace an owned process when the resolved binary path
changes. This handles upgrades from the broken flat-helper build where
`sunshine-owned-process.json` still points to the old PID/path.

`status()` must not report a process as fully healthy when Web UI is
not reachable. A running process with closed Web UI is degraded and
should send investigators to logs/process state before network.

## Required packaging behavior

`scripts/package_dmg.sh` must produce:

```text
MacStream Host.app/Contents/Resources/sunshine/Sunshine.app
```

The nested app must include:

- `CFBundleExecutable = Sunshine`
- `CFBundleIdentifier = org.macstream.host.engine.sunshine`
- `CFBundleName = MacStream Video Engine`
- `LSUIElement = true`
- screen/audio/microphone/local-network usage strings

The installed app should not contain:

```text
MacStream Host.app/Contents/MacOS/MacStreamEngine
```

Check:

```bash
/Applications/MacStream\ Host.app/Contents/MacOS/macstreamctl paths
test ! -e /Applications/MacStream\ Host.app/Contents/MacOS/MacStreamEngine
codesign --verify --deep --strict --verbose=2 /Applications/MacStream\ Host.app
plutil -p /Applications/MacStream\ Host.app/Contents/Resources/sunshine/Sunshine.app/Contents/Info.plist
```

Expected `macstreamctl paths` line:

```text
Sunshine binary: /Applications/MacStream Host.app/Contents/Resources/sunshine/Sunshine.app/Contents/MacOS/Sunshine
```

## Required macOS permissions

After a clean install or identity change, grant Screen Recording to:

- `MacStream Host`
- `MacStream Video Engine` / `Sunshine.app`

Grant Accessibility to:

- `MacStream Host`
- `MacStream Video Engine` if keyboard or mouse injection fails

The relevant paths are:

```text
/Applications/MacStream Host.app
/Applications/MacStream Host.app/Contents/Resources/sunshine/Sunshine.app
```

If a permission was granted while Sunshine was already running, restart
the engine:

```bash
/Applications/MacStream\ Host.app/Contents/MacOS/macstreamctl restart
```

Sunshine may cache capture/encoder trust state at startup.

## Connection-state diagnosis

Moonlight shows the host with a lock:

- Discovery works.
- Network is not the blocker.
- The host is not paired yet.
- Pair through Sunshine Web UI at `https://localhost:47990`.

Moonlight pairs, then shows:

```text
Failed to initialize video capture/encoding. Is a display connected and turned on?
```

This is the capture/encoder stage. Check, in order:

1. `org.macstream.host.engine.sunshine` has Screen Recording permission.
2. Sunshine was restarted after that grant.
3. At least one active display is visible to CoreGraphics.
4. The power policy keeps the display awake for headless/remote tests.
5. Sunshine logs do not report `Unable to find display or encoder during startup`.

CoreGraphics display probe:

```bash
swift -e 'import CoreGraphics; var count: UInt32 = 0; let r1 = CGGetActiveDisplayList(0, nil, &count); print("result", r1.rawValue, "count", count); var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(count, 1))); var actual: UInt32 = 0; let r2 = CGGetActiveDisplayList(UInt32(ids.count), &ids, &actual); print("result2", r2.rawValue, "actual", actual); for id in ids.prefix(Int(actual)) { print("display", id, "online", CGDisplayIsOnline(id), "active", CGDisplayIsActive(id), "builtin", CGDisplayIsBuiltin(id), "w", CGDisplayPixelsWide(id), "h", CGDisplayPixelsHigh(id)) }'
```

Power assertion check:

```bash
pmset -g assertions
```

For hosts that may run with displays sleeping, prefer a policy where
`keepDisplayAwake = true`; otherwise `PreventUserIdleDisplaySleep` may
remain `0` even while `PreventUserIdleSystemSleep` is active.

## Runtime validation checklist

After packaging and installing:

```bash
/Applications/MacStream\ Host.app/Contents/MacOS/macstreamctl restart
/Applications/MacStream\ Host.app/Contents/MacOS/macstreamctl status --json
pgrep -fl Sunshine
/usr/sbin/lsof -nP -iTCP:47984 -sTCP:LISTEN
/usr/sbin/lsof -nP -iTCP:47989 -sTCP:LISTEN
/usr/sbin/lsof -nP -iTCP:47990 -sTCP:LISTEN
/usr/sbin/lsof -nP -iTCP:48010 -sTCP:LISTEN
```

Expected:

- `sunshineStatus.state = running`
- `webUIReachable = true`
- `ownedProcessID` belongs to `.../Resources/sunshine/Sunshine.app/...`
- `pgrep -fl Sunshine` shows `Sunshine`, not `MacStreamEngine`
- TCP `47984`, `47989`, `47990`, and `48010` listen locally
- Moonlight discovers the host
- Moonlight pairs through PIN
- Moonlight starts a stream without capture/encoder error

## Test coverage that must remain

`SunshineManagerTests` must cover:

- Resolver prefers embedded `Sunshine.app` over flat helper.
- Resolver falls back to flat helper only when embedded app is missing.
- `start()` replaces a stale owned process when the resolved binary path changes.
- `restart()` clears ownership mismatch and starts fresh.
- Process ownership rejects legacy `MacStreamEngine` when embedded
  `Sunshine.app` is expected.
- Running process with unreachable Web UI reports degraded status.

Run:

```bash
swift test --filter SunshineManagerTests
```

Before publishing a fix, also run:

```bash
git diff --check
./scripts/package_dmg.sh
codesign --verify --deep --strict --verbose=2 .build/package/MacStream\ Host.app
```

Full `swift test` may still have environment-sensitive TCC assertions
on developer machines. Record those explicitly if they are unrelated
to the Sunshine engine path.
