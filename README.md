# MacStream Host

MacStream Host is an experimental macOS application that aims to make a Mac behave like a productivity-focused Moonlight-compatible remote work host.

The project is in the MVP implementation stage. The SwiftUI app and CLI use local safe diagnostics, persistent runtime settings, isolated engine configuration, owned process control, a resident user agent, log export, guided dependency installation, and guided Moonlight pairing. It does not change firewall settings, request hidden `sudo`, or control user-managed Sunshine processes.

## Problem

Running a Mac as a Moonlight host today usually requires several separate steps: installing Sunshine, configuring audio capture, granting macOS permissions, checking network ports, opening the Sunshine Web UI, and pairing Moonlight manually. That workflow is powerful, but it is too technical for many users.

MacStream Host is intended to become a native macOS remote work product that hides that complexity behind one guided app experience.

## Goal

The goal is to let a user install the app, open it, understand missing permissions/dependencies, start or stop Remote Work Mode, validate audio/video/network readiness, keep the Mac awake during a session, optionally lock the host screen for privacy, and pair with Moonlight with as little friction as possible.

The app is not a Moonlight client. Sunshine remains the streaming engine and BlackHole remains an independent CoreAudio driver, but the normal MacStream UI treats them as managed internal components rather than user-facing products.

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
- Resident `macstream-agent` target launched by user LaunchAgent `com.macstream.host.agent`.
- Remote Work Mode commands in app and CLI for prepare/start/stop/status/lock.
- macOS keep-awake power assertions while Remote Work Mode is active.
- Optional host privacy lock request using public macOS tooling.
- Safe Sunshine discovery/status, Web UI opening, and start/stop/restart using MacStream Host ownership metadata only.
- SwiftUI Sunshine screen wired to local diagnostics, isolated config generation, Web UI opening, and owned process control.
- SwiftUI operational dashboard with preflight CTA, first-run onboarding, dependency detection, Moonlight checklist, copyable pairing addresses, and support ZIP export.
- Integrated dependency installer for pinned upstream artifacts:
  - Sunshine macOS DMG is downloaded, SHA-256 verified, mounted, and copied into a user-scoped managed dependency directory.
  - BlackHole 2ch `.pkg` is downloaded, SHA-256 verified, and opened in Installer.app for explicit user/admin approval.
- Safe CoreAudio device enumeration and BlackHole 2ch detection for diagnostics.
- Safe local network diagnostics for IP addresses, Sunshine ports, and Tailscale address detection.
- Safe permission diagnostics for Screen Recording, Microphone, Accessibility, and guided Local Network validation.
- User LaunchAgent render/install/load/unload/remove without `sudo`, with plist and path validation.
- `doctor --json`, `doctor --strict`, real log reading, zipped support bundle export, and soft reset of MacStream Host owned state.
- Unsigned beta `.app` and optional drag-and-drop DMG packaging script with notices, build metadata, app icon, and SHA-256 checksum.
- SwiftUI sidebar with Remote Work, Setup, Components, Advanced Engines, Audio, Network, Moonlight, Diagnostics, and Settings.
- Domain models for Sunshine, BlackHole, permissions, audio, network, health checks, and streaming quality profiles.
- Unit tests for status rules, health checks, configuration validation, app state, settings, logs, LaunchAgent, reset, and test doubles.
- Safe diagnostic scripts that do not install, delete, request `sudo`, or modify system settings.
- GPL and third-party compliance documentation.

Not implemented yet:

- Controlling or adopting an existing user-managed Sunshine process.
- Automatic permission prompting or bypassing macOS privacy controls.
- Native Moonlight pairing through a Sunshine API.
- Driver installation.
- Privileged helper for full driver lifecycle management.
- Automatic host lock on session start before practical validation.
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

### Screen Recording for the embedded video engine

The video engine is the upstream `Sunshine.app` re-bundled under MacStream Host's identity namespace (`org.macstream.host.engine.sunshine`). `scripts/fetch_sunshine.sh` rewrites the bundle id and strips the upstream Developer ID signature so `scripts/package_dmg.sh` can re-seal the embedded app with the same ad-hoc identity as the wrapper. This is the only configuration macOS Tahoe (26+) reliably honors for TCC grants on apps inside other apps — keeping LizardByte's original Developer ID alongside our ad-hoc wrapper made Tahoe silently refuse to add the embedded engine to *Gravação do Áudio do Sistema e da Tela*.

On first run, grant Screen Recording **specifically to "MacStream Video Engine"** in *System Settings → Privacy & Security → Gravação do Áudio do Sistema e da Tela* (in older macOS this pane is called "Screen Recording"). The entry has to be added manually with the `+` button pointing at `/Applications/MacStream Host.app/Contents/Resources/sunshine/Sunshine.app`. Once the toggle is on, MacStream Host can drive the engine without any further prompts.

When the bundle is replaced (each `./scripts/package_dmg.sh` rebuild + reinstall) macOS may still revoke the grant. The Dashboard detects that state automatically and surfaces a red banner with two actions:

- **Resetar permissão do motor de vídeo** — runs `tccutil reset ScreenCapture org.macstream.host.engine.sunshine` (plus the legacy `dev.lizardbyte.app.Sunshine`) to clear zombie entries.
- **Abrir Ajustes de Gravação de Tela** — jumps straight to the right pane so the toggle can be flipped again.

After the Developer ID signing pass (release pipeline), grants persist across rebuilds and this manual recovery becomes unnecessary.

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

MacStream Host does not bundle Sunshine or BlackHole inside this repository or the MacStream Host DMG. The app downloads pinned upstream artifacts at install time and verifies SHA-256 before use. Exact upstream refs, URLs and checksums are tracked in `UPSTREAMS.md`.

If future releases bundle Sunshine or BlackHole binaries directly, the exact upstream refs, corresponding source, build scripts, notices, and any modifications must be published.

## Repository Layout

This project uses Swift Package Manager with custom target paths under `src/` instead of the default `Sources/` directory. That keeps the repository aligned with the requested MVP layout while still allowing normal SwiftPM commands.

```text
Package.swift
src/
  MacStreamCore/
  MacStreamHostApp/
  macstreamctl/
  macstream-agent/
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
swift run macstreamctl doctor --strict
```

The CLI doctor uses safe Sunshine discovery. It detects a `sunshine` binary, running process, Web UI reachability, audio devices, permission status where public APIs allow it, network ports, and LaunchAgent draft status.

Prepare the host for a real local Moonlight test:

```bash
swift run macstreamctl remote-work prepare
swift run macstreamctl remote-work start
swift run macstreamctl remote-work status
```

`remote-work prepare` writes the isolated engine config and installs the MacStream user agent. `remote-work start` asks the agent to start only MacStream-owned engines and activate keep-awake. If the video engine logs a runtime blocker such as missing Screen Recording permission, `doctor` reports it as a failing runtime check.

Manage the resident MacStream Agent:

```bash
swift run macstreamctl agent status
swift run macstreamctl agent install
swift run macstreamctl agent load
swift run macstreamctl agent unload
```

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

Manage the user LaunchAgent directly:

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
swift run macstreamctl support-bundle --zip
swift run macstreamctl reset --confirm
```

`support-bundle` exports sanitized diagnostics, logs, build metadata, and the isolated Sunshine config to `~/Library/Logs/MacStreamHost/SupportBundles/` by default.

Run the SwiftUI app from SwiftPM:

```bash
swift run MacStreamHostApp
```

Run safe local diagnostics:

```bash
./scripts/check-environment.sh
./scripts/generate-diagnostics.sh
```

Use integrated dependency installation from the app:

```bash
swift run MacStreamHostApp
```

Open **Components** and choose **Instalar dependências ausentes**. The video engine is installed into the current user’s MacStream Host application support directory. The audio driver opens the verified official `.pkg` in Installer.app and may require administrator approval and a reboot.

Create a local unsigned beta app bundle or DMG:

```bash
./scripts/package_dmg.sh
CREATE_DMG=1 ./scripts/package_dmg.sh
```

The DMG is unsigned until a Developer ID certificate is available. For a future signed release, configure the variables documented in `packaging/README.md` and run:

```bash
./scripts/sign_and_notarize.sh
```

## Roadmap

1. Validate Sunshine launch arguments and Web UI behavior against a pinned upstream version.
2. Validate `macstream-agent` across logout/login with Remote Work Mode start/stop.
3. Run the first end-to-end manual acceptance test with Moonlight on a real client from the unsigned DMG.
4. Capture beta feedback for permissions, audio route selection, host lock behavior, LaunchAgent persistence, and Gatekeeper unsigned flow.
5. Add signed and notarized release automation once Developer ID is available.

## Contributing

Contributions are welcome while keeping the project GPL-compatible, conservative, and safe. See `CONTRIBUTING.md`.

Do not add telemetry, login, backend services, auto-update, privileged helpers, private Apple APIs, or automatic driver installation without an accepted design discussion and compliance review.
