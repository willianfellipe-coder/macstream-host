# Packaging Plan

Packaging currently supports a reproducible unsigned beta `.app` bundle and optional drag-and-drop DMG.

```bash
./scripts/package_dmg.sh
CREATE_DMG=1 ./scripts/package_dmg.sh
```

The generated artifacts are written under `.build/package/`.

## Beta DMG

`CREATE_DMG=1 ./scripts/package_dmg.sh` creates an unsigned DMG containing:

- `MacStream Host.app`
- an `Applications` symlink for drag-and-drop installation
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `UPSTREAMS.md`
- a SHA-256 checksum beside the DMG

The app bundle includes `Info.plist`, `AppIcon.icns`, build metadata, and bundled license/notices resources. The version is read from `VERSION`; build number can be overridden with `BUILD_NUMBER=`.

This unsigned DMG is for controlled beta testing only. Users will see Gatekeeper warnings because the app is not Developer ID signed or notarized.

## Signing

Public binary releases should be signed with Apple Developer ID Application:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)" \
NOTARYTOOL_PROFILE="macstream-notary" \
./scripts/sign_and_notarize.sh
```

The script fails early when Developer ID or notarytool credentials are missing. The current entitlements file is intentionally minimal and should stay conservative until a specific runtime need is proven.

## Notarization

Public DMGs should be submitted through `xcrun notarytool` and stapled after approval. This requires an Apple Developer account. Supported credential options:

- `NOTARYTOOL_PROFILE`
- or `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`

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
