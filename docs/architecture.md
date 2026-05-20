# Architecture

## Initial Review Summary

The reference documents define MacStream Host as a native macOS SwiftUI app that turns Sunshine, BlackHole, and Moonlight pairing into a productivity-focused remote work host. The current milestone is a functional MVP with a resident MacStream user agent, guided dependency installation, and safe local control while still avoiding bundled upstream binaries, private APIs, hidden privilege escalation, and unsafe network changes.

## Main Technical Requirements

- Native macOS app in Swift and SwiftUI.
- Target macOS 14.2+ with Apple Silicon as the initial priority.
- GPL-3.0-or-later compatible repository and release process.
- MacStream-first product surface: normal users operate Remote Work Mode, not separate upstream tools.
- Wrapper/orchestrator approach before any Sunshine or BlackHole fork.
- Isolated Sunshine configuration under `~/Library/Application Support/MacStreamHost/sunshine/`.
- BlackHole 2ch detected and installed only through explicit verified package flow.
- Safe diagnostics for permissions, audio, network, Sunshine status, logs, and pairing.
- Resident `macstream-agent` launched by user LaunchAgent `com.macstream.host.agent`, with explicit safety boundaries and no `sudo`.
- Native keep-awake power assertions during active remote work sessions.
- Secure host lock by default: local-only overlay with mandatory MacStream Keychain password fallback, optional Touch ID / macOS password unlock, and conservative refusal when no non-captured display can host the password panel.
- Web UI advanced access preserved; native pairing only after a stable API is validated.

## First Architecture Decisions

### SwiftPM With `src/`

The project uses Swift Package Manager with custom target paths under `src/`. This keeps builds simple with `swift build` and `swift test` while matching the requested repository layout.

### Core/App Split

`MacStreamCore` owns domain models, protocols, managers, settings, validation, diagnostics, app state, and health checks. `MacStreamHostApp` owns SwiftUI views. `macstreamctl` is the local development executable for doctor/config/start/stop/logs/reset/LaunchAgent workflows. `macstream-agent` is the resident user process that receives local commands, starts/stops only MacStream-owned engines, holds keep-awake assertions, handles optional privacy lock requests, and writes heartbeat/status JSON.

### Protocol-First Managers

The foundation defines protocols for:

- `PermissionManager`
- `DependencyInstallerManager`
- `SunshineManager`
- `BlackHoleManager`
- `AudioDeviceManager`
- `NetworkDiagnosticsManager`
- `LaunchAgentManager`
- `AgentManager`
- `RemoteWorkSessionManager`
- `ManagedEngineManager`
- `PowerAssertionManager`
- `HostPrivacyManager`
- `ConfigurationManager`
- `LogManager`
- `MoonlightPairingGuide`
- `HealthCheckService`

Runtime code does not depend on mocks. Test doubles live under `tests/`. The SwiftUI app and local CLI diagnostics use real engine discovery, CoreAudio/BlackHole detection, local network diagnostics, permission checks where macOS exposes public APIs, LaunchAgent status validation, and agent heartbeat files. Direct engine start/stop/restart remains available for compatibility, but the product path is Remote Work Mode through `macstream-agent`. Engine stop is implemented only for processes launched by MacStream Host and tracked through local ownership metadata.

### Dependency Installation Boundary

MacStream Host **ships the video engine inside the app bundle** as a nested accessory app at `Contents/Resources/sunshine/Sunshine.app`. The build pipeline (`scripts/fetch_sunshine.sh` + `scripts/package_dmg.sh`) pulls the pinned upstream Sunshine release, verifies its SHA-256, preserves or synthesizes a real `.app` wrapper, and re-signs the nested app plus MacStream helper tools. The engine never appears as a separate top-level app in `/Applications` and is not user-managed.

The nested app layout is intentional. A previous flat helper layout (`Contents/MacOS/MacStreamEngine`) combined with `responsibility_spawnattrs_setdisclaim` caused Sunshine to hang on macOS 26 during AVFoundation/VideoToolbox encoder probing before it opened Moonlight ports. `docs/SUNSHINE_ENGINE_RUNBOOK.md` documents the incident, evidence, validation checklist, and regression guards.

BlackHole is a CoreAudio driver, not a normal resident service, so MacStream Host still downloads and verifies the official `.pkg`, then opens Installer.app for explicit user/admin approval (this will be replaced by an embedded install with Authorization Services in a later phase). The app controls the resulting audio route through detection, settings, config generation, and validation. It does not perform hidden `sudo`, modify firewall settings, open ports, or control external Sunshine processes. It can install/load/unload/remove only its own user LaunchAgent.

### Bundle Layout

```
MacStream Host.app/Contents/
├── MacOS/
│   ├── MacStream Host       # SwiftUI app (the user-facing executable)
│   ├── macstream-agent      # Resident user-LaunchAgent helper
│   └── macstreamctl         # CLI helper (development / diagnostics)
└── Resources/
    └── sunshine/
        └── Sunshine.app/
            └── Contents/
                ├── MacOS/Sunshine
                ├── Frameworks/
                └── Resources/assets/
```

The parent app and MacStream-owned helper tools use the `org.macstream.host` identity. The nested Sunshine app uses `org.macstream.host.engine.sunshine` and must be granted Screen Recording separately when macOS requires it. See `docs/POST_INSTALL.md` for the user-facing permission flow.

### Resident Agent

The resident architecture is user-scoped:

- `LaunchAgentManager` writes `~/Library/LaunchAgents/com.macstream.host.agent.plist`.
- The plist launches `macstream-agent run`, not Sunshine directly.
- App/CLI write codable command files under `~/Library/Application Support/MacStreamHost/Agent/`.
- The agent reads commands, starts/stops only the owned video engine, activates/releases IOPM keep-awake assertions, handles host lock requests, and writes `status.json`.
- App/CLI read `status.json` for `RemoteWorkSessionReport` and surface user-facing Remote Work Mode state.

## Key Risks And Gaps

- Sunshine macOS support is still experimental and must be tested against pinned upstream versions.
- Pairing through Sunshine may not have a stable documented API.
- macOS permission status is not always readable through public APIs; practical tests will be needed.
- Audio capture may vary between native macOS capture and BlackHole routes.
- Packaging third-party GPL binaries requires exact source/build compliance.
- Sunshine managed install currently uses a prerelease macOS DMG because the latest stable release does not expose macOS DMG artifacts.
- Notarization and signing strategy must be decided before public binary releases.

## Current Foundation

Configuration generation is real and safe: it creates the isolated Sunshine config directory, writes default `sunshine.conf` and `apps.json`, skips existing files unless overwrite is requested, and backs up existing files before replacement. Runtime settings are persisted in `~/Library/Application Support/MacStreamHost/settings.json`.

Sunshine process control is intentionally narrow. `start` requires the isolated config to exist and refuses to launch if another Sunshine process is already running outside MacStream Host ownership. `stop` only sends `SIGTERM` to the recorded owned PID after validating that the current command line still matches the stored binary and config path. Ownership metadata is stored under `~/Library/Application Support/MacStreamHost/run/`.

Upgrade safety is part of this ownership model: if a stored owned process points to an old binary path but the resolver now points to the nested `Sunshine.app`, `start` terminates the stale owned process, clears metadata, and launches the current engine. `restart` also clears stale ownership mismatch before starting fresh. This prevents a broken legacy `MacStreamEngine` process from being reported as healthy after a package-layout fix.

The app does not kill or adopt an existing user-managed Sunshine process. The SwiftUI Sunshine screen calls the same safe manager methods through `AppState`, then refreshes diagnostics and publishes a user-visible operation message.

Secure host lock is coordinated in `AppState` and rendered by the app process, not by the video engine. `SecureLockReadiness` separates product decisions before locking: ready, missing MacStream password, no safe display during capture risk, or lockout. During capture risk, the streamed display gets no `NSWindow` because ScreenCaptureKit captures it even with `sharingType = .none`; MacStream dims that display through panel/backlight APIs and keeps a watchdog active while locked. The password panel and full-screen local shield render only on a non-streamed display. If no non-streamed display exists, lock is refused rather than risking a password prompt on the Moonlight capture target.

LaunchAgent support renders, validates, installs, loads, unloads, and removes only `com.macstream.host.agent` for the current user. It validates the MacStream agent executable and log directory before install/load. Audio diagnostics, network diagnostics, and permission diagnostics remain safe local checks.
