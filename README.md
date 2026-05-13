# MacStream Host

MacStream Host is an experimental macOS application that aims to make Sunshine + BlackHole easier to use as a Moonlight-compatible streaming host.

The project is in the MVP implementation stage. The SwiftUI app and CLI use local safe diagnostics, persistent runtime settings, isolated Sunshine configuration, owned Sunshine process control, user LaunchAgent control, log export, and guided Moonlight pairing. It does not install BlackHole, change firewall settings, request `sudo`, or control user-managed Sunshine processes.

## Problem

Running a Mac as a Moonlight host today usually requires several separate steps: installing Sunshine, configuring audio capture, granting macOS permissions, checking network ports, opening the Sunshine Web UI, and pairing Moonlight manually. That workflow is powerful, but it is too technical for many users.

MacStream Host is intended to become a native macOS wrapper/orchestrator that turns that setup into a guided app experience.

## Goal

The goal is to let a user install the app, open it, understand missing permissions/dependencies, start or stop Sunshine, validate audio/video/network readiness, and pair with Moonlight with as little friction as possible.

The app is not a Moonlight client and does not replace Sunshine. It is a macOS-first layer around the existing open source ecosystem.

## Relationship To Upstream Projects

- Sunshine is the Moonlight-compatible host/server that performs streaming and pairing.
- BlackHole is the virtual audio driver used as a fallback route for system audio capture.
- Moonlight is the recommended client used from iPadOS, iOS, tvOS, Android, Windows, macOS, and other compatible platforms.

Sunshine, BlackHole, and Moonlight are independent projects. MacStream Host is not officially affiliated with their maintainers unless that changes in the future.

## Status

Current status: experimental MVP implementation.

Implemented now:

- Swift Package structure using Swift + SwiftUI.
- Runtime app/CLI managers use real local diagnostics; mocks live in tests only.
- Persistent runtime settings for Sunshine binary path, config directory, log directory, and audio mode.
- Safe Sunshine discovery/status, Web UI opening, and start/stop/restart using MacStream Host ownership metadata only.
- SwiftUI Sunshine screen wired to local diagnostics, isolated config generation, Web UI opening, and owned process control.
- Safe CoreAudio device enumeration and BlackHole 2ch detection for diagnostics.
- Safe local network diagnostics for IP addresses, Sunshine ports, and Tailscale address detection.
- Safe permission diagnostics for Screen Recording, Microphone, Accessibility, and guided Local Network validation.
- User LaunchAgent render/install/load/unload/remove without `sudo`, with plist and path validation.
- `doctor --json`, real log reading, and soft reset of MacStream Host owned state.
- Minimal unsigned development `.app` and optional DMG packaging script.
- Initial SwiftUI sidebar with Dashboard, Setup, Sunshine, Audio, Network, Moonlight, Diagnostics, and Settings.
- Domain models for Sunshine, BlackHole, permissions, audio, network, health checks, and streaming quality profiles.
- Unit tests for status rules, health checks, configuration validation, app state, settings, logs, LaunchAgent, reset, and test doubles.
- Safe diagnostic scripts that do not install, delete, request `sudo`, or modify system settings.
- GPL and third-party compliance documentation.

Not implemented yet:

- Controlling or adopting an existing user-managed Sunshine process.
- Automatic permission prompting or bypassing macOS privacy controls.
- Native Moonlight pairing through a Sunshine API.
- Driver installation.
- Signing, notarization, public release automation, or auto-update.

## System Requirements

Initial target:

- macOS 14.2 or newer.
- Apple Silicon first.
- Swift toolchain/Xcode command line tools for local development.

Intel Mac support is not promised yet and must be validated before it is documented as supported.

## macOS Permissions

The final app will need to guide the user through macOS privacy and networking permissions. Expected permissions include:

- Screen Recording for video capture.
- Microphone for some audio capture routes.
- Local Network for discovery and local connectivity.
- Accessibility when needed for input behavior.

MacStream Host does not bypass macOS permissions and does not use private Apple APIs.

## Sunshine On macOS

Sunshine support on macOS is still more limited than on some other platforms. Known limitations from the planning documents include experimental macOS support, possible permission friction, audio-route variability, and lack of current macOS host gamepad support in Sunshine. MacStream Host should communicate those limits honestly instead of promising unvalidated compatibility.

## License And Compliance

MacStream Host is licensed under GPL-3.0-or-later unless a file states otherwise.

This repository includes:

- `LICENSE` with the GNU GPL v3 license text.
- `NOTICE.md` for project notices.
- `THIRD_PARTY_NOTICES.md` for upstream credits.
- `UPSTREAMS.md` for pinned upstream versions once selected.
- `docs/gpl-compliance.md` with the release compliance strategy.

If future releases distribute Sunshine or BlackHole binaries, the exact upstream refs, corresponding source, build scripts, notices, and any modifications must be published.

## Repository Layout

This project uses Swift Package Manager with custom target paths under `src/` instead of the default `Sources/` directory. That keeps the repository aligned with the requested MVP layout while still allowing normal SwiftPM commands.

```text
Package.swift
src/
  MacStreamCore/
  MacStreamHostApp/
  macstreamctl/
tests/
scripts/
docs/
packaging/
Resources/templates/
```

## Run Locally

Build:

```bash
swift build
```

Run tests:

```bash
swift test
```

Run the CLI doctor:

```bash
swift run macstreamctl doctor
swift run macstreamctl doctor --json
```

The CLI doctor uses safe Sunshine discovery. It detects a `sunshine` binary, running process, Web UI reachability, audio devices, permission status where public APIs allow it, network ports, and LaunchAgent draft status.

Prepare the host for a real local Moonlight test:

```bash
swift run macstreamctl preflight
swift run macstreamctl preflight --start
```

`preflight` writes the isolated Sunshine config and `apps.json`, validates Sunshine, BlackHole, permissions, network, logs, and pairing readiness. `--start` starts only a Sunshine process owned by MacStream Host. If Sunshine logs a runtime blocker such as missing Screen Recording permission, `doctor` reports it as a failing runtime check.

Generate safe default Sunshine configuration:

```bash
swift run macstreamctl configure
```

By default this creates missing files under `~/Library/Application Support/MacStreamHost/sunshine/` and skips existing files. To replace existing files, use `--overwrite`; existing files are copied to timestamped `.backup-*` files first.

Start or stop Sunshine through MacStream Host ownership:

```bash
swift run macstreamctl start
swift run macstreamctl stop
swift run macstreamctl restart
```

These commands require the isolated Sunshine config to exist first. `start` refuses to run if another Sunshine process is already active outside MacStream Host ownership. `stop` only terminates the recorded owned process after validating that the PID still matches the recorded binary and config path.

Open the Sunshine Web UI:

```bash
swift run macstreamctl webui
```

Manage the user LaunchAgent:

```bash
swift run macstreamctl launchagent install
swift run macstreamctl launchagent load
swift run macstreamctl launchagent unload
swift run macstreamctl launchagent uninstall
```

Print recent logs or perform a soft reset of MacStream Host owned state:

```bash
swift run macstreamctl logs
swift run macstreamctl support-bundle
swift run macstreamctl reset --confirm
```

`support-bundle` exports sanitized diagnostics, logs, and the isolated Sunshine config to `~/Library/Logs/MacStreamHost/SupportBundles/` by default.

Run the SwiftUI app from SwiftPM:

```bash
swift run MacStreamHostApp
```

Run safe local diagnostics:

```bash
./scripts/check-environment.sh
./scripts/generate-diagnostics.sh
```

Create a local unsigned app bundle:

```bash
./scripts/package_dmg.sh
CREATE_DMG=1 ./scripts/package_dmg.sh
```

## Roadmap

1. Validate Sunshine launch arguments and Web UI behavior against a pinned upstream version.
2. Run the first end-to-end manual acceptance test with Moonlight on a real client.
3. Improve support bundle export into a user-selected zip from the SwiftUI app.
4. Add signed and notarized release automation once Developer ID is available.
5. Decide whether Intel Mac support is out of scope or only unvalidated.

## Contributing

Contributions are welcome while keeping the project GPL-compatible, conservative, and safe. See `CONTRIBUTING.md`.

Do not add telemetry, login, backend services, auto-update, privileged helpers, private Apple APIs, or automatic driver installation without an accepted design discussion and compliance review.
