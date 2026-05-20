# Post-install setup (manual TCC grants)

This document describes the manual steps every MacStream Host user has to
go through after installing the app **for the first time**.

Builds are signed by `scripts/setup_local_codesign_identity.sh` with the
locally-provisioned identity `MacStream Local Dev`, so the cdhash + cert
chain stay stable across rebuilds and the TCC grants below survive
`./scripts/package_dmg.sh` cycles. You only redo these steps after a
fresh keychain wipe or a cert rotation.

## Runtime bundle identities

MacStream Host ships its own executables plus the embedded Sunshine
engine inside the same top-level `.app`:

| Binary | Path | Role |
|---|---|---|
| `MacStream Host` | `/Applications/MacStream Host.app/Contents/MacOS/MacStream Host` | The SwiftUI app the user opens. |
| `macstream-agent` | `/Applications/MacStream Host.app/Contents/MacOS/macstream-agent` | Resident user-LaunchAgent that holds power assertions and runs the privacy lock. |
| `MacStream Video Engine` / `Sunshine.app` | `/Applications/MacStream Host.app/Contents/Resources/sunshine/Sunshine.app` | The upstream Sunshine engine. Captures the screen, encodes, serves Moonlight. |

The Sunshine engine must remain a real nested `.app` bundle. A previous
flat helper layout at `Contents/MacOS/MacStreamEngine` caused Sunshine
to hang during macOS AVFoundation/VideoToolbox encoder probing before
opening Moonlight ports. See `docs/SUNSHINE_ENGINE_RUNBOOK.md` before
changing the engine layout.

The nested engine bundle identifier is:

```text
org.macstream.host.engine.sunshine
```

macOS TCC grants must cover both the user-facing app and the nested
engine where the capture or input API is called.

## Step 1 — Reset stale grants (only after a rebuild)

If MacStream Host was previously installed under a different layout,
clean the TCC database first:

```bash
tccutil reset ScreenCapture org.macstream.host
tccutil reset ScreenCapture org.macstream.host.engine.sunshine 2>/dev/null
tccutil reset ScreenCapture dev.lizardbyte.app.Sunshine 2>/dev/null
tccutil reset Accessibility org.macstream.host
tccutil reset Accessibility org.macstream.host.engine.sunshine 2>/dev/null
```

The Dashboard exposes a button "Resetar permissão de Gravação de Tela"
that runs the first three commands.

## Step 2 — Grant Screen Recording

1. Open **System Settings → Privacy & Security → Screen Recording**
   (in pt-BR: "Gravação do Áudio do Sistema e da Tela").
2. Click the `+` button. Authenticate when prompted.
3. Navigate to `/Applications` and add **`MacStream Host`**. Toggle ON.
4. Click `+` again, open **`/Applications/MacStream Host.app/Contents/Resources/sunshine/`**, and add **`Sunshine.app`** (`MacStream Video Engine`). Toggle ON.
5. macOS may offer to "Quit & Reopen" — accept.

If Moonlight pairs but shows `Failed to initialize video capture/encoding`,
restart the engine via the dashboard or:

```bash
/Applications/MacStream\ Host.app/Contents/MacOS/macstreamctl restart
```

Sunshine can cache capture trust at boot, so grants made while the
engine is already running may not apply until restart.

## Step 3 — Grant Accessibility

Without Accessibility, ALL keyboard and mouse forwarding from Moonlight
is silently dropped — the engine receives the events but `CGEventPost`
gets nowhere. The macOS log doesn't surface the denial, so the only
symptom is "vídeo + áudio funcionam, input não chega".

1. **System Settings → Privacy & Security → Accessibility**.
2. Click `+`, authenticate.
3. Navigate to `/Applications` and add **`MacStream Host`**. Toggle ON.
4. If keyboard or mouse still fail after video starts, add
   **`/Applications/MacStream Host.app/Contents/Resources/sunshine/Sunshine.app`**
   as well.

The dashboard probes `AXIsProcessTrusted()` and shows an Accessibility
warning if the grant is missing. Restart the engine after changing this
grant while Sunshine is already running.

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
- `macstreamctl status --json` shows `webUIReachable: true`

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

## Bloqueio seguro

MacStream Host usa bloqueio seguro como modo padrão. Ele cobre as telas
físicas locais com overlay preto e exige autenticação local, enquanto o
cliente Moonlight continua vendo e usando o desktop normalmente.

### Primeiro bloqueio

No primeiro clique em **Bloquear host**, se ainda não houver senha
MacStream:

1. O app mostra uma sheet local para criar a senha.
2. A senha precisa ser não vazia e a confirmação precisa bater.
3. A senha é salva no Keychain do macOS, separada da senha do usuário.
4. O bloqueio seguro começa automaticamente depois de salvar.

Touch ID / senha do macOS é o caminho preferencial de desbloqueio
quando disponível, mas a senha MacStream continua obrigatória como
fallback local. O app nunca lê a senha do macOS; usa apenas
LocalAuthentication.

Em **Ajustes → Modo remoto**, mantenha `Permitir Touch ID / senha do
macOS` ativo se quiser o prompt nativo. Ajuste `Tentativas antes do
lockout` se quiser (default 5). Após exceder, o painel entra em backoff
temporal (30s × tentativa extra, cap 5 min). Não é lockout permanente.

### O que acontece quando você clica "Bloquear host"

- **Tela capturada pelo Moonlight** (normalmente o MacBook built-in):
  não recebe nenhuma `NSWindow`, porque esse caminho aparece no
  ScreenCaptureKit/Moonlight mesmo com `sharingType = .none`. O app usa
  brilho/backlight em 0 e mantém um watchdog reaplicando esse estado
  enquanto o host estiver bloqueado.
- **Telas não capturadas** (ex.: LG external): NSWindow preto cobre o
  display inteiro. O painel de senha aparece em uma dessas telas.
- **Cliente Moonlight**: continua vendo o desktop ao vivo, com mouse e
  teclado funcionando. Nunca vê o overlay.

### Casos especiais

| Situação | Comportamento |
|---|---|
| Único display + Sunshine/Moonlight ativo | Pre-flight rejeita: "Bloqueio seguro precisa de uma tela não capturada pelo Moonlight." Conecte outro display ou encerre a sessão antes de bloquear. |
| Despluga um monitor durante o lock | O controlador observa `didChangeScreenParametersNotification` e reconstrói as janelas. Painel de senha migra para outra tela não capturada. |
| Esqueceu a senha do MacStream | Use Touch ID / senha do macOS (se ativado). Recovery sem precisar reinstalar. |
| Quer escapar pelo tray | Em modo seguro, o item de unlock do tray é desabilitado deliberadamente. Desbloqueio só pelo painel local. |
| Pressiona `Cmd+Q` ou clica fora | Não desbloqueia. O `SecureLockWindow` é key + screenSaver level. |
| Moonlight desconecta com host travado | Auto-release: o `streamEndWatcher` detecta `CLIENT DISCONNECTED` na sunshine.log e libera (não tem mais cliente pra proteger). |

### Modo legado

`Overlay no app (seguro)` permanece disponível como modo legado em
Ajustes, mas não é o padrão. Ele escurece displays sem a mesma barreira
de autenticação local do bloqueio seguro.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Moonlight shows the host with a lock | Host discovered but not paired | Pair through `https://localhost:47990` using the PIN shown by Moonlight |
| Moonlight pairs, then shows "Failed to initialize video capture/encoding. Is a display connected and turned on?" | Screen Recording missing for the nested engine, grant made after engine boot, display asleep, or no active capture display | Re-do Step 2 for both entries, restart the engine, and enable "Manter display acordado" for remote/headless use |
| Moonlight shows "Failed to start streaming" | Screen Recording denied or encoder startup failed | Re-do Step 2, restart the engine, then inspect `docs/SUNSHINE_ENGINE_RUNBOOK.md` |
| Video and audio work, **neither keyboard nor mouse** reach the Mac | Accessibility denied for `org.macstream.host` | Re-do Step 3; the AccessibilityRecoveryBanner in the dashboard will surface this automatically |
| `Error: No screen capture permission!` in sunshine.log after rebuild | TCC grant was reset (rare with stable identity) | `tccutil reset` (Step 1) + Step 2 + restart the engine |
| Black strip across remote feed during host lock | Old build before the host-lock fix | Update to a build that contains `Suppress unlock panel during stream` |
| Host stays locked after disconnecting Moonlight | Old build before auto-release fix | Update to a build that contains `Extract SunshineSessionTracker` |
| Moonlight has video but no audio | macOS Tap API permission not granted (System Audio Recording, macOS 14.4+) | First Moonlight session triggers the prompt; accept it. If you missed it, the dashboard's audio card surfaces the warning. |
| Two cursors visible on iPad (iPad pointer **on top of** host cursor) | iPadOS renders its native trackpad/mouse pointer on top of every app — not a host bug. Sunshine has no knob to suppress the iPad's pointer. | Tap the screen once during the Moonlight session to enter "mouse capture mode": the iPad pointer hides and only the host cursor remains. Alternatively, in Moonlight iOS settings set **Touchscreen mode → Touchscreen as trackpad**. |
| Overlay appears in Moonlight when locking the host | Build rendered an `NSWindow` on the streamed display; ScreenCaptureKit captured it despite `sharingType = .none` | Update to a build that skips all windows on the streamed display and uses brightness watchdog there. |
| Host display can be revealed by raising brightness | Old build applied brightness once and did not enforce it during lock | Update to a build with brightness watchdog while secure lock is active. |
| Host display goes black during stream and Moonlight cursor freezes | Old build that ran gamma blackout on the streamed display or captured remote input with the local shield | Update to a build where the streamed display has no window and the password panel exists only on a non-streamed display. |
| LG / external monitor stays bright when locking the host | Old build that only used `DisplayServicesSetBrightness` (no-op on externals) | Update to a build that contains "Multi-display lock via gamma blackout fallback" — externals dim via `CGSetDisplayTransferByFormula`. |
| Dashboard button stays "Bloquear host" even when lock is active | Old build before the dashboard toggle | Update to a build that contains "Dashboard 'Bloquear host' toggles to 'Desbloquear host' while locked". |
