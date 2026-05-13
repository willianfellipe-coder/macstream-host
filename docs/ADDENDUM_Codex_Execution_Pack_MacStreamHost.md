# Addendum Codex-Ready — MacStream Host

**Documento complementar ao PRD principal**  
**Projeto:** MacStream Host  
**Objetivo:** transformar a especificação de produto/arquitetura em um pacote executável pelo Codex, reduzindo ambiguidade e criando tarefas implementáveis, testáveis e versionáveis.

---

## 1. Veredito técnico

O PRD principal está forte como documento de visão, produto e arquitetura, mas **não deve ser considerado sozinho como especificação final para o Codex implementar o projeto inteiro sem lacunas**.

Ele cobre bem:

- visão do produto;
- posicionamento;
- arquitetura macro;
- integração Sunshine + BlackHole;
- estratégia GPL;
- UX desejada;
- roadmap;
- riscos;
- prompts iniciais.

Ainda faltava, para execução real no Codex:

- backlog granular por issue;
- contratos de interface entre módulos;
- comandos reais de validação;
- matriz de permissões macOS;
- estratégia de versionamento dos upstreams;
- definição de MVP congelada;
- plano de testes manual/automatizado;
- Definition of Done;
- política de commits/branches;
- critérios objetivos para o Codex saber quando parar;
- decisões técnicas explícitas em formato ADR.

---

## 2. Escopo congelado do MVP

### 2.1 O que entra no MVP

O MVP deve entregar um **orquestrador macOS-first para Sunshine**, com suporte assistido a BlackHole, sem ainda tentar reescrever Sunshine ou criar um protocolo próprio.

Entram no MVP:

1. App macOS nativo em SwiftUI.
2. CLI `macstreamctl`.
3. Geração de configuração Sunshine isolada.
4. Geração de `apps.json` com app `Desktop`.
5. Start/stop/restart do processo Sunshine.
6. Verificação de porta Web UI.
7. Detecção de BlackHole 2ch.
8. Orientação de permissões macOS.
9. LaunchAgent por usuário.
10. Tela de diagnóstico.
11. Logs locais.
12. Botão para abrir Web UI avançada do Sunshine.
13. Instruções guiadas de pareamento com Moonlight.
14. Documentação GPL/compliance.

### 2.2 O que não entra no MVP

Fica fora do MVP:

1. Fork profundo do Sunshine.
2. Fork customizado do BlackHole com branding próprio.
3. Pairing nativo via API interna do Sunshine.
4. Helper XPC privilegiado funcional.
5. Instalador `.pkg` próprio para driver de áudio.
6. Auto-update com Sparkle.
7. Crash reporting.
8. Integração real com Tailscale CLI.
9. Criação automática de Multi-Output Device.
10. Suporte pleno a gamepad no macOS.
11. Distribuição via Mac App Store.

---

## 3. Decisões arquiteturais — ADRs

### ADR-001 — App nativo SwiftUI

**Decisão:** usar Swift + SwiftUI.  
**Motivo:** integração nativa com macOS, permissões, LaunchAgent/Login Item, CoreAudio, Network.framework e aparência comercial.  
**Alternativas rejeitadas:** Electron e Tauri.  
**Status:** aprovado.

### ADR-002 — Wrapper/orquestrador antes de fork

**Decisão:** iniciar como wrapper/orquestrador do Sunshine e BlackHole.  
**Motivo:** menor risco técnico e mais velocidade de entrega.  
**Quando revisar:** quando pairing nativo, APIs internas ou bugs macOS exigirem patch upstream.  
**Status:** aprovado.

### ADR-003 — Configuração isolada do Sunshine

**Decisão:** usar diretório próprio em `~/Library/Application Support/MacStreamHost/sunshine/`.  
**Motivo:** evitar conflito com instalação Sunshine existente e facilitar reset/suporte.  
**Status:** aprovado.

### ADR-004 — BlackHole oficial no MVP

**Decisão:** detectar e orientar instalação do BlackHole 2ch oficial no MVP.  
**Motivo:** reduzir manutenção inicial de fork de driver.  
**Status:** aprovado.

### ADR-005 — LaunchAgent por usuário

**Decisão:** usar LaunchAgent no contexto do usuário.  
**Motivo:** streaming de tela e permissões do macOS normalmente dependem da sessão do usuário.  
**Status:** aprovado.

### ADR-006 — Web UI avançada continua disponível

**Decisão:** não esconder completamente a Web UI do Sunshine.  
**Motivo:** reduz escopo e mantém compatibilidade com recursos avançados.  
**Status:** aprovado.

---

## 4. Estratégia de versionamento upstream

O repositório deve fixar explicitamente:

```text
SUNSHINE_UPSTREAM_REPO=https://github.com/LizardByte/Sunshine
SUNSHINE_UPSTREAM_REF=<tag ou commit fixado>
BLACKHOLE_UPSTREAM_REPO=https://github.com/ExistentialAudio/BlackHole
BLACKHOLE_UPSTREAM_REF=<tag ou commit fixado>
```

Regras:

1. Nunca depender de `latest` em build reprodutível.
2. Registrar SHA/tag em `UPSTREAMS.md`.
3. Gerar `THIRD_PARTY_NOTICES.md` no release.
4. Incluir instruções para reconstruir binários incluídos.
5. Se binários upstream forem distribuídos, disponibilizar fonte correspondente e referência exata.

Arquivo recomendado:

```text
UPSTREAMS.md
```

Conteúdo mínimo:

```md
# Upstreams

## Sunshine
- Repository: https://github.com/LizardByte/Sunshine
- Version/ref: TBD
- License: GPL-3.0
- Local use: bundled runtime/orchestrated process
- Modifications: none in MVP

## BlackHole
- Repository: https://github.com/ExistentialAudio/BlackHole
- Version/ref: TBD
- License: GPL-3.0
- Local use: detected/optionally installed external driver
- Modifications: none in MVP
```

---

## 5. Estrutura de repositório Codex-ready

```text
MacStreamHost/
  README.md
  LICENSE
  NOTICE.md
  THIRD_PARTY_NOTICES.md
  UPSTREAMS.md
  CONTRIBUTING.md
  SECURITY.md
  CHANGELOG.md

  Package.swift

  Sources/
    MacStreamHostApp/
      MacStreamHostApp.swift
      Views/
      ViewModels/
      Resources/

    MacStreamCore/
      Sunshine/
      Audio/
      Permissions/
      Network/
      Diagnostics/
      LaunchAgent/
      Security/
      Logging/
      Models/

    MacStreamCLI/
      main.swift

    MacStreamHelper/
      README.md
      Stubs/

  Resources/
    templates/
      sunshine.conf.template
      apps.json.template
      launchagent.plist.template

  scripts/
    bootstrap.sh
    build.sh
    test.sh
    lint.sh
    package_dmg.sh
    doctor-smoke-test.sh

  docs/
    PRD.md
    architecture.md
    codex-execution-plan.md
    gpl-compliance.md
    sunshine-integration.md
    blackhole-integration.md
    audio-routing.md
    permissions.md
    network.md
    launchagent.md
    troubleshooting.md
    release-process.md

  .github/
    workflows/
      ci.yml
      release.yml
```

---

## 6. Contratos de interface Swift

### 6.1 SunshineService

```swift
public protocol SunshineServicing {
    func isInstalled() async -> Bool
    func version() async throws -> String?
    func configure(_ config: SunshineConfig) async throws
    func start() async throws
    func stop() async throws
    func restart() async throws
    func status() async -> SunshineStatus
    func isWebUIReachable() async -> Bool
    func openWebUI() async throws
    func logs(lines: Int) async throws -> String
}
```

### 6.2 ConfigManager

```swift
public protocol ConfigManaging {
    var configDirectory: URL { get }
    var sunshineConfigURL: URL { get }
    var appsJSONURL: URL { get }

    func ensureDirectories() throws
    func writeDefaultConfig(overwrite: Bool) throws
    func writeDefaultApps(overwrite: Bool) throws
    func backupExistingConfig() throws
    func validateConfig() throws -> ConfigValidationResult
}
```

### 6.3 AudioManager

```swift
public protocol AudioManaging {
    func listAudioDevices() async throws -> [AudioDevice]
    func hasBlackHole2ch() async throws -> Bool
    func preferredAudioMode() async -> AudioMode
    func validateAudioRoute() async -> AudioDiagnosticResult
    func openAudioMIDISetup() async throws
}
```

### 6.4 PermissionManager

```swift
public protocol PermissionManaging {
    func screenRecordingStatus() async -> PermissionStatus
    func microphoneStatus() async -> PermissionStatus
    func accessibilityStatus() async -> PermissionStatus
    func localNetworkStatus() async -> PermissionStatus
    func openSettings(for permission: MacPermission) async throws
    func runPracticalPermissionTests() async -> [PermissionCheck]
}
```

### 6.5 NetworkManager

```swift
public protocol NetworkManaging {
    func localAddresses() async throws -> [NetworkAddress]
    func tailscaleAddress() async throws -> String?
    func isPortListening(_ port: Int, protocol proto: NetworkProtocol) async -> Bool
    func sunshinePortReport(basePort: Int) async -> SunshinePortReport
    func openFirewallSettings() async throws
}
```

### 6.6 LaunchAgentManager

```swift
public protocol LaunchAgentManaging {
    func installLaunchAgent() async throws
    func uninstallLaunchAgent() async throws
    func isInstalled() async -> Bool
    func isLoaded() async -> Bool
    func load() async throws
    func unload() async throws
}
```

### 6.7 DiagnosticsService

```swift
public protocol DiagnosticsServicing {
    func runDoctor() async -> DoctorReport
    func exportSupportBundle(redactSensitiveData: Bool) async throws -> URL
}
```

---

## 7. CLI `macstreamctl` — especificação operacional

### 7.1 Comandos obrigatórios no MVP

```bash
macstreamctl doctor
macstreamctl configure
macstreamctl start
macstreamctl stop
macstreamctl restart
macstreamctl status
macstreamctl logs --lines 100
macstreamctl reset --soft
macstreamctl paths
```

### 7.2 Saída humana

Exemplo:

```text
MacStream Host Doctor

[✓] macOS version: 15.x
[✓] Architecture: arm64
[✓] Config directory exists
[✓] sunshine.conf exists
[✓] apps.json exists
[✓] Sunshine binary found
[✓] Sunshine process running
[✓] Web UI reachable at https://localhost:47990
[!] BlackHole 2ch not detected
[✓] Local IP: 192.168.1.20

Result: DEGRADED
Next action: Install BlackHole 2ch or use native audio capture.
```

### 7.3 Saída JSON

```bash
macstreamctl doctor --json
```

Exemplo:

```json
{
  "result": "degraded",
  "checks": [
    { "id": "macos.version", "status": "pass", "value": "15.x" },
    { "id": "arch", "status": "pass", "value": "arm64" },
    { "id": "audio.blackhole", "status": "warn", "value": "missing" }
  ]
}
```

---

## 8. Configuração Sunshine — template fechado do MVP

Arquivo:

```text
Resources/templates/sunshine.conf.template
```

Conteúdo inicial:

```ini
sunshine_name = MacStream Host
locale = pt_BR
min_log_level = info
system_tray = disabled

keyboard = enabled
mouse = enabled
native_pen_touch = enabled
high_resolution_scrolling = enabled

stream_audio = enabled
# MVP default: prefer native macOS audio capture when supported.
# Fallback: set to BlackHole 2ch if native capture fails.
audio_sink = {{AUDIO_SINK}}

upnp = disabled
address_family = ipv4
port = 47989
origin_web_ui_allowed = pc
```

Regra para `{{AUDIO_SINK}}`:

```text
native audio mode: empty string
blackhole mode: BlackHole 2ch
advanced/custom: user selected device name
```

---

## 9. `apps.json` — template fechado do MVP

Arquivo:

```text
Resources/templates/apps.json.template
```

Conteúdo:

```json
{
  "env": {},
  "apps": [
    {
      "name": "Desktop",
      "output": "",
      "cmd": "",
      "detached": [],
      "image-path": "desktop.png"
    }
  ]
}
```

Critério de aceite:

- Moonlight deve mostrar o app `Desktop`.
- Ao iniciar `Desktop`, deve transmitir a sessão atual do macOS.

---

## 10. LaunchAgent — contrato MVP

Arquivo gerado:

```text
~/Library/LaunchAgents/com.macstream.host.sunshine.plist
```

Regras:

1. Deve rodar no usuário logado.
2. Deve usar config isolada.
3. Deve escrever logs em `~/Library/Logs/MacStreamHost/`.
4. Deve ser removível pelo app/CLI.
5. Não deve exigir root para instalação no MVP.

Comandos usados pelo CLI:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.macstream.host.sunshine.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.macstream.host.sunshine.plist
launchctl print gui/$(id -u)/com.macstream.host.sunshine
```

---

## 11. Matriz de portas Sunshine

Base port padrão:

```ini
port = 47989
```

Portas derivadas:

| Serviço | Protocolo | Porta padrão | Offset |
|---|---:|---:|---:|
| HTTPS/nvhttp | TCP | 47984 | -5 |
| HTTP | TCP | 47989 | 0 |
| Web UI | TCP | 47990 | +1 |
| RTSP | TCP | 48010 | +21 |
| Vídeo | UDP | 47998 | +9 |
| Controle | UDP | 47999 | +10 |
| Áudio | UDP | 48000 | +11 |
| Microfone não usado | UDP | 48002 | +13 |

No MVP, o app deve apenas diagnosticar portas locais e orientar o usuário. Não deve abrir roteador, UPnP nem port forwarding automaticamente.

---

## 12. Matriz de permissões macOS

| Permissão | Obrigatória? | Como pedir | Como validar no MVP |
|---|---:|---|---|
| Screen Recording | Sim | abrir Privacy & Security | teste prático via Sunshine/log |
| Microphone | Sim para BlackHole/loopback | abrir Privacy & Security | teste prático/log |
| Local Network | Sim para descoberta local | prompt do sistema/rede | teste com IP/porta |
| Accessibility | Desejável | abrir Privacy & Security | status AXIsProcessTrusted |
| Login Items | Desejável | app settings/LaunchAgent de usuário | LaunchAgent instalado/carregado |
| Full Disk Access | Não | não pedir | não aplicável |

Regra de UX:

- Não pedir Full Disk Access no MVP.
- Não pedir permissões antes de explicar o motivo.
- Sempre oferecer botão “Abrir Ajustes”.

---

## 13. Backlog em formato de issues para Codex

### Issue 001 — Criar estrutura base do repositório

**Objetivo:** criar projeto SwiftPM com módulos principais.  
**Entregáveis:** `Package.swift`, diretórios, README, LICENSE, docs iniciais.  
**Critérios de aceite:** `swift build` executa sem erro.

### Issue 002 — Implementar ConfigManager

**Objetivo:** gerar diretórios, `sunshine.conf` e `apps.json`.  
**Critérios de aceite:** `macstreamctl configure` cria arquivos no caminho correto e não sobrescreve sem backup.

### Issue 003 — Implementar SunshineService básico

**Objetivo:** localizar binário, iniciar/parar processo, verificar status.  
**Critérios de aceite:** `start`, `stop`, `restart`, `status` funcionam via CLI.

### Issue 004 — Implementar verificação de Web UI

**Objetivo:** testar `https://localhost:47990`.  
**Critérios de aceite:** `doctor` reporta reachable/unreachable sem travar em certificado self-signed.

### Issue 005 — Implementar AudioManager básico

**Objetivo:** listar dispositivos de áudio e detectar BlackHole 2ch.  
**Critérios de aceite:** `doctor` mostra `blackhole: present/missing`.

### Issue 006 — Implementar NetworkManager básico

**Objetivo:** listar IPs locais, detectar porta listening e Tailscale se disponível.  
**Critérios de aceite:** `doctor` mostra IP local e portas Sunshine.

### Issue 007 — Implementar LaunchAgentManager

**Objetivo:** instalar, carregar, descarregar e remover LaunchAgent.  
**Critérios de aceite:** Sunshine inicia após login ou bootstrap manual.

### Issue 008 — Implementar DiagnosticsService

**Objetivo:** unificar checks em relatório humano e JSON.  
**Critérios de aceite:** `macstreamctl doctor` e `doctor --json` funcionam.

### Issue 009 — Criar app SwiftUI MVP

**Objetivo:** criar GUI com sidebar e dashboard.  
**Critérios de aceite:** app mostra status do servidor, áudio, rede e permissões.

### Issue 010 — Tela de permissões

**Objetivo:** guiar usuário para Screen Recording, Microphone e Accessibility.  
**Critérios de aceite:** botões abrem Settings e o app explica cada permissão.

### Issue 011 — Tela de pareamento assistido

**Objetivo:** guiar PIN do Moonlight sem implementar API nativa ainda.  
**Critérios de aceite:** tela abre Web UI/página de PIN ou instrui usuário com clareza.

### Issue 012 — Logs e pacote de suporte

**Objetivo:** coletar logs e diagnóstico em zip.  
**Critérios de aceite:** gera arquivo exportável com dados sensíveis mascaráveis.

### Issue 013 — Documentação GPL/compliance

**Objetivo:** garantir LICENSE, NOTICE, UPSTREAMS, THIRD_PARTY_NOTICES.  
**Critérios de aceite:** release contém fontes/instruções/avisos suficientes.

### Issue 014 — Smoke test com Moonlight no iPad

**Objetivo:** validar fluxo real ponta a ponta.  
**Critérios de aceite:** iPad encontra host, pareia, abre Desktop, teclado/mouse funcionam, vídeo transmite e áudio funciona ou erro guiado é exibido.

---

## 14. Test plan

### 14.1 Testes automatizados

- ConfigManager escreve arquivos corretos.
- ConfigManager preserva backup.
- LaunchAgentManager gera plist válido.
- NetworkManager calcula portas derivadas corretamente.
- DiagnosticsService retorna JSON válido.
- AudioManager cobre parsing/detecção com fakes em testes; runtime usa CoreAudio real.

### 14.2 Testes manuais obrigatórios

#### Cenário A — Mac limpo sem Sunshine/BlackHole

1. Abrir app.
2. Rodar onboarding.
3. Configurar Sunshine runtime.
4. Detectar ausência de BlackHole.
5. Orientar modo nativo/fallback.
6. Iniciar servidor.
7. Parear Moonlight.

#### Cenário B — Mac com Sunshine já instalado

1. App detecta Sunshine externo.
2. Não sobrescreve config existente.
3. Oferece modo isolado MacStreamHost.

#### Cenário C — Mac com BlackHole já instalado

1. App detecta BlackHole 2ch.
2. Permite selecionar `audio_sink = BlackHole 2ch`.
3. Doctor reporta áudio OK ou erro específico.

#### Cenário D — Via Tailscale

1. Mac e iPad no mesmo tailnet.
2. App mostra IP Tailscale.
3. Usuário adiciona IP manualmente no Moonlight.
4. Pareamento e Desktop funcionam.

#### Cenário E — Sem permissão de tela

1. Remover Screen Recording.
2. Iniciar Sunshine.
3. App deve detectar falha ou orientar correção.

---

## 15. Definition of Done do MVP

O MVP só está pronto quando:

1. `swift build` passa.
2. `swift test` passa.
3. `macstreamctl doctor` funciona.
4. `macstreamctl configure` gera config válida.
5. `macstreamctl start` inicia Sunshine.
6. Web UI responde localmente.
7. App SwiftUI mostra status real.
8. App não exige terminal para fluxo básico.
9. Moonlight consegue parear via fluxo guiado.
10. Desktop transmite em rede local.
11. Áudio tem pelo menos um caminho funcional documentado.
12. LaunchAgent pode ser instalado e removido.
13. Logs são acessíveis.
14. Reset soft funciona.
15. README explica instalação, uso e limitações.
16. GPL compliance está documentado.
17. Limitações macOS estão claramente comunicadas.

---

## 16. Protocolo de trabalho para Codex

### 16.1 Regra geral

O Codex deve trabalhar em ciclos pequenos:

```text
1 issue = 1 branch = 1 PR
```

### 16.2 Ordem de execução

1. Issue 001 — estrutura base.
2. Issue 002 — ConfigManager.
3. Issue 008 — DiagnosticsService e `doctor --json`.
4. Issue 003 — SunshineService.
5. Issue 004 — Web UI check.
6. Issue 006 — NetworkManager.
7. Issue 005 — AudioManager.
8. Issue 007 — LaunchAgentManager.
9. Issue 009 — SwiftUI MVP.
10. Issue 010 — permissões.
11. Issue 011 — pareamento assistido.
12. Issue 012 — logs/suporte.
13. Issue 013 — compliance.
14. Issue 014 — smoke test real.

### 16.3 Regra de parada

O Codex deve parar e pedir decisão humana quando encontrar:

- necessidade de instalar driver privilegiado;
- necessidade de assinar/notarizar;
- mudança no código upstream do Sunshine;
- mudança no código upstream do BlackHole;
- comportamento não documentado da API de pairing;
- permissões macOS que não possam ser validadas publicamente.

---

## 17. Prompt definitivo para abrir no Codex

```text
Você está trabalhando no projeto MacStream Host.

Objetivo:
Criar um app macOS open source GPL-3.0-or-later, em Swift + SwiftUI, que orquestra Sunshine e BlackHole para tornar simples usar um Mac como host compatível com Moonlight, especialmente para acesso via iPad com teclado/trackpad.

Leia primeiro estes documentos:
- docs/PRD.md
- docs/codex-execution-plan.md
- docs/architecture.md
- docs/gpl-compliance.md
- docs/sunshine-integration.md
- docs/blackhole-integration.md

Escopo do MVP:
- App SwiftUI com dashboard simples.
- CLI macstreamctl.
- ConfigManager para gerar sunshine.conf e apps.json.
- SunshineService para start/stop/status.
- DiagnosticsService com doctor humano e JSON.
- AudioManager para detectar BlackHole 2ch.
- NetworkManager para IP local, Tailscale e portas.
- LaunchAgentManager para autostart por usuário.
- Tela de permissões.
- Tela de pareamento assistido.
- Logs e pacote de suporte.

Não implemente no MVP:
- fork profundo do Sunshine;
- fork customizado do BlackHole;
- helper XPC privilegiado funcional;
- pairing nativo não documentado;
- auto-update;
- Mac App Store;
- abertura automática de portas externas.

Comece pela Issue 001: criar estrutura base do repositório com SwiftPM, módulos, README, LICENSE, NOTICE, UPSTREAMS e docs iniciais.

Regras:
- Faça mudanças pequenas e testáveis.
- Inclua testes onde fizer sentido.
- Não use dependências proprietárias.
- Preserve compatibilidade GPL-3.0-or-later.
- Não sobrescreva configurações existentes sem backup.
- Sempre documente limitações do macOS.
- Ao concluir, explique exatamente quais arquivos criou/alterou e como validar com comandos locais.
```

---

## 18. Checklist final antes de entregar ao Codex

Antes de iniciar desenvolvimento, preparar no repositório:

- [ ] `docs/PRD.md` com o PRD principal.
- [ ] `docs/codex-execution-plan.md` com este addendum.
- [ ] `LICENSE` GPL-3.0-or-later.
- [ ] `NOTICE.md`.
- [ ] `UPSTREAMS.md`.
- [ ] `THIRD_PARTY_NOTICES.md` inicial.
- [ ] `README.md` explicando status experimental.
- [ ] Issues 001 a 014 criadas no GitHub.
- [ ] Decidir versão/tag inicial do Sunshine.
- [ ] Decidir versão/tag inicial do BlackHole.
- [ ] Confirmar se o MVP incluirá binário Sunshine embutido ou apenas detecção/instrução.
- [ ] Confirmar se BlackHole será apenas detectado ou se o app baixará/orientará instalação.
- [ ] Confirmar conta Apple Developer para notarização futura.

---

## 19. Conclusão

Com este addendum, o projeto fica muito mais próximo de um pacote realmente executável pelo Codex. O PRD principal define o “o quê” e o “porquê”; este documento define o “como começar”, “em qual ordem”, “com quais contratos” e “como validar”.
