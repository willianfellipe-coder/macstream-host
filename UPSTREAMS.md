# Upstreams

MacStream Host must never depend on unpinned `latest` upstream binaries for reproducible releases.

## Sunshine

- Repository: https://github.com/LizardByte/Sunshine
- Version/ref validated locally for MVP smoke test: `2025.924.154138`, commit `86188d47a7463b0f73b35de18a628353adeaa20e`.
- License: GPL-3.0
- Local use planned for MVP: detected or orchestrated external runtime; bundling decision still open.
- Modifications: none.
- Local validation notes: explicit config path is accepted by the CLI help contract; Web UI was reachable at `https://localhost:47990`; `origin_pin_allowed` is not recognized by this version and is not generated.

## BlackHole

- Repository: https://github.com/ExistentialAudio/BlackHole
- Version/ref: TBD
- License: GPL-3.0
- Local use planned for MVP: detected external BlackHole 2ch installation.
- Modifications: none.

## Moonlight

- Repository: https://github.com/moonlight-stream
- Version/ref: not bundled.
- Local use planned for MVP: user-provided client.
- Modifications: none.
