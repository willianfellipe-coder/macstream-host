# Post-install setup (manual TCC grants)

This document describes the manual steps every MacStream Host user has to
go through after installing the app **for the first time**.

Builds are signed by `scripts/setup_local_codesign_identity.sh` with the
locally-provisioned identity `MacStream Local Dev`, so the cdhash + cert
chain stay stable across rebuilds and the TCC grants below survive
`./scripts/package_dmg.sh` cycles. You only redo these steps after a
fresh keychain wipe or a cert rotation.

## Build dependency — LIEF (optional but recommended)

The build pipeline patches the engine's Mach-O header to embed
`LSUIElement=true`, suppressing the "ghost" Dock icon for the
background processes. Install once on the build machine:

```bash
python3 -m pip install --user lief
```

Without LIEF the build still succeeds — `package_dmg.sh` emits a
warning and the engine appears in the Dock until you install LIEF
and rebuild.

## Why one TCC entry covers the whole bundle

MacStream Host ships three Mach-O binaries inside the same `.app`:

| Binary | Path | Role |
|---|---|---|
| `MacStream Host` | `/Applications/MacStream Host.app/Contents/MacOS/MacStream Host` | The SwiftUI app the user opens. |
| `MacStreamEngine` | `/Applications/MacStream Host.app/Contents/MacOS/MacStreamEngine` | The upstream Sunshine binary, renamed. Captures the screen, encodes, serves Moonlight. |
| `macstream-agent` | `/Applications/MacStream Host.app/Contents/MacOS/macstream-agent` | Resident user-LaunchAgent that holds power assertions and runs the privacy lock. |

All three are codesigned with the same identifier (`org.macstream.host`)
**and** with the same authority (`MacStream Local Dev`). The agent
spawns the engine via `responsibility_spawnattrs_setdisclaim`, which
attributes the engine's TCC checks back to the agent. Because the
agent, engine and GUI share identity, granting `MacStream Host.app`
once in System Settings is enough to cover the whole chain — no need
to add each binary individually.

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

1. Open **System Settings → Privacy & Security → Screen Recording**
   (in pt-BR: "Gravação do Áudio do Sistema e da Tela").
2. Click the `+` button. Authenticate when prompted.
3. Navigate to `/Applications` and add **`MacStream Host`**. Toggle ON.
4. macOS will offer to "Quit & Reopen" — accept.

The single entry covers `MacStreamEngine` as well (shared codesign
identifier). If `~/.config/sunshine/sunshine.log` still shows
`Error: No screen capture permission!`, restart the engine via the
dashboard ("Reiniciar") — Sunshine caches the trust check at boot.

## Step 3 — Grant Accessibility

Without Accessibility, ALL keyboard and mouse forwarding from Moonlight
is silently dropped — the engine receives the events but `CGEventPost`
gets nowhere. The macOS log doesn't surface the denial, so the only
symptom is "vídeo + áudio funcionam, input não chega".

1. **System Settings → Privacy & Security → Accessibility**.
2. Click `+`, authenticate.
3. Navigate to `/Applications` and add **`MacStream Host`**. Toggle ON.

The dashboard probes `AXIsProcessTrusted()` via the embedded
`macstreamctl axprobe` and shows the `AccessibilityRecoveryBanner` if
the grant is missing. When you flip the toggle ON the live monitor
detects the transition and respawns the engine automatically so it
re-evaluates trust without a manual restart.

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

## Audio path (Tap API nativa do macOS)

A partir do Sunshine `v2026.516.143833`, o áudio do sistema é capturado
diretamente via Core Audio Tap API no macOS 14.2+. `sunshine.conf` é
emitido sem `audio_sink`, o engine cria um aggregate device com a Tap, e
o som do sistema flui pro Moonlight sem driver terceiro.

Na primeira sessão Moonlight ativa, o macOS exibe um prompt do tipo
"MacStream Host quer gravar áudio de outros apps" (System Audio
Recording, macOS 14.4+). Aceite — é a única confirmação manual.

Quem quiser ouvir local **e** transmitir ao mesmo tempo continua podendo
instalar BlackHole 2ch manualmente (não acompanha o app) e configurar
um Multi-Output Device em Audio MIDI Setup. Isso é opcional.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Moonlight shows "Failed to start streaming" | Screen Recording denied | Re-do Step 2, then restart the engine |
| Video and audio work, **neither keyboard nor mouse** reach the Mac | Accessibility denied for `org.macstream.host` | Re-do Step 3; the AccessibilityRecoveryBanner in the dashboard will surface this automatically |
| `Error: No screen capture permission!` in sunshine.log after rebuild | TCC grant was reset (rare with stable identity) | `tccutil reset` (Step 1) + Step 2 + restart the engine |
| Black strip across remote feed during host lock | Old build before the host-lock fix | Update to a build that contains `Suppress unlock panel during stream` |
| Host stays locked after disconnecting Moonlight | Old build before auto-release fix | Update to a build that contains `Extract SunshineSessionTracker` |
| Moonlight has video but no audio | macOS Tap API permission not granted (System Audio Recording, macOS 14.4+) | First Moonlight session triggers the prompt; accept it. If you missed it, the dashboard's audio card surfaces the warning. |
| Two cursors visible on iPad (iPad pointer **on top of** host cursor) | iPadOS renders its native trackpad/mouse pointer on top of every app — not a host bug. Sunshine has no knob to suppress the iPad's pointer. | Tap the screen once during the Moonlight session to enter "mouse capture mode": the iPad pointer hides and only the host cursor remains. Alternatively, in Moonlight iOS settings set **Touchscreen mode → Touchscreen as trackpad**. |
| Host display goes black during stream and Moonlight cursor freezes | Old build that ran gamma blackout on the streamed display (corrupted ScreenCaptureKit) | Update to a build that contains "Lock during streaming: dim the built-in via brightness, only ban gamma" — gamma is now forbidden on the streamed display while brightness paths (panel-only, SCK-safe) still run. |
| LG / external monitor stays bright when locking the host | Old build that only used `DisplayServicesSetBrightness` (no-op on externals) | Update to a build that contains "Multi-display lock via gamma blackout fallback" — externals dim via `CGSetDisplayTransferByFormula`. |
| Dashboard button stays "Bloquear host" even when lock is active | Old build before the dashboard toggle | Update to a build that contains "Dashboard 'Bloquear host' toggles to 'Desbloquear host' while locked". |
