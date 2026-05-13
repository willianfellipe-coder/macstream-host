# Open Questions

These questions must be resolved before implementing deeper integrations or public releases.

## Upstream Versioning

- Current local smoke target: Sunshine `2025.924.154138`, commit `86188d47a7463b0f73b35de18a628353adeaa20e`. Confirm whether this should become the first public MVP target or whether a tagged release should be selected instead.
- Managed installer target for Sunshine currently uses prerelease `v2026.508.45922` because it provides macOS DMG artifacts. Should the first public beta accept that prerelease, wait for a stable macOS DMG release, or keep Homebrew as the preferred stable Sunshine path?
- Managed installer target for BlackHole is `v0.6.1` / `BlackHole2ch-0.6.1.pkg`; validate on a clean macOS machine and document reboot behavior.
- Decision for this MVP: detect external Sunshine and BlackHole installs; do not bundle either upstream binary.
- Decision for this installer milestone: download pinned upstream artifacts at runtime, verify SHA-256, install Sunshine into a user-scoped managed directory, and open the BlackHole package through Installer.app for explicit approval.

## Sunshine Integration

- Local validation showed Sunshine accepts `/path/to/configuration_file` as a CLI positional argument. Confirm this against upstream docs before public release.
- Local validation showed `https://localhost:47990` reachable for Sunshine `2025.924.154138`; confirm whether this remains stable across the selected public MVP target.
- Decision for this MVP: Web UI guidance is the pairing path; native API pairing remains out of scope until validated.
- What authentication and certificate behavior should the app expect from Sunshine's local Web UI?
- Local smoke test showed Web UI requests from `127.0.0.1` as not authorized until the user completes Sunshine Web UI authentication.
- How should MacStream Host avoid conflicts with an existing user-managed Sunshine installation?
- Current MVP policy refuses to start when any external Sunshine process is running and refuses to stop anything it did not launch. Should future versions offer a guided migration/adoption flow, or keep external Sunshine completely separate?

## Audio

- On macOS 14.2+, how reliable is Sunshine native system audio capture with `audio_sink` left blank?
- Under what conditions is BlackHole 2ch still required?
- Which public APIs should be used to enumerate CoreAudio devices and detect BlackHole reliably?
- Can a Multi-Output Device be created safely through public APIs, or must the MVP only guide the user?
- How should the app communicate known macOS volume limitations with Multi-Output Devices?

## Permissions

- Current implementation reads Screen Recording via `CGPreflightScreenCaptureAccess`, Microphone via `AVCaptureDevice.authorizationStatus`, and Accessibility via `AXIsProcessTrustedWithOptions`. Local Network remains practical-validation only because macOS does not expose a direct reliable status API.
- What is the least surprising flow for Screen Recording and Microphone prompts?
- Local smoke test confirmed Sunshine can start and expose Web UI while still failing video runtime with `No screen capture permission`; the app/CLI now surfaces this as a failing runtime diagnostic.
- Does Sunshine itself need Accessibility in the target MVP scenarios, or should it remain optional?
- How should Local Network permission be triggered and validated without creating confusing prompts?

## LaunchAgent And Login

- Decision for this MVP: use a plain user LaunchAgent and `launchctl bootstrap/bootout gui/<uid>` without sudo.
- Should a later packaged app migrate from LaunchAgent to `SMAppService`, or keep LaunchAgent for transparency?

## Packaging And Distribution

- Is there an Apple Developer ID available for signing and notarization?
- Decision for this beta milestone: ship a controlled unsigned DMG for manual testers only. Public distribution remains blocked until Developer ID signing and notarization are available.
- What release process will publish corresponding source when third-party GPL binaries are bundled?
- Should the project generate an SBOM during packaging?
- Should the placeholder-generated app icon be replaced with a committed designer-provided `.icns` before wider beta distribution?

## Platform Scope

- Is Intel Mac support explicitly out of scope for the MVP or only unvalidated?
- Which macOS versions beyond 14.2 should be tested before the first beta?
- What real Moonlight clients are required for acceptance testing: iPadOS, Apple TV, macOS, Windows?

## Network And Remote Access

- Should Tailscale integration stay documentation-only in MVP, or should the CLI detect `tailscale ip`?
- Which Sunshine port matrix should be treated as canonical for the pinned upstream version?
- How should the app warn about port forwarding without encouraging unsafe public exposure?
