# Upstreams

MacStream Host must never depend on unpinned `latest` upstream binaries for reproducible releases.

## Sunshine

- Repository: https://github.com/LizardByte/Sunshine
- Version/ref validated locally for MVP smoke test: `2025.924.154138`, commit `86188d47a7463b0f73b35de18a628353adeaa20e`.
- Bundled release ref: `v2026.508.45922` (prerelease — see risk note).
- Source/release page: https://github.com/LizardByte/Sunshine/releases/tag/v2026.508.45922
- Apple Silicon artifact: `Sunshine-macOS-arm64.dmg`
- Apple Silicon SHA-256: `8b9819f2dafcfa430b00cc08b07aa61d0ad138998d68f369bfc210e07db3eb4b`
- Intel artifact: `Sunshine-macOS-x86_64.dmg`
- Intel SHA-256: `8d1518ef938e42d04fd013057aabdf2945d6a6dd12f053943d4d47f68d17089d`
- License: GPL-3.0
- Distribution: `Sunshine.app` is embedded inside the MacStream Host application bundle at `Contents/Resources/sunshine/Sunshine.app`, fetched and staged by `scripts/fetch_sunshine.sh` before packaging. The staged directory is git-ignored; only the pinned references above are tracked.
- Runtime fallback: if the embedded bundle is missing, `DefaultDependencyInstallerManager.installManagedSunshine` re-downloads the same pinned DMG (SHA-256 verified) into user Application Support.
- Modifications: none.
- Local validation notes: explicit config path is accepted by the CLI help contract; Web UI was reachable at `https://localhost:47990`; `origin_pin_allowed` is not recognized by this version and is not generated.
- Risk note: the macOS DMG target is currently a Sunshine prerelease because the latest stable GitHub release does not expose macOS DMG artifacts.

## BlackHole

- Repository: https://github.com/ExistentialAudio/BlackHole
- Version/ref: `v0.6.1`
- Installer artifact: `BlackHole2ch-0.6.1.pkg`
- Download URL: https://existential.audio/downloads/BlackHole2ch-0.6.1.pkg
- SHA-256: `c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988`
- License: GPL-3.0
- Local use planned for MVP: detected external BlackHole 2ch installation or guided package install opened through Installer.app after checksum verification.
- Modifications: none.

## Moonlight

- Repository: https://github.com/moonlight-stream
- Version/ref: not bundled.
- Local use planned for MVP: user-provided client.
- Modifications: none.
