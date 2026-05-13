# Contributing

MacStream Host is early-stage GPL-3.0-or-later software. Contributions should prioritize safety, clarity, and compatibility with Sunshine, BlackHole, Moonlight, and macOS public APIs.

## Local Checks

Run before opening a pull request:

```bash
swift build
swift test
./scripts/check-environment.sh
```

## Guidelines

- Keep changes small and testable.
- Prefer Swift, SwiftUI, Foundation, and public macOS frameworks.
- Do not add proprietary dependencies.
- Do not add telemetry, login, backend services, or auto-update in the MVP.
- Do not request `sudo` or perform privileged operations without an accepted architecture document.
- Do not overwrite existing Sunshine configuration without backup logic and tests.
- Document technical uncertainty in `docs/OPEN_QUESTIONS.md`.

## Commit Sign-Off

This project expects Developer Certificate of Origin style sign-off:

```text
Signed-off-by: Name <email@example.com>
```
