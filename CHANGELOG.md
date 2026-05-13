# Changelog

All notable changes to MacStream Host will be documented here.

## Unreleased

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
