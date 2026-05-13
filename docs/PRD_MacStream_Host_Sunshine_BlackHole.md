# PRD + Especificação Técnica — macOS Streaming Host para Moonlight baseado em Sunshine + BlackHole

**Nome provisório:** `MacStream Host`  
**Licença proposta:** GPL-3.0-or-later  
**Plataforma alvo:** macOS 14.2+ / Apple Silicon prioritário  
**Cliente alvo:** Moonlight no iPadOS, iOS, tvOS, Android, Windows, macOS e demais clientes compatíveis  
**Objetivo central:** transformar a experiência técnica atual de instalar/configurar Sunshine + áudio loopback em uma aplicação macOS única, guiada, visual, confiável, comercialmente polida e 100% compatível com Moonlight.

---

## 1. Contexto

Hoje, para transformar um MacBook em host de streaming compatível com Moonlight, o usuário normalmente precisa instalar e configurar componentes separados:

1. **Sunshine** — servidor/host compatível com Moonlight/GameStream.
2. **BlackHole 2ch** — driver virtual de áudio para loopback quando se deseja capturar áudio do sistema via dispositivo virtual.
3. Permissões do macOS — gravação de tela, microfone, acessibilidade, rede local, itens de login etc.
4. Configuração manual via Web UI do Sunshine.
5. Configuração manual de áudio via Ajustes do Sistema ou `Audio MIDI Setup`.
6. Diagnóstico manual de firewall, portas, rede, PIN e pareamento.

A proposta é criar uma aplicação macOS consolidada, com instalador, interface gráfica e automação de setup, reduzindo o atrito de “ferramenta de desenvolvedor” para “produto de usuário final”.

---

## 2. Visão do produto

O produto deve ser um **host macOS comercialmente amigável para Moonlight**, empacotando/orquestrando Sunshine e BlackHole sob uma experiência nativa, simples e com foco em iPad como terminal remoto.

A experiência desejada:

> “Instalo o app no Mac, abro, sigo um assistente visual, dou permissões, escolho qualidade, pareio com Moonlight e começo a usar meu Mac pelo iPad.”

---

## 3. Posicionamento

### 3.1 Usuário primário

Usuário de MacBook/Mac mini/iMac que quer acessar o Mac remotamente com baixa latência via Moonlight, especialmente usando:

- iPad Pro com Magic Keyboard;
- iPad com teclado Bluetooth;
- Apple TV;
- outro computador;
- rede local ou VPN tipo Tailscale.

### 3.2 Caso de uso prioritário

Uso produtivo do macOS pelo iPad:

- controlar o MacBook pela internet;
- usar teclado e trackpad do iPad;
- acessar apps macOS reais;
- manter áudio do Mac chegando no iPad;
- evitar configurações manuais complexas;
- iniciar o servidor automaticamente.

### 3.3 Diferencial

Não é apenas “Sunshine com skin”. É uma camada macOS-first para:

- instalar dependências;
- configurar áudio;
- configurar Sunshine;
- validar permissões;
- criar serviço de inicialização;
- expor status claro;
- guiar pareamento;
- diagnosticar problemas;
- aplicar presets otimizados para iPad/Moonlight.

---

## 4. Princípios de produto

1. **Zero terminal para o usuário comum.**
2. **Tudo reversível:** desinstalar, remover driver, remover serviço, limpar configs.
3. **Compatibilidade antes de customização.**
4. **Moonlight como cliente oficial recomendado.**
5. **macOS-first:** usar APIs e padrões nativos do macOS sempre que possível.
6. **Open source real:** código, builds, scripts e instruções auditáveis.
7. **Sem esconder GPL:** créditos, licenças e fontes acessíveis no app.
8. **Fail loud, fix guided:** quando algo falhar, o app deve explicar e oferecer correção.
9. **Segurança por padrão:** bind local da interface admin, senha forte, permissões mínimas, aviso sobre exposição de portas.
10. **Experiência comercial:** onboarding visual, status simples, linguagem clara, logs exportáveis.

---

## 5. Base técnica analisada

### 5.1 Sunshine

Sunshine é um host de streaming self-hosted para Moonlight. Ele oferece streaming de baixa latência, suporte a encoding por hardware quando disponível e uma Web UI para configuração e pareamento.

Pontos relevantes para macOS:

- Possui binários para macOS em releases.
- macOS é considerado experimental no projeto original.
- Gamepads no macOS não são suportados atualmente pelo Sunshine.
- Captura de tela no macOS usa ScreenCaptureKit.
- Encoding no macOS usa VideoToolbox.
- O macOS exige permissões de gravação de tela e microfone.
- A configuração padrão fica em `~/.config/sunshine`.
- A Web UI padrão roda em `https://localhost:47990`.
- O pareamento com Moonlight é feito via PIN na Web UI.
- A configuração `audio_sink` pode usar `BlackHole 2ch`.
- Em macOS 14+ há menção a captura nativa de áudio do sistema via Audio Tap API ao deixar `audio_sink` em branco, mas ainda é prudente manter BlackHole como fallback/rota controlada para compatibilidade.

### 5.2 BlackHole

BlackHole é um driver virtual de áudio loopback para macOS.

Pontos relevantes:

- Funciona como dispositivo de áudio virtual.
- Permite passar áudio entre aplicações com zero latência adicional.
- Possui builds 2ch, 16ch, 64ch, 128ch e 256ch.
- É compatível com Intel e Apple Silicon.
- Não exige kernel extension nem alteração de segurança do sistema.
- Pode ser instalado por `.pkg` ou Homebrew.
- Pode ser customizado via constantes de build.
- O README deixa claro que projetos não-GPL precisam licença separada; como este projeto será GPL, a integração é coerente.
- Para setup de captura de áudio do sistema, normalmente é necessário Multi-Output Device ou configuração equivalente.
- Há limitações conhecidas do macOS com volume em Multi-Output Device.

---

## 6. Estratégia de licença e compliance GPL-3.0

### 6.1 Decisão

O projeto deve ser GPL-3.0-or-later e publicar:

- código fonte completo;
- scripts de build;
- scripts de empacotamento;
- instruções para reproduzir o build;
- modificações feitas em Sunshine e/ou BlackHole;
- avisos de copyright;
- cópia da GPL;
- seção “About / Open Source Licenses” dentro do app;
- links para os repositórios originais.

### 6.2 Modelo de monetização compatível

Possíveis receitas:

- suporte pago;
- instalação assistida;
- builds assinados/notarizados com conveniência;
- consultoria para empresas;
- suporte prioritário;
- documentação premium, desde que não restrinja os direitos GPL sobre o software;
- doações/sponsors;
- serviços gerenciados;
- automações complementares externas.

Evitar:

- fechar código derivado;
- impedir redistribuição;
- exigir pagamento para exercer liberdades GPL;
- esconder código necessário para reproduzir o binário;
- criar EULA que contradiga GPL;
- misturar código GPL com componentes proprietários no mesmo binário sem cuidado jurídico.

### 6.3 Estrutura recomendada

```text
macstream-host/
  LICENSE
  NOTICE.md
  README.md
  THIRD_PARTY_NOTICES.md
  docs/
  app/
  sunshine/
    upstream/
    patches/
  blackhole/
    upstream/
    patches/
  packaging/
  scripts/
  ci/
```

### 6.4 Caminho jurídico-técnico mais limpo

**Opção recomendada para MVP:** orquestrar Sunshine e BlackHole como componentes GPL incluídos no pacote, sem modificar profundamente os projetos no início.

**Depois:** se necessário, criar forks com patches pequenos e bem documentados.

---

## 7. Arquitetura proposta

### 7.1 Visão geral

```text
+------------------------------------------------------+
|                 MacStream Host.app                   |
|------------------------------------------------------|
| SwiftUI GUI                                          |
| Onboarding Wizard                                   |
| Status Dashboard                                    |
| Settings                                            |
| Pairing Assistant                                   |
| Diagnostics                                         |
| Logs Export                                         |
+-------------------------+----------------------------+
                          |
                          v
+------------------------------------------------------+
|              MacStream Host Controller               |
|------------------------------------------------------|
| Service Manager                                     |
| Config Manager                                      |
| Permission Manager                                  |
| Audio Manager                                       |
| Network Manager                                     |
| Moonlight Pairing Helper                            |
| Health Monitor                                      |
+-------------------------+----------------------------+
                          |
         +----------------+----------------+
         |                                 |
         v                                 v
+--------------------+             +--------------------+
| Sunshine Runtime   |             | BlackHole Driver   |
| sunshine binary    |             | HAL audio driver   |
| Web UI/API         |             | BlackHole 2ch      |
| config files       |             | optional custom    |
+--------------------+             +--------------------+
         |
         v
+--------------------+
| Moonlight Clients  |
| iPad / iPhone / TV |
+--------------------+
```

### 7.2 Componentes

#### 7.2.1 Aplicação principal

Tecnologia recomendada:

- Swift;
- SwiftUI;
- Combine/Observation;
- ServiceManagement;
- Network.framework;
- AVFoundation/CoreAudio;
- ScreenCaptureKit permission detection;
- os.log;
- Sparkle opcional para updates, observando compatibilidade de licença.

Funções:

- onboarding;
- configuração de Sunshine;
- start/stop/restart;
- status do host;
- diagnóstico;
- pareamento;
- gestão de áudio;
- gestão de permissões;
- abertura controlada da Web UI avançada;
- exportação de logs.

#### 7.2.2 Helper privilegiado

Provavelmente necessário para:

- instalar driver HAL em `/Library/Audio/Plug-Ins/HAL`;
- reiniciar CoreAudio;
- instalar LaunchDaemon/LaunchAgent;
- criar/remover arquivos em paths protegidos;
- configurar permissões auxiliares;
- aplicar scripts de setup.

Tecnologias:

- SMAppService;
- XPC;
- Authorization Services, se necessário;
- helper assinado e notarizado.

#### 7.2.3 Sunshine runtime

Opções:

1. **Bundle embutido:** incluir binário Sunshine dentro de `MacStream Host.app/Contents/Resources/sunshine`.
2. **Download no onboarding:** baixar release oficial/fork durante instalação.
3. **Build próprio:** compilar fork e distribuir junto.

Para experiência comercial, a melhor opção é bundle embutido, desde que o projeto forneça o código-fonte correspondente e scripts de build.

#### 7.2.4 BlackHole runtime

Opções:

1. Instalar BlackHole 2ch oficial.
2. Criar build customizado com nome próprio, por exemplo `MacStream Audio 2ch`, baseado no BlackHole, mantendo GPL.
3. Detectar BlackHole existente e reaproveitar.

Recomendação:

- MVP: usar `BlackHole 2ch`.
- Produto polido: build customizado chamado `MacStream Audio 2ch`, para reduzir confusão na interface do usuário, mantendo créditos e licença.

---

## 8. Fluxo de instalação ideal

### 8.1 Download

Usuário baixa:

```text
MacStreamHost.dmg
```

Abre e arrasta:

```text
MacStream Host.app -> Applications
```

### 8.2 Primeira abertura

O app mostra:

```text
Bem-vindo ao MacStream Host
Use seu Mac pelo Moonlight com baixa latência.
```

Botões:

- Começar configuração
- Já tenho Sunshine configurado
- Modo avançado

### 8.3 Checklist inicial

O app verifica:

- arquitetura do Mac;
- versão do macOS;
- Sunshine presente;
- BlackHole presente;
- permissões concedidas;
- porta Web UI disponível;
- portas de streaming disponíveis;
- rede local ativa;
- se Tailscale está instalado;
- se há VPN;
- se o Mac está em bateria;
- se bloqueio de tela/sleep pode atrapalhar.

### 8.4 Instalação guiada

Etapas:

1. Instalar Sunshine runtime.
2. Instalar BlackHole/MacStream Audio.
3. Criar configuração inicial do Sunshine.
4. Criar app “Desktop” no Sunshine.
5. Configurar nome do host.
6. Configurar áudio.
7. Configurar inicialização automática.
8. Solicitar permissões do macOS.
9. Iniciar servidor.
10. Parear Moonlight.

### 8.5 Finalização

Tela final:

```text
Seu Mac está pronto para o Moonlight.
No iPad, abra Moonlight e procure por “MacBook de Willian”.
```

Mostrar:

- IP local;
- hostname;
- status;
- botão “Parear novo dispositivo”;
- botão “Testar conexão”;
- QR code opcional com dados de conexão/instruções.

---

## 9. Fluxo de uso diário

### 9.1 Dashboard principal

Exibir:

```text
Status: Online
Host Moonlight: MacBook Pro
Áudio: OK
Tela: OK
Permissões: OK
Clientes pareados: 1
Inicialização automática: Ativa
Rede: Wi-Fi 6 / 5 GHz
Latência estimada: Boa
```

Ações:

- Iniciar servidor;
- Parar servidor;
- Reiniciar servidor;
- Parear dispositivo;
- Abrir Moonlight no iPad — instruções;
- Diagnosticar;
- Configurações;
- Modo avançado.

### 9.2 Sem terminal

Tudo deve ser feito via botões.

---

## 10. Configuração do Sunshine

### 10.1 Arquivo de configuração

Sunshine usa por padrão:

```text
~/.config/sunshine/sunshine.conf
~/.config/sunshine/apps.json
```

O app deve poder trabalhar com:

```text
~/Library/Application Support/MacStreamHost/sunshine/sunshine.conf
~/Library/Application Support/MacStreamHost/sunshine/apps.json
```

E iniciar Sunshine com caminho explícito:

```bash
sunshine "$HOME/Library/Application Support/MacStreamHost/sunshine/sunshine.conf"
```

Vantagem:

- não conflita com instalação Sunshine pré-existente;
- facilita backup;
- facilita suporte;
- permite reset limpo.

### 10.2 Configuração inicial recomendada

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
audio_sink = BlackHole 2ch

upnp = disabled
```

Observações:

- `upnp` deve ficar desativado por padrão para evitar exposição de portas sem consentimento.
- Para uso remoto, recomendar Tailscale/ZeroTier/WireGuard, não port forwarding manual.
- `audio_sink` pode ficar em branco em macOS 14+ se a captura nativa via Audio Tap funcionar bem; ainda assim, BlackHole deve ser fallback.

### 10.3 Configuração de apps

`apps.json` mínimo:

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

Adicionar presets opcionais:

- Desktop;
- Finder;
- Safari;
- VS Code;
- Terminal;
- Cursor;
- Xcode.

Para o caso de uso “usar o Mac inteiro pelo iPad”, o app principal deve priorizar o app `Desktop`.

---

## 11. Áudio

### 11.1 Objetivo

O usuário deve ouvir no iPad/Moonlight o áudio que o Mac geraria localmente.

### 11.2 Estratégias

#### Estratégia A — Audio Tap API nativa do Sunshine

Em macOS 14+, Sunshine indica que pode capturar áudio nativo deixando `audio_sink` em branco.

Vantagens:

- menos dependência;
- menos configuração;
- menos interferência com saída de áudio do usuário.

Riscos:

- comportamento pode variar;
- Sunshine macOS ainda é experimental;
- menos controle visual para o app wrapper.

#### Estratégia B — BlackHole 2ch

Configurar Sunshine com:

```ini
audio_sink = BlackHole 2ch
```

Vantagens:

- rota conhecida;
- compatível com setups existentes;
- controlável;
- pode ser diagnosticado via CoreAudio.

Riscos:

- usuário pode perder áudio local se saída for alterada incorretamente;
- Multi-Output Device tem limitações;
- volume de Multi-Output Device no macOS é limitado;
- drift correction precisa ser bem configurado em alguns casos.

#### Estratégia C — Driver customizado baseado no BlackHole

Criar:

```text
MacStream Audio 2ch
```

Baseado no BlackHole, com:

- 2 canais;
- 48 kHz e 44.1 kHz;
- baixa latência;
- nome comercial;
- bundle id próprio;
- ícone próprio;
- créditos GPL.

Vantagens:

- UX mais limpa;
- não confunde o usuário;
- permite escondê-lo parcialmente ou usá-lo “por trás”;
- dá mais controle ao produto.

Riscos:

- manutenção de fork;
- assinatura/notarização;
- mais responsabilidade técnica.

### 11.3 Recomendação

MVP:

```text
Preferir Audio Tap nativo quando confiável.
Fallback automático para BlackHole 2ch.
```

Produto estável:

```text
Criar MacStream Audio 2ch baseado em BlackHole.
```

### 11.4 Setup de áudio no app

Tela:

```text
Áudio do Mac para o iPad

[✓] Captura nativa disponível
[ ] Usar driver virtual MacStream Audio
[ ] Manter áudio também nos alto-falantes do Mac
```

Opções:

1. **Somente iPad:** áudio vai para Moonlight, Mac fica mudo.
2. **iPad + Mac:** cria Multi-Output Device.
3. **Avançado:** usuário escolhe dispositivo.

### 11.5 Diagnóstico de áudio

Verificar:

- dispositivo BlackHole/MacStream Audio existe;
- sample rate;
- canais;
- se CoreAudio reconhece;
- se Sunshine está usando device correto;
- se app tem permissão de microfone;
- se stream_audio está habilitado.

Ações automáticas:

- reinstalar driver;
- reiniciar CoreAudio;
- recriar Multi-Output Device;
- restaurar saída padrão.

---

## 12. Permissões macOS

O app deve guiar o usuário para permissões obrigatórias e desejáveis.

### 12.1 Obrigatórias

- Screen Recording / Gravação de Tela;
- Microphone / Microfone, para captura de áudio via input/loopback;
- Local Network, se aplicável;
- Accessibility, se Sunshine precisar controlar entrada.

### 12.2 Desejáveis

- Login Items;
- Full Disk Access não deve ser solicitado salvo necessidade real;
- Notifications para status;
- Background Items.

### 12.3 Tela de permissões

```text
Permissões necessárias

[!] Gravação de tela — necessária para transmitir a imagem do Mac
[!] Microfone — necessário para capturar áudio via dispositivo virtual
[✓] Rede local — necessário para o iPad encontrar o Mac
[ ] Acessibilidade — melhora teclado/mouse em alguns apps
```

Cada item deve ter:

- botão “Abrir Ajustes”;
- botão “Verificar novamente”;
- explicação curta;
- status.

---

## 13. Inicialização automática

### 13.1 Objetivo

O usuário não deve precisar abrir terminal nem iniciar Sunshine manualmente.

### 13.2 Opções

#### LaunchAgent por usuário

Instalar em:

```text
~/Library/LaunchAgents/com.macstream.host.sunshine.plist
```

Vantagens:

- roda no contexto do usuário;
- adequado para captura de tela;
- não exige daemon root para tudo.

Exemplo:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.macstream.host.sunshine</string>
    <key>ProgramArguments</key>
    <array>
      <string>/Applications/MacStream Host.app/Contents/Resources/sunshine/bin/sunshine</string>
      <string>/Users/USER/Library/Application Support/MacStreamHost/sunshine/sunshine.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/USER/Library/Logs/MacStreamHost/sunshine.out.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/USER/Library/Logs/MacStreamHost/sunshine.err.log</string>
  </dict>
</plist>
```

#### SMAppService

Para macOS moderno, preferir APIs nativas para Login Item e helper.

### 13.3 Controles no app

- iniciar com macOS;
- manter rodando em segundo plano;
- reiniciar se falhar;
- pausar quando em bateria;
- pausar em redes públicas;
- exigir confirmação para acesso remoto via internet.

---

## 14. Rede

### 14.1 Cenários suportados

1. Mesmo Wi-Fi/rede local.
2. Mac via Ethernet e iPad via Wi-Fi.
3. VPN mesh com Tailscale.
4. Hotspot.
5. Internet com port forwarding — avançado, não recomendado por padrão.

### 14.2 Diagnóstico

Exibir:

- IP local;
- hostname `.local`;
- interface ativa;
- SSID;
- tipo de rede;
- portas Sunshine abertas;
- teste de conexão local;
- teste via Tailscale, se instalado;
- firewall do macOS.

### 14.3 Segurança

Por padrão:

- não habilitar UPnP;
- não abrir porta externa automaticamente;
- Web UI apenas local, salvo modo avançado;
- exigir credenciais fortes;
- alertar sobre exposição pública.

### 14.4 Tailscale

Como seu caso de uso inclui acesso pela internet, o app deve ter integração de orientação com Tailscale:

- detectar se `tailscale` está instalado;
- detectar IP Tailscale;
- exibir instrução: “adicione este IP manualmente no Moonlight”;
- checar conectividade entre iPad e Mac;
- avisar se o Mac está offline no tailnet.

---

## 15. Pareamento com Moonlight

### 15.1 Fluxo atual

No Sunshine, o usuário abre Web UI, recebe PIN do Moonlight, insere PIN na tela de pareamento e nomeia o dispositivo.

### 15.2 Fluxo desejado

No MacStream Host:

1. Usuário clica “Parear novo dispositivo”.
2. App mostra instruções:
   - abra Moonlight no iPad;
   - toque no Mac;
   - anote o PIN;
   - digite abaixo.
3. Usuário digita PIN no app nativo.
4. App envia PIN ao Sunshine.
5. App confirma sucesso.

### 15.3 Implementação

Investigar se o Sunshine expõe endpoint local para pareamento via Web UI/API. Se não houver API estável:

- opção 1: abrir Web UI embutida em WKWebView na tela certa;
- opção 2: automatizar chamada HTTP interna usada pela Web UI;
- opção 3: propor patch upstream para API de pairing estável;
- opção 4: manter botão “Abrir painel de pareamento avançado”.

### 15.4 UX

Evitar:

```text
Abra https://localhost:47990, ignore certificado, faça login, vá em PIN...
```

Substituir por:

```text
Digite o PIN que apareceu no Moonlight
[ _ _ _ _ ]
[ Parear ]
```

---

## 16. Interface gráfica

### 16.1 Estrutura

Sidebar:

- Início
- Pareamento
- Qualidade
- Áudio
- Rede
- Permissões
- Inicialização
- Diagnóstico
- Avançado
- Sobre

### 16.2 Início

Cards:

- Servidor
- Moonlight
- Áudio
- Permissões
- Rede
- Última conexão
- Botão grande: Iniciar/Parar

### 16.3 Qualidade

Presets:

- iPad Pro — Equilibrado
- iPad Pro — Alta qualidade
- Baixa latência
- Rede remota/VPN
- Personalizado

Configurações:

- resolução;
- FPS;
- bitrate sugerido;
- codec preferido;
- HDR, se suportado;
- cursor;
- teclado;
- toque/caneta.

### 16.4 Áudio

- modo de captura;
- dispositivo selecionado;
- manter áudio no Mac;
- testar som;
- reparar áudio.

### 16.5 Diagnóstico

Lista de checagens:

- Sunshine executando;
- Web UI respondendo;
- config válida;
- apps.json válido;
- BlackHole instalado;
- áudio detectado;
- permissões;
- portas;
- rede;
- clientes pareados;
- logs recentes.

Botão:

```text
Gerar pacote de suporte
```

Gera zip com:

```text
diagnostics.json
sunshine.conf
apps.json
logs/
system_profile.txt
audio_devices.txt
network.txt
```

Com opção de mascarar dados sensíveis.

---

## 17. Presets recomendados para iPad Pro

### 17.1 Preset Equilibrado

```text
Resolução: 1920x1200 ou nativa equivalente
FPS: 60
Bitrate: 25–40 Mbps
Codec: HEVC quando disponível
Áudio: estéreo 2ch
```

### 17.2 Preset Alta qualidade local

```text
Resolução: 2560x1600 ou próxima do iPad
FPS: 60/120 se suportado de ponta a ponta
Bitrate: 50–100 Mbps
Codec: HEVC
Rede: Wi-Fi 6/6E ou Ethernet no host
```

### 17.3 Preset remoto via Tailscale

```text
Resolução: 1920x1080
FPS: 60
Bitrate: 10–25 Mbps
Codec: HEVC
Prioridade: estabilidade
```

### 17.4 Preset baixa latência

```text
Resolução: 1600x1000 ou 1920x1080
FPS: 60
Bitrate: 15–30 Mbps
Prioridade: menor delay
```

---

## 18. Compatibilidade Moonlight

### 18.1 Requisitos

O produto deve manter compatibilidade com o protocolo esperado pelo Moonlight. O objetivo não é criar cliente próprio, mas melhorar o host.

Garantir:

- descoberta local;
- pareamento;
- apps listados;
- streaming desktop;
- teclado;
- mouse/trackpad;
- áudio;
- reconexão;
- múltiplos clientes pareados;
- remoção de clientes.

### 18.2 Limitações conhecidas no macOS

- gamepads não suportados no host macOS pelo Sunshine atual;
- teclas Command não são encaminhadas diretamente pelo Moonlight; mapeamento com Right Option para Command pode ser necessário;
- permissões do macOS podem bloquear captura;
- áudio pode variar conforme rota escolhida;
- sleep/bloqueio do Mac pode interromper streaming;
- rede remota depende fortemente de VPN/latência/upload.

### 18.3 Comunicação honesta no app

Exemplo:

```text
Controle por teclado e trackpad: suportado
Áudio: suportado
Gamepad no host macOS: ainda não suportado pelo Sunshine
Tecla Command: use Right Option no Moonlight ou configure atalho
```

---

## 19. Segurança

### 19.1 Ameaças

- exposição acidental da Web UI;
- senha fraca;
- UPnP abrindo portas;
- acesso remoto não autorizado;
- logs com dados sensíveis;
- helper privilegiado abusável;
- driver de áudio instalado sem clareza.

### 19.2 Mitigações

- senha aleatória forte no setup;
- Web UI local por padrão;
- firewall status;
- UPnP desativado;
- avisos para port forwarding;
- usar XPC com comandos limitados;
- assinar e notarizar;
- logs mascarados;
- opção de revogar clientes pareados;
- reset de credenciais.

---

## 20. Estratégia de desenvolvimento

### 20.1 Fase 0 — Discovery técnico

Objetivo: validar comandos, caminhos, permissões e automações.

Entregáveis:

- script que instala/verifica Sunshine;
- script que instala/verifica BlackHole;
- script que gera config;
- script que inicia Sunshine;
- script que valida Web UI;
- script que lista dispositivos de áudio;
- roteiro manual de pareamento.

Confiança esperada: 0,85.

### 20.2 Fase 1 — MVP funcional

Objetivo: app SwiftUI simples que controla Sunshine.

Escopo:

- dashboard;
- start/stop;
- status;
- abrir Web UI;
- configurar `audio_sink`;
- verificar BlackHole;
- guiar permissões;
- LaunchAgent;
- logs.

Não precisa ainda:

- instalar driver custom;
- pareamento nativo;
- auto-repair avançado;
- UI ultra refinada.

Confiança esperada: 0,80.

### 20.3 Fase 2 — Instalador e onboarding

Objetivo: experiência de usuário final.

Escopo:

- DMG;
- assinatura/notarização;
- onboarding;
- instalador de BlackHole;
- reset;
- diagnóstico;
- presets;
- documentação.

Confiança esperada: 0,78.

### 20.4 Fase 3 — Produto polido

Objetivo: “comercial”.

Escopo:

- driver custom baseado em BlackHole;
- pairing dentro do app;
- integração Tailscale;
- update automático;
- crash reporting opt-in;
- pacote de suporte;
- site;
- releases públicas.

Confiança esperada: 0,72.

---

## 21. Roadmap técnico detalhado

### Milestone 1 — CLI de orquestração

Criar `macstreamctl`.

Comandos:

```bash
macstreamctl doctor
macstreamctl install-sunshine
macstreamctl install-audio
macstreamctl configure
macstreamctl start
macstreamctl stop
macstreamctl restart
macstreamctl status
macstreamctl logs
macstreamctl reset
```

Por que começar por CLI?

- facilita debug;
- GUI chama CLI/serviço;
- simplifica automação;
- acelera MVP.

### Milestone 2 — App SwiftUI

Conectar GUI ao controller.

Views:

- HomeView;
- OnboardingView;
- PermissionsView;
- AudioView;
- NetworkView;
- PairingView;
- DiagnosticsView;
- SettingsView;
- AboutView.

### Milestone 3 — Helper privilegiado

Funções permitidas:

```text
installAudioDriver()
uninstallAudioDriver()
restartCoreAudio()
installLaunchAgent()
removeLaunchAgent()
repairPermissionsHints()
```

### Milestone 4 — Empacotamento

- DMG;
- GitHub Actions;
- build universal;
- notarização;
- release notes;
- checksums;
- SBOM.

### Milestone 5 — Forks/patches

Se necessário:

- patch Sunshine para API de pairing;
- patch Sunshine para macOS-first config;
- patch BlackHole para branding;
- patch BlackHole para mirror/hidden device.

---

## 22. Estrutura técnica sugerida do repositório

```text
MacStreamHost/
  README.md
  LICENSE
  NOTICE.md
  THIRD_PARTY_NOTICES.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md

  Sources/
    MacStreamHostApp/
      App/
      Views/
      ViewModels/
      Services/
      Models/
      Resources/

    MacStreamCore/
      Sunshine/
      Audio/
      Permissions/
      Network/
      Diagnostics/
      LaunchAgent/
      Security/

    MacStreamHelper/
      XPC/
      PrivilegedOperations/

    macstreamctl/
      main.swift

  Resources/
    sunshine/
      bin/
      licenses/
    audio/
      packages/
      licenses/
    templates/
      sunshine.conf.template
      apps.json.template
      launchagent.plist.template

  scripts/
    build.sh
    package_dmg.sh
    notarize.sh
    install_blackhole.sh
    uninstall_blackhole.sh
    generate_notice.sh

  docs/
    architecture.md
    audio.md
    sunshine.md
    moonlight.md
    troubleshooting.md
    gpl-compliance.md
    release-process.md

  .github/
    workflows/
      ci.yml
      release.yml
```

---

## 23. Config Manager

Responsabilidades:

- gerar `sunshine.conf`;
- preservar mudanças do usuário;
- aplicar presets;
- validar schema mínimo;
- fazer backup antes de alterar;
- detectar conflitos com instalação Sunshine existente.

Estratégia:

```text
sunshine.conf
sunshine.conf.backup-2026-05-12-103000
apps.json
apps.json.backup-2026-05-12-103000
```

Não sobrescrever silenciosamente.

---

## 24. Service Manager

Responsabilidades:

- iniciar processo Sunshine;
- parar processo;
- reiniciar;
- checar PID;
- checar porta 47990;
- checar logs;
- instalar LaunchAgent;
- remover LaunchAgent.

Estados:

```swift
enum ServerState {
    case notInstalled
    case stopped
    case starting
    case running
    case degraded
    case failed(reason: String)
}
```

---

## 25. Audio Manager

Responsabilidades:

- listar dispositivos CoreAudio;
- detectar BlackHole;
- detectar MacStream Audio;
- validar sample rate/canais;
- setar rota de captura;
- reiniciar CoreAudio via helper;
- criar/remover Multi-Output Device, se tecnicamente viável via APIs/scripts;
- orientar usuário quando operação exigir Audio MIDI Setup.

Estados:

```swift
enum AudioState {
    case nativeCaptureAvailable
    case blackHoleAvailable
    case driverMissing
    case misconfigured
    case permissionMissing
    case unknown
}
```

---

## 26. Permission Manager

Responsabilidades:

- detectar status onde possível;
- abrir painéis corretos do macOS;
- explicar permissões;
- revalidar após usuário conceder;
- bloquear “finalizar setup” se permissão crítica ausente.

Atenção: algumas permissões do macOS não têm API pública perfeita para leitura direta; nesses casos, usar teste prático, por exemplo tentar iniciar captura ou checar erro do Sunshine.

---

## 27. Network Manager

Responsabilidades:

- listar interfaces;
- identificar IP local;
- detectar Tailscale;
- detectar firewall;
- testar porta local;
- exibir instruções para Moonlight;
- sugerir conexão manual.

Comandos possíveis:

```bash
ifconfig
networksetup -listallhardwareports
lsof -iTCP -sTCP:LISTEN
```

Preferir Network.framework quando possível.

---

## 28. Diagnostics

### 28.1 Doctor checks

```text
[✓] macOS version >= 14.2
[✓] Apple Silicon detected
[✓] Sunshine binary exists
[✓] Sunshine config exists
[✓] Sunshine process running
[✓] Web UI reachable
[✓] Desktop app configured
[✓] Screen Recording permission likely OK
[✓] Microphone permission likely OK
[✓] Audio device available
[✓] Port 47990 listening
[✓] iPad/Moonlight should find host on local network
```

### 28.2 JSON output

```json
{
  "appVersion": "0.1.0",
  "macOS": "15.x",
  "arch": "arm64",
  "sunshine": {
    "installed": true,
    "version": "x.y.z",
    "running": true,
    "webUI": true,
    "configPath": "...",
    "audioSink": "BlackHole 2ch"
  },
  "audio": {
    "blackHoleInstalled": true,
    "nativeCapture": "unknown",
    "sampleRate": 48000
  },
  "network": {
    "localIP": "192.168.1.10",
    "tailscaleIP": "100.x.y.z",
    "ports": {
      "47990": "listening"
    }
  },
  "permissions": {
    "screenRecording": "granted_or_probably_granted",
    "microphone": "granted_or_probably_granted"
  }
}
```

---

## 29. UX de erros

### 29.1 Erro: Sunshine não inicia

```text
Não consegui iniciar o servidor Sunshine.

Possíveis causas:
1. Permissão de gravação de tela ausente.
2. Porta em uso.
3. Configuração inválida.
4. Binário danificado.

[Reparar automaticamente]
[Ver logs]
[Reinstalar Sunshine]
```

### 29.2 Erro: Moonlight não encontra Mac

```text
O iPad não encontrou este Mac automaticamente.

Tente:
1. Confirmar que ambos estão na mesma rede ou Tailscale.
2. Adicionar manualmente este IP no Moonlight:
   192.168.1.10
3. Verificar firewall do macOS.

[Testar rede]
[Copiar IP]
```

### 29.3 Erro: sem áudio

```text
O vídeo está funcionando, mas o áudio não.

Vamos verificar:
[✓] Streaming de áudio ativo
[!] Dispositivo BlackHole não detectado
[ ] Permissão de microfone
[ ] Saída de áudio do macOS

[Reparar áudio]
```

---

## 30. Build e distribuição

### 30.1 Build local

```bash
git clone https://github.com/seu-org/macstream-host
cd macstream-host
./scripts/bootstrap.sh
./scripts/build.sh
```

### 30.2 Assinatura

Usar Apple Developer ID:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: ..." \
  "build/MacStream Host.app"
```

### 30.3 Notarização

```bash
xcrun notarytool submit MacStreamHost.dmg \
  --keychain-profile "AC_PROFILE" \
  --wait
```

### 30.4 Staple

```bash
xcrun stapler staple MacStreamHost.dmg
```

### 30.5 Releases

Cada release deve incluir:

- DMG;
- checksum;
- source tarball;
- changelog;
- SBOM;
- license notices;
- scripts de build correspondentes.

---

## 31. CI/CD

GitHub Actions:

```yaml
name: Release macOS

on:
  push:
    tags:
      - "v*"

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bootstrap
        run: ./scripts/bootstrap.sh
      - name: Build
        run: ./scripts/build.sh
      - name: Package
        run: ./scripts/package_dmg.sh
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: MacStreamHost
          path: dist/*.dmg
```

Notarização exigirá secrets.

---

## 32. Open source governance

### 32.1 Repositório público

Arquivos obrigatórios:

- README;
- LICENSE;
- NOTICE;
- CONTRIBUTING;
- SECURITY;
- CODE_OF_CONDUCT;
- docs de build.

### 32.2 Créditos

README deve afirmar:

```text
MacStream Host is built on top of Sunshine and BlackHole.
Sunshine is developed by LizardByte.
BlackHole is developed by Existential Audio.
This project is licensed under GPL-3.0-or-later.
```

### 32.3 Contribuições

Definir:

- DCO ou CLA?
- estilo de commit;
- branch strategy;
- labels;
- roadmap público.

Para simplicidade, usar DCO:

```text
Signed-off-by: Name <email>
```

---

## 33. Decisões técnicas críticas

### 33.1 Fork vs wrapper

Recomendação inicial:

```text
Wrapper + empacotamento + configuração.
```

Motivo:

- menor risco;
- entrega mais rápida;
- permite acompanhar upstream;
- reduz manutenção.

Migrar para fork quando:

- precisar API de pairing;
- precisar mudar comportamento interno;
- precisar melhorar suporte macOS;
- precisar integração mais profunda de áudio.

### 33.2 BlackHole oficial vs custom

MVP:

```text
BlackHole 2ch oficial
```

Produto:

```text
MacStream Audio 2ch baseado em BlackHole
```

### 33.3 App nativo vs Electron/Tauri

Recomendação:

```text
SwiftUI nativo
```

Motivo:

- integração macOS;
- permissões;
- login items;
- helper;
- menor peso;
- aparência comercial;
- melhor confiança do usuário.

### 33.4 Web UI do Sunshine

Não remover inicialmente. O app deve ter:

- modo simples próprio;
- botão “Abrir configurações avançadas do Sunshine”.

---

## 34. Prompt para Lovable/Antigravity/Codex gerar a base do projeto

```text
Crie um projeto macOS nativo chamado MacStream Host, em Swift + SwiftUI, licenciado sob GPL-3.0-or-later, cujo objetivo é funcionar como uma camada de produto comercial/open-source para orquestrar Sunshine e BlackHole no macOS, tornando simples transformar um Mac em host compatível com Moonlight.

O projeto deve conter:

1. App SwiftUI com sidebar:
   - Início
   - Pareamento
   - Qualidade
   - Áudio
   - Rede
   - Permissões
   - Inicialização
   - Diagnóstico
   - Avançado
   - Sobre

2. Camada MacStreamCore com serviços:
   - SunshineService
   - ConfigManager
   - AudioManager
   - PermissionManager
   - NetworkManager
   - LaunchAgentManager
   - DiagnosticsService

3. CLI macstreamctl com comandos:
   - doctor
   - configure
   - start
   - stop
   - restart
   - status
   - logs
   - reset

4. Templates:
   - sunshine.conf.template
   - apps.json.template
   - launchagent.plist.template

5. O app deve assumir que o binário Sunshine será colocado em:
   MacStream Host.app/Contents/Resources/sunshine/bin/sunshine

6. O app deve gerar configuração em:
   ~/Library/Application Support/MacStreamHost/sunshine/

7. O app deve criar logs em:
   ~/Library/Logs/MacStreamHost/

8. O app deve ter uma tela de diagnóstico que execute checks simulados/implementáveis:
   - versão do macOS
   - arquitetura
   - presença do Sunshine
   - processo rodando
   - porta 47990 respondendo
   - presença de BlackHole 2ch
   - permissões prováveis
   - IP local
   - Tailscale detectado
   - existência de config
   - existência de apps.json

9. O app deve ter código preparado para, no futuro, usar um helper XPC privilegiado, mas no MVP pode deixar protocolos e stubs.

10. O código deve ser modular, documentado, seguro e pronto para evolução.

11. Incluir README.md, LICENSE, NOTICE.md, docs/architecture.md e docs/gpl-compliance.md.

12. Não usar dependências proprietárias. Manter tudo compatível com GPL-3.0-or-later.
```

---

## 35. Prompt para gerar documentação inicial do repositório

```text
Crie a documentação inicial de produto e engenharia para o projeto MacStream Host.

Contexto:
MacStream Host é um aplicativo macOS open source GPL-3.0-or-later que consolida Sunshine + BlackHole para permitir que usuários usem seus Macs via Moonlight, especialmente a partir de iPad com teclado/trackpad.

Objetivo:
Transformar uma configuração técnica e fragmentada em um produto macOS amigável, com instalador, interface gráfica, onboarding, configuração automática, inicialização automática, diagnóstico, presets para iPad e compatibilidade total com Moonlight.

Documentos a criar:
1. README.md
2. docs/PRD.md
3. docs/architecture.md
4. docs/audio-routing.md
5. docs/sunshine-integration.md
6. docs/moonlight-compatibility.md
7. docs/gpl-compliance.md
8. docs/release-process.md
9. docs/troubleshooting.md

Inclua:
- visão do produto
- personas
- fluxos de usuário
- arquitetura
- estratégia GPL
- integração Sunshine
- integração BlackHole
- permissões macOS
- LaunchAgent
- diagnóstico
- roadmap
- riscos
- milestones
- critérios de aceite
```

---

## 36. Critérios de aceite do MVP

O MVP pode ser considerado pronto quando:

1. Usuário instala `MacStream Host.app`.
2. App detecta/instala Sunshine.
3. App detecta/instala BlackHole 2ch ou instrui corretamente.
4. App gera `sunshine.conf`.
5. App gera `apps.json` com Desktop.
6. App inicia Sunshine.
7. App mostra status online.
8. Moonlight no iPad encontra o host na rede local.
9. Usuário consegue parear.
10. Usuário consegue abrir Desktop.
11. Teclado e mouse/trackpad funcionam.
12. Áudio chega no iPad.
13. App inicia Sunshine automaticamente após login.
14. App mostra logs e diagnóstico.
15. App permite reset/desinstalação limpa.

---

## 37. Riscos

| Risco | Impacto | Mitigação |
|---|---:|---|
| Sunshine macOS experimental | Alto | limitar escopo, testar em versões macOS, contribuir upstream |
| Gamepad não suportado no macOS | Médio | comunicar claramente |
| Permissões macOS instáveis | Alto | onboarding guiado + diagnóstico |
| Áudio via BlackHole confuso | Alto | Audio Manager + presets |
| Multi-Output Device limitado | Médio | preferir captura nativa quando possível |
| Fork difícil de manter | Médio | wrapper primeiro |
| Notarização com driver/helper | Alto | CI dedicado e Apple Developer ID |
| Exposição de Web UI | Alto | local por padrão |
| Conflito com Sunshine existente | Médio | config isolada |
| Usuário remoto via internet | Alto | recomendar Tailscale |

---

## 38. Ordem recomendada de execução

1. Criar repo público GPL.
2. Criar documentação e README.
3. Criar CLI `macstreamctl doctor`.
4. Criar geração de config Sunshine.
5. Criar controle start/stop.
6. Criar app SwiftUI simples.
7. Criar LaunchAgent.
8. Criar detecção de BlackHole.
9. Criar onboarding.
10. Criar diagnóstico.
11. Criar DMG.
12. Testar em Mac Apple Silicon.
13. Testar Moonlight no iPad local.
14. Testar Moonlight via Tailscale.
15. Criar release beta.

---

## 39. Próximas decisões

Antes de iniciar código, decidir:

1. Nome final do produto.
2. Se o repo ficará em conta pessoal ou organização.
3. Se o app usará Sunshine oficial ou fork desde o dia 1.
4. Se BlackHole será oficial ou customizado.
5. Se haverá assinatura Apple Developer já no beta.
6. Se o foco inicial será apenas Apple Silicon.
7. Se terá suporte a Intel Mac no MVP.
8. Se pareamento nativo entra no MVP ou fica para fase 2.

---

## 40. Conclusão

O projeto é tecnicamente viável e faz sentido como produto open source GPL: ele resolve uma dor real, especialmente para usuários que querem usar Mac pelo iPad via Moonlight, mas não querem lidar com instalação fragmentada, Web UI técnica, driver de áudio separado, permissões e diagnóstico manual.

A melhor estratégia é começar como **orquestrador macOS-first** de Sunshine + BlackHole, com interface nativa, onboarding, configuração e diagnóstico. Isso entrega valor rapidamente sem assumir desde o início a manutenção pesada de forks profundos.

A evolução natural é transformar o produto em uma distribuição macOS polida para Moonlight hosting, com driver de áudio customizado, pareamento integrado, presets para iPad e experiência de suporte profissional.

---

## 41. Fontes base

- Sunshine — https://github.com/LizardByte/Sunshine
- Sunshine docs — https://docs.lizardbyte.dev/projects/sunshine/
- BlackHole — https://github.com/ExistentialAudio/BlackHole
- GNU GPL v3 — https://www.gnu.org/licenses/gpl-3.0.html
