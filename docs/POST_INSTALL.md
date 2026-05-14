# Post-install setup (manual TCC grants)

This document describes the manual steps every MacStream Host user has to
go through after installing or rebuilding the app. Once
`scripts/setup_local_codesign_identity.sh` works end-to-end (or the
project signs with a real Apple Developer ID), TCC grants will survive
rebuilds and most of this becomes one-time.

Until then, every `./scripts/package_dmg.sh` reissues the app with a new
ad-hoc `cdhash`, macOS invalidates the previous grants, and the steps
below have to be repeated.

## Why two binaries, two TCC entries

MacStream Host ships two related Mach-O binaries inside the same `.app`:

| Binary | Path | Role |
|---|---|---|
| `MacStream Host` | `/Applications/MacStream Host.app/Contents/MacOS/MacStream Host` | The SwiftUI app the user opens. |
| `MacStreamEngine` | `/Applications/MacStream Host.app/Contents/MacOS/MacStreamEngine` | The upstream Sunshine binary, renamed. Captures the screen, encodes, serves Moonlight. |
| `macstream-agent` | `/Applications/MacStream Host.app/Contents/MacOS/macstream-agent` | Resident user-LaunchAgent that holds power assertions and runs the privacy lock. |

All three are codesigned with the same identifier (`org.macstream.host`)
so macOS treats them as parts of the same product. **But** with ad-hoc
signing the TCC framework still keys grants per-`cdhash`, and each
binary has its own `cdhash`. The user has to add each binary that needs
a TCC category to the corresponding privacy list manually.

## Step 1 — Reset stale grants (only after a rebuild)

If MacStream Host was previously installed under a different layout,
clean the TCC database first:

```bash
tccutil reset ScreenCapture org.macstream.host
tccutil reset ScreenCapture org.macstream.host.engine.sunshine 2>/dev/null
tccutil reset ScreenCapture dev.lizardbyte.app.Sunshine 2>/dev/null
tccutil reset Accessibility org.macstream.host
```

The Dashboard exposes a button "Resetar permissão de Gravação de Tela"
that runs the first three commands.

## Step 2 — Grant Screen Recording

1. Open **System Settings → Privacy & Security → Gravação do Áudio do
   Sistema e da Tela** (or "Screen Recording" on older macOS).
2. Click the `+` button. Authenticate when prompted.
3. Press `⌘⇧G`, paste `/Applications/MacStream Host.app/Contents/MacOS`,
   press Return.
4. Select **`MacStream Host`** → Open. Toggle ON.
5. Click `+` again, repeat for **`MacStreamEngine`**. Toggle ON.

Both entries have to be ON. Sunshine reports `Error: No screen capture
permission!` in `~/.config/sunshine/sunshine.log` if either is missing.

## Step 3 — Grant Accessibility

Without Accessibility, the touchpad from Moonlight still works (mouse
events take a different routing path), but the keyboard does NOT — the
engine silently fails to inject `CGEventPost` keyboard events.

1. **System Settings → Privacy & Security → Acessibilidade**.
2. Click `+`, authenticate.
3. Add and toggle ON:
   - `MacStream Host`
   - `MacStreamEngine`
   - `macstream-agent`

All three are at
`/Applications/MacStream Host.app/Contents/MacOS/`.

## Step 4 — (Optional) Microphone

Only needed if the chosen audio capture mode reads from a real
microphone device (default is BlackHole 2ch which doesn't trigger the
microphone prompt).

System Settings → Privacy & Security → Microfone — add `MacStream Host`
and toggle ON.

## Step 5 — Start the engine

Open MacStream Host, click **Iniciar modo remoto** (or run
`/Applications/MacStream Host.app/Contents/MacOS/macstreamctl start`
from a terminal). Tail the log to confirm no permission errors:

```bash
tail -30 ~/.config/sunshine/sunshine.log
```

Expected:
- `Found H.264 encoder: h264_videotoolbox [videotoolbox]`
- `Found HEVC encoder: hevc_videotoolbox [videotoolbox]`
- No `Error: No screen capture permission!`
- No `Fatal: Unable to find display or encoder during startup`

## Step 6 — Pair Moonlight

1. Open https://localhost:47990 on the Mac in any browser. You'll see
   the engine's web panel (technically the upstream Sunshine web UI;
   MacStream Host treats it as an internal panel).
2. On the Moonlight client, add the Mac by IP (the Dashboard lists the
   addresses) and start the pairing flow.
3. Enter the PIN in the engine's web panel when Moonlight prompts.

## Audio path (BlackHole 2ch)

The Sunshine config has `audio_sink = BlackHole 2ch`. For audio to
actually leave the Mac:

1. The BlackHole 2ch driver must be installed (the Components tab of
   MacStream Host handles the install via the official `.pkg`).
2. **The system's default audio output must be set to BlackHole 2ch**,
   otherwise BlackHole captures silence. Today this is a manual step
   in Audio MIDI Setup; the project's `Etapa 2` adds an in-app button
   to flip the system output to BlackHole with one click.

After step 2, the user typically wants to hear local audio too. The
recommended setup is a *Multi-Output Device* in Audio MIDI Setup that
includes both BlackHole 2ch and the real speakers.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Moonlight shows "Failed to start streaming" | Screen Recording missing for `MacStreamEngine` | Re-do Step 2 |
| Touchpad works, keyboard does not | Accessibility missing for `MacStreamEngine` | Re-do Step 3 |
| `Error: No screen capture permission!` in sunshine.log after rebuild | New cdhash; previous grant invalidated | `tccutil reset` (Step 1) + Step 2 + Step 3 |
| Black strip across remote feed during host lock | Old build before the host-lock fix | Update to a build that contains `Suppress unlock panel during stream` |
| Host stays locked after disconnecting Moonlight | Old build before auto-release fix | Update to a build that contains `Extract SunshineSessionTracker` |
| Moonlight has video but no audio | System output not routed to BlackHole 2ch | Audio MIDI Setup → Output → BlackHole 2ch (or Multi-Output device including BlackHole) |
