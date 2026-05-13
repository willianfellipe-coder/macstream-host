# Packaging Plan

Packaging currently supports a local unsigned development `.app` bundle and optional unsigned DMG.

```bash
./scripts/package_dmg.sh
CREATE_DMG=1 ./scripts/package_dmg.sh
```

The generated artifacts are written under `.build/package/`.

## Development DMG

`CREATE_DMG=1 ./scripts/package_dmg.sh` creates a simple unsigned DMG containing `MacStream Host.app`. This is for local testing only.

## Signing

Public binary releases should be signed with Apple Developer ID Application. Signing identity and CI secret handling are still TBD.

## Notarization

Public DMGs should be submitted through `xcrun notarytool` and stapled after approval. This requires an Apple Developer account and release automation.

## Open Source Distribution

Every binary release must include source availability, license notices, checksums, release notes, and reproducible build instructions.

## Upstream Binaries

Bundling Sunshine or BlackHole directly increases compliance and release risk. If bundled, the release must include exact upstream refs, corresponding source, build scripts, notices, and any patches.

## Initial Dependency Strategy

For the MVP, MacStream Host detects external Sunshine and BlackHole installations and guides the user. It does not bundle Sunshine or BlackHole binaries, silently install drivers, or distribute upstream binaries before compliance, signing, and notarization are ready.

## Not In Scope Yet

- Sparkle or any auto-update mechanism.
- Installer package for BlackHole.
- Privileged helper packaging.
- Signed and notarized release automation.
