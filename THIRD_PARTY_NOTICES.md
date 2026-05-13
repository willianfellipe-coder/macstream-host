# Third-Party Notices

This file tracks third-party projects that MacStream Host integrates with, detects, documents, or may distribute in future releases.

## Sunshine

- Project: Sunshine
- Upstream: https://github.com/LizardByte/Sunshine
- Role: Moonlight-compatible host/server.
- License: GPL-3.0.
- Current MVP use: external install detection or managed user-scoped install from a pinned upstream macOS DMG. Sunshine is not bundled in the MacStream Host source tree or DMG.
- Managed install target: see `UPSTREAMS.md` for version, URL and checksum.
- Affiliation: independent upstream project; MacStream Host is not officially affiliated.

## BlackHole

- Project: BlackHole
- Upstream: https://github.com/ExistentialAudio/BlackHole
- Role: virtual audio loopback device for macOS.
- License: GPL-3.0.
- Current MVP use: external install detection or guided `.pkg` installation opened through Installer.app after checksum verification. The BlackHole driver is not bundled in the MacStream Host source tree or DMG.
- Managed install target: see `UPSTREAMS.md` for version, URL and checksum.
- Affiliation: independent upstream project; MacStream Host is not officially affiliated.

## Moonlight

- Project: Moonlight
- Upstream: https://github.com/moonlight-stream
- Role: recommended client ecosystem for connecting to Sunshine-compatible hosts.
- Current MVP use: documented pairing target only; no Moonlight client code is bundled.
- Affiliation: independent upstream project; MacStream Host is not officially affiliated.

## Release Requirement

Before any release that bundles third-party binaries, this file must be updated with exact versions, source references, licenses, modifications, and corresponding source/build instructions.
