# Source Layout

SwiftPM normally uses `Sources/`, but this repository intentionally uses `src/` as the target root to match the requested MVP structure.

Targets:

- `MacStreamCore`: shared models, protocols, managers, validation, settings, diagnostics, and app state.
- `MacStreamHostApp`: SwiftUI app shell.
- `macstreamctl`: CLI for diagnostics, configuration, Sunshine process control, LaunchAgent control, logs, and reset.
