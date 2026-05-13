# GPL Compliance

MacStream Host is intended to be GPL-3.0-or-later software.

## Foundation Rules

- Keep source code, build scripts, packaging scripts, and release instructions public.
- Do not add proprietary dependencies without a license review.
- Do not add an EULA or restriction that conflicts with GPL rights.
- Preserve upstream notices and attribution.
- Document all bundled third-party binaries with exact refs and corresponding source.
- Re-staging is reproducible: `scripts/fetch_sunshine.sh` is the single entry point that fetches the pinned Sunshine DMG by SHA-256.

## Sunshine And BlackHole

Sunshine and BlackHole are independent GPL projects. MacStream Host carries them unmodified.

### Sunshine — bundled

The MacStream Host application bundle embeds the pinned upstream `Sunshine.app` at `Contents/Resources/sunshine/Sunshine.app`. To satisfy GPL-3.0 §6 we must, for any binary release that ships this bundle:

- Pin the exact upstream ref (release tag) and SHA-256 in `UPSTREAMS.md`.
- Link to the corresponding source — the upstream release page hosts both the DMG and the source tarball/tag.
- Ship the Sunshine license text inside the bundle (`Contents/Resources/sunshine/LICENSE` when present; the upstream LICENSE is also reproduced in the app About screen).
- Publish any local patches (currently: none).
- Provide the build script that reproduces the staging step (`scripts/fetch_sunshine.sh`).
- Update `THIRD_PARTY_NOTICES.md` whenever the pinned ref changes.

### BlackHole — guided install, not bundled

BlackHole is delivered via the upstream `.pkg` installer, opened from MacStream Host after SHA-256 verification. We do not bundle the kext/driver in the app bundle or DMG, so the standard rules in `UPSTREAMS.md` apply (pin the version, document the source, no modifications).

## Distribution Strategy

Open source distribution may include source releases, signed convenience builds, notarized DMGs, and paid support. Charging for convenience builds or support must not restrict recipients' GPL freedoms.

## App UI Requirement

The app should eventually include an About/Open Source Licenses screen that links to:

- GPL license text.
- Sunshine upstream.
- BlackHole upstream.
- Moonlight upstream.
- Local notices and bundled component versions.
