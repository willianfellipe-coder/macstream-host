# GPL Compliance

MacStream Host is intended to be GPL-3.0-or-later software.

## Foundation Rules

- Keep source code, build scripts, packaging scripts, and release instructions public.
- Do not add proprietary dependencies without a license review.
- Do not add an EULA or restriction that conflicts with GPL rights.
- Preserve upstream notices and attribution.
- Document all bundled third-party binaries with exact refs and corresponding source.

## Sunshine And BlackHole

Sunshine and BlackHole are independent GPL projects. The safest MVP path is to detect or orchestrate official upstream builds without modifying them.

If future releases bundle Sunshine or BlackHole binaries:

- Pin exact upstream refs in `UPSTREAMS.md`.
- Include or link corresponding source for the exact binary.
- Publish all local patches.
- Include build scripts sufficient to reproduce the bundled binary.
- Update `THIRD_PARTY_NOTICES.md`.
- Include license text and copyright notices in the app and release artifact.

## Distribution Strategy

Open source distribution may include source releases, signed convenience builds, notarized DMGs, and paid support. Charging for convenience builds or support must not restrict recipients' GPL freedoms.

## App UI Requirement

The app should eventually include an About/Open Source Licenses screen that links to:

- GPL license text.
- Sunshine upstream.
- BlackHole upstream.
- Moonlight upstream.
- Local notices and bundled component versions.
