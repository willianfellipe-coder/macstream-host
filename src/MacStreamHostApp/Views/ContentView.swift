// SPDX-License-Identifier: GPL-3.0-or-later

import MacStreamCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case setup
    case sunshine
    case audio
    case network
    case moonlight
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .setup: return "Setup"
        case .sunshine: return "Sunshine"
        case .audio: return "Audio"
        case .network: return "Network"
        case .moonlight: return "Moonlight"
        case .diagnostics: return "Diagnostics"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .setup: return "checklist"
        case .sunshine: return "sun.max"
        case .audio: return "speaker.wave.2"
        case .network: return "network"
        case .moonlight: return "moon"
        case .diagnostics: return "stethoscope"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("MacStream Host")
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardView()
            case .setup:
                SetupView()
            case .sunshine:
                SunshineView()
            case .audio:
                AudioView()
            case .network:
                NetworkView()
            case .moonlight:
                MoonlightView()
            case .diagnostics:
                DiagnosticsView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Dashboard", subtitle: "Status inicial do host e próximo passo recomendado.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                StatusPanel(
                    title: "Sunshine",
                    value: appState.dashboard.sunshineStatus.state.displayName,
                    detail: appState.dashboard.sunshineStatus.webUIReachable ? "Web UI acessível" : "Web UI ainda não validada",
                    status: appState.dashboard.sunshineStatus.state.checkStatus
                )

                StatusPanel(
                    title: "BlackHole",
                    value: appState.dashboard.blackHoleStatus.displayName,
                    detail: "Fallback de áudio oficial para o MVP",
                    status: appState.dashboard.blackHoleStatus.checkStatus
                )

                StatusPanel(
                    title: "Permissões macOS",
                    value: appState.dashboard.permissionsStatus.aggregateStatus.displayName,
                    detail: appState.dashboard.permissionsStatus.criticalPermissionsSatisfied ? "Críticas OK" : "Requer validação guiada",
                    status: appState.dashboard.permissionsStatus.aggregateStatus
                )

                StatusPanel(
                    title: "Rede",
                    value: appState.dashboard.networkStatus.aggregateStatus.displayName,
                    detail: appState.dashboard.networkStatus.localAddresses.first ?? "Sem IP local detectado",
                    status: appState.dashboard.networkStatus.aggregateStatus
                )
            }

            GroupBox("Próximo passo recomendado") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.forward.circle")
                        .foregroundStyle(Color.accentColor)
                    Text(appState.dashboard.recommendedNextStep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label("Atualizar diagnóstico", systemImage: "arrow.clockwise")
                }

                Spacer()
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Setup", subtitle: "Checklist seguro para preparar Sunshine, áudio, rede e pareamento.") {
            VStack(spacing: 10) {
                ForEach(appState.setupChecklist) { item in
                    HStack(alignment: .top, spacing: 12) {
                        StatusIcon(status: item.status)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.detail)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )
                }
            }

            GroupBox("Permissões macOS") {
                VStack(spacing: 10) {
                    ForEach(appState.dashboard.permissionsStatus.checks) { permission in
                        HStack(alignment: .top, spacing: 12) {
                            StatusIcon(status: permission.status.checkStatus)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(permission.id.displayName)
                                    .font(.headline)
                                Text(permission.detail)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await appState.openSettings(for: permission.id) }
                            } label: {
                                Label("Abrir Ajustes", systemImage: "gearshape")
                            }
                        }
                        .padding(10)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
            }
        }
    }
}

struct SunshineView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Sunshine", subtitle: "Controle seguro do runtime Sunshine sem esconder a Web UI avançada.") {
            StatusPanel(
                title: "Servidor",
                value: appState.dashboard.sunshineStatus.state.displayName,
                detail: sunshineStatusDetail,
                status: appState.dashboard.sunshineStatus.state.checkStatus
            )

            GroupBox("Ações seguras") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await appState.createDefaultSunshineConfiguration() }
                        } label: {
                            Label("Gerar config", systemImage: "doc.badge.plus")
                        }

                        Button {
                            Task { await appState.startSunshine() }
                        } label: {
                            Label("Iniciar", systemImage: "play.fill")
                        }
                        .disabled(startDisabled)

                        Button {
                            Task { await appState.stopSunshine() }
                        } label: {
                            Label("Parar", systemImage: "stop.fill")
                        }
                        .disabled(stopDisabled)

                        Button {
                            Task { await appState.restartSunshine() }
                        } label: {
                            Label("Reiniciar", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(restartDisabled)

                        Button {
                            Task { await appState.openSunshineWebUI() }
                        } label: {
                            Label("Web UI", systemImage: "safari")
                        }

                        Spacer()

                        Button {
                            Task { await appState.refresh() }
                        } label: {
                            Label("Atualizar", systemImage: "arrow.clockwise")
                        }
                    }

                    Text(actionGuidance)
                        .foregroundStyle(.secondary)

                    if let message = appState.lastSunshineOperationMessage {
                        Label(message, systemImage: messageIcon)
                            .foregroundStyle(messageStyle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Configuração isolada") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.configurationManager.configDirectory.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text("O app usa esse diretório para evitar conflito com uma instalação Sunshine existente.")
                        .foregroundStyle(.secondary)
                    Text("Logs: \(appState.runtimeSettings.logDirectoryPath)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sunshineStatus: SunshineStatus {
        appState.dashboard.sunshineStatus
    }

    private var sunshineStatusDetail: String {
        if let processID = sunshineStatus.ownedProcessID {
            return "Controlado pelo MacStream Host, PID \(processID)."
        }

        if sunshineStatus.state == .running {
            return "Processo Sunshine externo detectado; o app não irá pará-lo."
        }

        if let binaryPath = sunshineStatus.binaryPath {
            return "Binário detectado em \(binaryPath)."
        }

        return "Sunshine ainda não foi detectado neste Mac."
    }

    private var actionGuidance: String {
        if appState.isSunshineOperationInProgress {
            return "Executando ação e atualizando diagnóstico..."
        }

        if sunshineStatus.state == .running && sunshineStatus.ownedProcessID == nil {
            return "Há um Sunshine externo rodando. Start/stop ficam bloqueados para evitar conflito."
        }

        if sunshineStatus.ownedProcessID == nil {
            return "Gere a configuração isolada antes de iniciar o Sunshine pelo MacStream Host."
        }

        return "Somente o processo owned pelo MacStream Host pode ser parado ou reiniciado."
    }

    private var startDisabled: Bool {
        appState.isSunshineOperationInProgress
            || sunshineStatus.state == .running
            || sunshineStatus.state == .notInstalled
    }

    private var stopDisabled: Bool {
        appState.isSunshineOperationInProgress || sunshineStatus.ownedProcessID == nil
    }

    private var restartDisabled: Bool {
        appState.isSunshineOperationInProgress || sunshineStatus.ownedProcessID == nil
    }

    private var messageIcon: String {
        guard let message = appState.lastSunshineOperationMessage else { return "info.circle" }
        return message.localizedCaseInsensitiveContains("failed")
            || message.localizedCaseInsensitiveContains("erro")
            || message.localizedCaseInsensitiveContains("não")
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle.fill"
    }

    private var messageStyle: Color {
        messageIcon == "checkmark.circle.fill" ? .green : .orange
    }
}

struct AudioView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Audio", subtitle: "Rotas de captura planejadas: nativa do macOS primeiro, BlackHole 2ch como fallback.") {
            StatusPanel(
                title: "BlackHole 2ch",
                value: appState.dashboard.blackHoleStatus.displayName,
                detail: "Nenhum driver será instalado automaticamente nesta fase.",
                status: appState.dashboard.blackHoleStatus.checkStatus
            )

            GroupBox("Modo de captura inicial") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Modo atual: \(appState.runtimeSettings.audioCaptureMode.displayName)")
                        .font(.headline)
                    HStack {
                        Button {
                            Task { await appState.updateAudioCaptureMode(.nativeSystemAudio) }
                        } label: {
                            Label("Usar nativo", systemImage: "speaker.wave.2")
                        }

                        Button {
                            Task { await appState.updateAudioCaptureMode(.blackHole2ch) }
                        } label: {
                            Label("Usar BlackHole", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                    Text("Ao gerar a configuração isolada, o app grava `audio_sink = BlackHole 2ch` apenas quando esse modo estiver selecionado.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct NetworkView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Network", subtitle: "Diagnóstico local de IP, portas comuns do Sunshine e orientação para VPN mesh.") {
            GroupBox("Endereços") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.dashboard.networkStatus.localAddresses, id: \.self) { address in
                        Label(address, systemImage: "network")
                    }

                    if let tailscale = appState.dashboard.networkStatus.tailscaleAddress {
                        Label(tailscale, systemImage: "lock.shield")
                    } else {
                        Text("Tailscale não detectado.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 10) {
                ForEach(appState.dashboard.networkStatus.portChecks) { check in
                    HStack {
                        StatusIcon(status: check.status)
                        Text("\(check.name) \(check.protocolKind.rawValue.uppercased())/\(check.port)")
                        Spacer()
                        Text(check.detail)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
            }
        }
    }
}

struct MoonlightView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Moonlight", subtitle: "Guia de pareamento sem depender de API não documentada do Sunshine.") {
            GroupBox("Acesso rápido") {
                HStack {
                    Button {
                        Task { await appState.openSunshineWebUI() }
                    } label: {
                        Label("Abrir Web UI do Sunshine", systemImage: "safari")
                    }

                    if let firstAddress = appState.dashboard.networkStatus.localAddresses.first {
                        Text(firstAddress)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Spacer()
                }
            }

            VStack(spacing: 10) {
                ForEach(appState.pairingGuide.pairingSteps()) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(step.id)")
                            .font(.headline)
                            .frame(width: 28, height: 28)
                            .background(.quaternary)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
            }
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Diagnostics", subtitle: "Health check inicial com diagnósticos locais seguros e regras testáveis.") {
            StatusPanel(
                title: "Resultado",
                value: appState.healthCheckResult.status.displayName,
                detail: appState.healthCheckResult.recommendedNextStep,
                status: status(for: appState.healthCheckResult.status)
            )

            VStack(spacing: 10) {
                ForEach(appState.healthCheckResult.checks) { check in
                    HStack(alignment: .top, spacing: 12) {
                        StatusIcon(status: check.status)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.title)
                                .font(.headline)
                            Text(check.detail)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }
            }
        }
    }

    private func status(for result: HealthCheckResultStatus) -> CheckStatus {
        switch result {
        case .pass: return .pass
        case .degraded: return .warning
        case .failing: return .fail
        case .unknown: return .unknown
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sunshineBinaryPath = ""
    @State private var configDirectoryPath = ""
    @State private var logDirectoryPath = ""
    @State private var audioCaptureMode: AudioCaptureMode = .blackHole2ch
    @State private var didLoadSettings = false
    @State private var pendingConfirmation: SettingsConfirmation?

    var body: some View {
        PageContainer(title: "Settings", subtitle: "Preferências locais usadas pelo app e pelo CLI.") {
            GroupBox("Paths") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Sunshine binary path", text: $sunshineBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Config directory", text: $configDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Log directory", text: $logDirectoryPath)
                        .textFieldStyle(.roundedBorder)

                    Picker("Áudio", selection: $audioCaptureMode) {
                        Text(AudioCaptureMode.nativeSystemAudio.displayName).tag(AudioCaptureMode.nativeSystemAudio)
                        Text(AudioCaptureMode.blackHole2ch.displayName).tag(AudioCaptureMode.blackHole2ch)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Button {
                            Task {
                                await appState.saveSettings(
                                    sunshineBinaryPath: sunshineBinaryPath,
                                    configDirectoryPath: configDirectoryPath,
                                    logDirectoryPath: logDirectoryPath,
                                    audioCaptureMode: audioCaptureMode
                                )
                            }
                        } label: {
                            Label("Salvar preferências", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            loadSettingsFields()
                        } label: {
                            Label("Recarregar", systemImage: "arrow.clockwise")
                        }

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("LaunchAgent") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status atual: \(launchAgentStatusText(appState.healthCheckResult.checks.first(where: { $0.id == .launchAgent })?.status ?? .unknown))")
                        .font(.headline)
                    HStack {
                        Button {
                            pendingConfirmation = .launchAgent(.install)
                        } label: {
                            Label("Instalar", systemImage: "plus.circle")
                        }

                        Button {
                            pendingConfirmation = .launchAgent(.load)
                        } label: {
                            Label("Carregar", systemImage: "play.circle")
                        }

                        Button {
                            pendingConfirmation = .launchAgent(.unload)
                        } label: {
                            Label("Descarregar", systemImage: "pause.circle")
                        }

                        Button(role: .destructive) {
                            pendingConfirmation = .launchAgent(.remove)
                        } label: {
                            Label("Remover", systemImage: "trash")
                        }
                    }
                    Text("Essas ações operam apenas o LaunchAgent `com.macstream.host.sunshine` do usuário atual.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Reset soft") {
                VStack(alignment: .leading, spacing: 12) {
                    Button(role: .destructive) {
                        pendingConfirmation = .softReset
                    } label: {
                        Label("Executar reset soft", systemImage: "arrow.counterclockwise")
                    }
                    Text("Para somente o Sunshine owned pelo MacStream Host, remove o LaunchAgent do app e arquiva a configuração isolada. Não remove Sunshine, BlackHole ou configurações externas.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Perfil recomendado") {
                VStack(alignment: .leading, spacing: 8) {
                    let profile = StreamingQualityProfile.balancedIPad.recommendedConfiguration
                    Text(StreamingQualityProfile.balancedIPad.displayName)
                        .font(.headline)
                    Text("\(profile.width)x\(profile.height), \(profile.framesPerSecond) FPS, \(profile.bitrateMbps) Mbps, \(profile.codec.rawValue.uppercased())")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Logs") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.logManager.logDirectoryURL.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        let outputURL = appState.logManager.logDirectoryURL
                            .appendingPathComponent("SupportBundles", isDirectory: true)
                        Task { _ = await appState.writeSupportBundle(to: outputURL) }
                    } label: {
                        Label("Exportar pacote de suporte", systemImage: "archivebox")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = appState.lastOperationMessage {
                Label(message, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if didLoadSettings == false {
                loadSettingsFields()
                didLoadSettings = true
            }
        }
        .confirmationDialog(
            "Confirmar ação",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingConfirmation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation = pendingConfirmation {
                Button(confirmation.confirmButtonTitle, role: confirmation.role) {
                    pendingConfirmation = nil
                    Task { await runConfirmedAction(confirmation) }
                }
            }

            Button("Cancelar", role: .cancel) {
                pendingConfirmation = nil
            }
        } message: {
            if let confirmation = pendingConfirmation {
                Text(confirmation.message)
            } else {
                Text("")
            }
        }
    }

    private func loadSettingsFields() {
        sunshineBinaryPath = appState.runtimeSettings.sunshineBinaryPath ?? ""
        configDirectoryPath = appState.runtimeSettings.configDirectoryPath
        logDirectoryPath = appState.runtimeSettings.logDirectoryPath
        audioCaptureMode = appState.runtimeSettings.audioCaptureMode
    }

    private func launchAgentStatusText(_ status: CheckStatus) -> String {
        status.displayName
    }

    private func runConfirmedAction(_ confirmation: SettingsConfirmation) async {
        switch confirmation {
        case .launchAgent(.install):
            await appState.installLaunchAgent()
        case .launchAgent(.load):
            await appState.loadLaunchAgent()
        case .launchAgent(.unload):
            await appState.unloadLaunchAgent()
        case .launchAgent(.remove):
            await appState.removeLaunchAgent()
        case .softReset:
            await appState.softReset()
        }
    }

    private enum LaunchAgentUIAction {
        case install
        case load
        case unload
        case remove
    }

    private enum SettingsConfirmation {
        case launchAgent(LaunchAgentUIAction)
        case softReset

        var confirmButtonTitle: String {
            switch self {
            case .launchAgent(.install): return "Instalar LaunchAgent"
            case .launchAgent(.load): return "Carregar LaunchAgent"
            case .launchAgent(.unload): return "Descarregar LaunchAgent"
            case .launchAgent(.remove): return "Remover LaunchAgent"
            case .softReset: return "Executar reset soft"
            }
        }

        var message: String {
            switch self {
            case .launchAgent(.install):
                return "O app vai gravar um plist validado em ~/Library/LaunchAgents para o usuário atual. Nenhuma senha de administrador será solicitada."
            case .launchAgent(.load):
                return "O app vai carregar o LaunchAgent no domínio do usuário atual usando launchctl. Isso pode iniciar o Sunshine com a configuração isolada."
            case .launchAgent(.unload):
                return "O app vai descarregar apenas o LaunchAgent com o label com.macstream.host.sunshine."
            case .launchAgent(.remove):
                return "O app vai remover apenas o plist com.macstream.host.sunshine.plist criado pelo MacStream Host."
            case .softReset:
                return "O app vai parar somente o Sunshine owned pelo MacStream Host, remover o LaunchAgent do app e arquivar a configuração isolada."
            }
        }

        var role: ButtonRole? {
            switch self {
            case .launchAgent(.remove), .softReset:
                return .destructive
            default:
                return nil
            }
        }
    }
}

struct PageContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct StatusPanel: View {
    let title: String
    let value: String
    let detail: String
    let status: CheckStatus

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    StatusIcon(status: status)
                }

                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

struct StatusIcon: View {
    let status: CheckStatus

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(status.displayName)
    }

    private var symbol: String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        case .unknown: return .secondary
        }
    }
}
