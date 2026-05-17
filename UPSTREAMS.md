# Upstreams

MacStream Host must never depend on unpinned `latest` upstream binaries for reproducible releases.

## Sunshine

- Repository: https://github.com/LizardByte/Sunshine
- Version/ref validated locally for MVP smoke test: `2025.924.154138`, commit `86188d47a7463b0f73b35de18a628353adeaa20e`.
- Bundled release ref: `v2026.516.143833` (stable, published 2026-05-16).
- Source/release page: https://github.com/LizardByte/Sunshine/releases/tag/v2026.516.143833
- Apple Silicon artifact: `Sunshine-macOS-arm64.dmg`
- Apple Silicon SHA-256: `ab31ad716117b913c6aab104268e820595c0baf89b319fd3b75d34c9ae8ddd1e`
- Intel artifact: `Sunshine-macOS-x86_64.dmg`
- Intel SHA-256: `6b17c8d5a20cb2d2fa7c3bb9387d1412e63bb5c964d6820af91dea12f31a665f`
- License: GPL-3.0
- Distribution: only the helper binary, dynamic libraries and web/assets directory are extracted from the upstream `.app`; they get laid down inside MacStream Host's bundle at `Contents/MacOS/MacStreamEngine`, `Contents/Frameworks/` and `Contents/Resources/assets/` by `scripts/fetch_sunshine.sh` + `scripts/package_dmg.sh`. There is no nested `Sunshine.app` — that would give macOS a separate TCC identity Screen Recording cannot disclaim. The staged directory is git-ignored; only the pinned references above are tracked.
- Runtime fallback: if the embedded engine is missing, `DefaultDependencyInstallerManager.installManagedSunshine` re-downloads the same pinned DMG (SHA-256 verified) into user Application Support.
- Modifications: upstream code signatures are stripped and the helper is re-signed with `org.macstream.host` so it shares TCC identity with the parent bundle.
- Notable upstream changes since `v2026.508.45922` (prerelease) → `v2026.516.143833` (stable):
  - **Security**: CVE fix [`GHSA-ph75-mgxh-mv57`](https://github.com/LizardByte/Sunshine/security/advisories/GHSA-ph75-mgxh-mv57). Apply ASAP.
  - **CSRF**: new web-ui CSRF protection. Non-localhost access requires `csrf_allowed_origins` in `sunshine.conf` — MacStream Host only ever hits `https://localhost:47990`, so this is a no-op for us.
  - **macOS audio capture via Tap API** ([PR #4209](https://github.com/LizardByte/Sunshine/pull/4209)): native system-audio capture on macOS 14.2+ removes the hard dependency on BlackHole. Tracked as a UX simplification follow-up.
  - **macOS input fixes**: mouse wheel scroll ([#4592](https://github.com/LizardByte/Sunshine/pull/4592)), modifier state preservation ([#5102](https://github.com/LizardByte/Sunshine/pull/5102)), left/right modifier identity ([#5115](https://github.com/LizardByte/Sunshine/pull/5115)).
  - **macOS perf**: `adjust_thread_priority` + `set_thread_name` implementations ([#4605](https://github.com/LizardByte/Sunshine/pull/4605)).
  - **macOS packaging**: signed `.dmg` + `.app` bundle, Dock icon hidden, runtime tray icon paths ([#4759](https://github.com/LizardByte/Sunshine/pull/4759), [#4823](https://github.com/LizardByte/Sunshine/pull/4823), [#4711](https://github.com/LizardByte/Sunshine/pull/4711)). We re-sign as `org.macstream.host` regardless.
- Local validation notes: explicit config path is accepted by the CLI help contract; Web UI was reachable at `https://localhost:47990`; `origin_pin_allowed` is not recognized by this version and is not generated.

## BlackHole

- **Status (2026-05-16):** removed from the install path. Sunshine
  `v2026.516+` ships system-audio capture via the macOS Tap API
  (CoreAudio, macOS 14.2+), which makes the BlackHole driver
  unnecessary for streaming. MacStream Host no longer bundles
  `BlackHole2ch.pkg`, no longer fetches it, and no longer installs it.
- Users who still want a Multi-Output Device (e.g. to listen locally
  AND stream the same audio) can install the upstream driver from
  https://github.com/ExistentialAudio/BlackHole separately; the app
  detects the resulting CoreAudio device for diagnostics but does not
  push or manage it.
- License: GPL-3.0.

## Moonlight

- Repository: https://github.com/moonlight-stream
- Version/ref: not bundled.
- Local use planned for MVP: user-provided client.
- Modifications: none.
