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
- Optional host lock request for privacy, gated behind user action until end-to-end validation proves it does not break streaming.
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

MacStream Host now **ships the video engine inside the app bundle** as a renamed Mach-O helper (`MacStreamEngine`) at `Contents/MacOS/`, along with its dynamic libraries (`Contents/Frameworks/`) and assets (`Contents/Resources/assets/`). The build pipeline (`scripts/fetch_sunshine.sh` + `scripts/package_dmg.sh`) pulls the pinned upstream Sunshine release, verifies its SHA-256, strips the upstream signature, and re-signs every component with our own identity (`Identifier=org.macstream.host`) so the engine binary is treated as part of the host app for TCC purposes. The engine never appears as a separate `.app` in `/Applications` and is not user-managed.

BlackHole is a CoreAudio driver, not a normal resident service, so MacStream Host still downloads and verifies the official `.pkg`, then opens Installer.app for explicit user/admin approval (this will be replaced by an embedded install with Authorization Services in a later phase). The app controls the resulting audio route through detection, settings, config generation, and validation. It does not perform hidden `sudo`, modify firewall settings, open ports, or control external Sunshine processes. It can install/load/unload/remove only its own user LaunchAgent.

### Bundle Layout

```
MacStream Host.app/Contents/
├── MacOS/
│   ├── MacStream Host       # SwiftUI app (the user-facing executable)
│   ├── MacStreamEngine      # Renamed Sunshine binary (sibling of the app)
│   ├── macstream-agent      # Resident user-LaunchAgent helper
│   └── macstreamctl         # CLI helper (development / diagnostics)
├── Frameworks/
│   ├── libcrypto.3.dylib    # Sunshine deps, signed under same identity
│   ├── libssl.3.dylib
│   └── libminiupnpc.21.dylib
└── Resources/
    └── assets/              # Sunshine web panel assets (apps.json, web/)
```

All four binaries are codesigned with `--identifier org.macstream.host`, with the parent app signed *without* `--deep` so the helper's explicit identifier survives the parent's seal. With ad-hoc signing each binary still has its own `cdhash`, so TCC keys grants per-binary and the user has to add each binary that needs a category (Screen Recording, Accessibility) to the corresponding privacy list manually until a stable code-signing chain (Apple Developer ID or persistent self-signed identity) is in place. See `docs/POST_INSTALL.md` for the user-facing dance.

### Resident Agent

The resident architecture is user-scoped:

- `LaunchAgentManager` writes `~/Library/LaunchAgents/com.macstream.host.agent.plist`.
- The plist launches `macstream-agent run`, not Sunshine directly.
- App/CLI write codable command files under `~/Library/Application Support/MacStreamHost/Agent/`.
- The agent reads commands, starts/stops only the owned video engine, activates/releases IOPM keep-awake assertions, handles optional host lock requests, and writes `status.json`.
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

Sunshine process control is intentionally narrow. `start` requires the isolated config to exist and refuses to launch if another Sunshine process is already running outside MacStream Host ownership. `stop` only sends `SIGTERM` to the recorded owned PID after validating that the current command line still matches the stored binary and config path. Ownership metadata is stored under `~/Library/Application Support/MacStreamHost/run/`. The app does not kill or adopt an existing user-managed Sunshine process. The SwiftUI Sunshine screen calls the same safe manager methods through `AppState`, then refreshes diagnostics and publishes a user-visible operation message.

LaunchAgent support renders, validates, installs, loads, unloads, and removes only `com.macstream.host.agent` for the current user. It validates the MacStream agent executable and log directory before install/load. Audio diagnostics, network diagnostics, and permission diagnostics remain safe local checks.
