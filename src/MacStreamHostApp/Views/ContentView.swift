// SPDX-License-Identifier: GPL-3.0-or-later

import MacStreamCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case setup
    case dependencies
    case sunshine
    case audio
    case network
    case moonlight
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Remote Work"
        case .setup: return "Setup"
        case .dependencies: return "Components"
        case .sunshine: return "Advanced Engines"
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
        case .dependencies: return "shippingbox"
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
            case .dependencies:
                DependenciesView()
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

    private var pairingAddresses: [String] {
        var addresses = appState.dashboard.networkStatus.localAddresses
        if let tailscale = appState.dashboard.networkStatus.tailscaleAddress {
            addresses.append(tailscale)
        }
        return addresses
    }

    var body: some View {
        PageContainer(title: "Remote Work", subtitle: "Prepare este Mac para uso remoto produtivo a partir do iPad ou outro cliente Moonlight.") {
            RemoteWorkBanner(
                report: appState.remoteWorkSession,
                pairingAddresses: pairingAddresses,
                onCopyAddress: { address in appState.copyPairingAddress(address) }
            )

            GroupBox("Ações principais") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await appState.prepareRemoteWorkMode() }
                        } label: {
                            Label("Preparar MacStream", systemImage: "wand.and.stars")
                        }

                        Button {
                            Task { await appState.requestMacOSPermissions() }
                        } label: {
                            Label("Permissões", systemImage: "hand.raised")
                        }

                        Button {
                            Task { await appState.startRemoteWorkMode() }
                        } label: {
                            Label("Iniciar modo remoto", systemImage: "play.fill")
                        }
                        .disabled(appState.remoteWorkSession.state == .running)

                        Button {
                            Task { await appState.openSunshineWebUI() }
                        } label: {
                            Label("Parear dispositivo", systemImage: "ipad.and.arrow.forward")
                        }

                        Button {
                            Task { await appState.lockHostForPrivacy() }
                        } label: {
                            Label("Bloquear host", systemImage: "lock.display")
                        }

                        Button {
                            Task { await appState.stopRemoteWorkMode() }
                        } label: {
                            Label("Parar", systemImage: "stop.fill")
                        }

                        Button {
                            Task { _ = await appState.exportRemoteWorkSupportBundle() }
                        } label: {
                            Label("Diagnóstico", systemImage: "archivebox")
                        }
                    }

                    if let message = appState.lastOperationMessage ?? appState.lastSunshineOperationMessage {
                        Label(message, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                StatusPanel(
                    title: "Modo remoto",
                    value: appState.remoteWorkSession.state.displayName,
                    detail: appState.remoteWorkSession.nextStep,
                    status: appState.remoteWorkSession.state.checkStatus
                )

                StatusPanel(
                    title: "Agente residente",
                    value: appState.agentStatus.isRunning ? "Ativo" : appState.agentStatus.launchAgentStatus.displayName,
                    detail: appState.agentStatus.detail,
                    status: appState.agentStatus.checkStatus
                )

                StatusPanel(
                    title: "Engines",
                    value: appState.managedEngineStatus.aggregateStatus.displayName,
                    detail: "Video, audio e rede gerenciados pelo MacStream",
                    status: appState.managedEngineStatus.aggregateStatus
                )

                StatusPanel(
                    title: "Permissões macOS",
                    value: appState.dashboard.permissionsStatus.runtimeGuidanceStatus.displayName,
                    detail: appState.dashboard.permissionsStatus.runtimeGuidanceStatus == .pass
                        ? "Permissões conhecidas OK"
                        : "Diagnóstico não bloqueante; a captura real é validada pela engine.",
                    status: appState.dashboard.permissionsStatus.runtimeGuidanceStatus
                )

                StatusPanel(
                    title: "Energia",
                    value: appState.powerAssertionStatus.isActive ? "Keep-awake ativo" : "Aguardando sessão",
                    detail: appState.powerAssertionStatus.detail,
                    status: appState.powerAssertionStatus.checkStatus
                )

                StatusPanel(
                    title: "Privacidade",
                    value: appState.hostPrivacyStatus.lastAction.rawValue,
                    detail: appState.hostPrivacyStatus.detail,
                    status: appState.hostPrivacyStatus.checkStatus
                )
            }

            OnboardingStepList(steps: appState.onboardingSteps)

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
        PageContainer(title: "Setup", subtitle: "Checklist seguro para preparar vídeo, áudio, rede e pareamento.") {
            OnboardingStepList(steps: appState.onboardingSteps)

            GroupBox("Preflight") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            Task {
                                await appState.runPreflight(
                                    startAfterValidation: false,
                                    overwriteConfig: false
                                )
                            }
                        } label: {
                            Label("Validar sem iniciar", systemImage: "checkmark.shield")
                        }

                        Button {
                            Task {
                                await appState.runPreflight(
                                    startAfterValidation: true,
                                    overwriteConfig: false
                                )
                            }
                        } label: {
                            Label("Gerar config e iniciar", systemImage: "play.circle")
                        }

                        Spacer()
                    }

                    if let result = appState.lastPreflightResult {
                        Text("Estado: \(result.operationalState.displayName)")
                            .font(.headline)
                        if !result.blockers.isEmpty {
                            ForEach(result.blockers, id: \.self) { blocker in
                                Label(blocker, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
                    HStack {
                        Button {
                            Task { await appState.requestMacOSPermissions() }
                        } label: {
                            Label("Solicitar permissões", systemImage: "hand.raised")
                        }
                        Spacer()
                    }

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

                    if !appState.lastPermissionRequestResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.lastPermissionRequestResults) { result in
                                Label(result.detail, systemImage: result.statusAfter == .granted ? "checkmark.circle" : "exclamationmark.triangle")
                                    .foregroundStyle(result.statusAfter == .granted ? .green : .orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct DependenciesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showBlackHoleExplainer = false

    var body: some View {
        PageContainer(title: "Components", subtitle: "Componentes gerenciados pelo MacStream para video, audio e pareamento.") {
            VStack(spacing: 12) {
                ForEach(appState.dependencyStatuses) { dependency in
                    DependencyRow(dependency: dependency)
                }
            }

            GroupBox("Instalação integrada") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await appState.installMissingDependencies() }
                        } label: {
                            Label("Instalar dependências ausentes", systemImage: "square.and.arrow.down")
                        }

                        if appState.dependencyStatus(for: .sunshine) != .pass {
                            Button {
                                Task { await appState.installManagedSunshine() }
                            } label: {
                                Label("Restaurar mecanismo de vídeo", systemImage: "arrow.down.circle")
                            }
                        }

                        if appState.dependencyStatus(for: .blackHole) != .pass {
                            Button {
                                showBlackHoleExplainer = true
                            } label: {
                                Label("Configurar roteamento de áudio", systemImage: "speaker.wave.2")
                            }
                        }
                    }

                    if let progress = appState.dependencyInstallProgress {
                        HStack(alignment: .top, spacing: 12) {
                            StatusIcon(status: status(for: progress.stage))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(progress.id.displayName): \(progress.stage.displayName)")
                                    .font(.headline)
                                Text(progress.detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    ForEach(appState.dependencyInstallerManager.artifacts) { artifact in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(artifact.displayName) \(artifact.version)")
                                .font(.headline)
                            Text(artifact.downloadURL.absoluteString)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("SHA-256: \(artifact.sha256)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            if artifact.requiresAdministrator || artifact.requiresReboot || artifact.isPrerelease {
                                Text(artifactNotes(artifact))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Configurar engine de video manualmente") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Se a engine de video não estiver no PATH padrão, informe o caminho do binário em Settings e revalide.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(appState.runtimeSettings.sunshineBinaryPath ?? "Nenhum caminho manual configurado.")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            Task { await appState.refreshDependencies() }
                        } label: {
                            Label("Revalidar", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Política de instalação") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Componentes upstream independentes aparecem aqui para compliance e suporte.", systemImage: "shippingbox")
                    Label("A engine de video é baixada de release upstream fixado e instalada em diretório gerenciado pelo usuário.", systemImage: "checkmark.shield")
                    Label("O driver de audio é baixado de URL oficial, verificado por checksum e aberto no Installer.app.", systemImage: "safari")
                    Label("Portas de firewall não são alteradas automaticamente.", systemImage: "lock.shield")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showBlackHoleExplainer) {
            BlackHoleInstallExplainer(
                onCancel: { showBlackHoleExplainer = false },
                onConfirm: {
                    showBlackHoleExplainer = false
                    Task {
                        await appState.installBlackHole()
                        await appState.pollForBlackHoleInstallation()
                    }
                }
            )
        }
    }

    private func status(for stage: DependencyInstallStage) -> CheckStatus {
        switch stage {
        case .completed: return .pass
        case .failed: return .fail
        case .idle, .downloading, .verifying, .installing, .waitingForUser: return .warning
        }
    }

    private func artifactNotes(_ artifact: DependencyArtifact) -> String {
        [
            artifact.isPrerelease ? "Versão upstream fixada em prerelease para obter artefato macOS." : nil,
            artifact.requiresAdministrator ? "Pode solicitar senha de administrador no Installer.app." : nil,
            artifact.requiresReboot ? "Pode exigir reinicialização após instalar." : nil
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

struct SunshineView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Advanced Engines", subtitle: "Diagnóstico técnico das engines internas controladas pelo MacStream.") {
            StatusPanel(
                title: "Engine de video",
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
                    Text("O app usa esse diretório para evitar conflito com uma instalação externa existente.")
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
    @State private var audioDevices: [AudioDevice] = []
    @State private var routeStatus: CheckStatus = .unknown

    var body: some View {
        PageContainer(title: "Audio", subtitle: "Dispositivos CoreAudio reais, rota preferida e configuração isolada do MacStream.") {
            StatusPanel(
                title: "Rota de audio MacStream",
                value: appState.dashboard.blackHoleStatus.displayName,
                detail: blackHoleDetail,
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

            GroupBox("Dispositivos CoreAudio") {
                VStack(spacing: 10) {
                    HStack {
                        StatusIcon(status: routeStatus)
                        Text("Rota atual: \(routeStatus.displayName)")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await reloadAudioDevices() }
                        } label: {
                            Label("Revalidar", systemImage: "arrow.clockwise")
                        }
                    }

                    ForEach(audioDevices) { device in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: device.isOutput ? "speaker.wave.2" : "mic")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name)
                                    .font(.headline)
                                Text(deviceDetail(device))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(device.status.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }

                    if audioDevices.isEmpty {
                        Text("Nenhum dispositivo CoreAudio foi listado no diagnóstico atual.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task {
            await reloadAudioDevices()
        }
    }

    private var blackHoleDetail: String {
        if appState.runtimeSettings.audioCaptureMode == .blackHole2ch {
            return appState.dashboard.blackHoleStatus == .installed
                ? "A configuração isolada deve gravar audio_sink = BlackHole 2ch."
                : "Instale externamente ou escolha captura nativa para continuar sem BlackHole."
        }

        return "Modo atual não depende de BlackHole, mas ele continua disponível como fallback."
    }

    private func reloadAudioDevices() async {
        audioDevices = await appState.audioDeviceManager.listAudioDevices()
        routeStatus = await appState.audioDeviceManager.validateAudioRoute()
    }

    private func deviceDetail(_ device: AudioDevice) -> String {
        let direction = [
            device.isInput ? "entrada" : nil,
            device.isOutput ? "saída" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " e ")
        let sampleRate = device.sampleRate.map { " @ \(Int($0)) Hz" } ?? ""
        return "\(direction), \(device.channels) canais\(sampleRate)"
    }
}

struct NetworkView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        PageContainer(title: "Network", subtitle: "Diagnóstico local de IP, portas do mecanismo de streaming e orientação para VPN mesh.") {
            GroupBox("Endereços") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.dashboard.networkStatus.localAddresses, id: \.self) { address in
                        HStack {
                            Label(address, systemImage: "network")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                appState.copyPairingAddress(address)
                            } label: {
                                Label("Copiar", systemImage: "doc.on.doc")
                            }
                        }
                    }

                    if let tailscale = appState.dashboard.networkStatus.tailscaleAddress {
                        HStack {
                            Label(tailscale, systemImage: "lock.shield")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                appState.copyPairingAddress(tailscale)
                            } label: {
                                Label("Copiar", systemImage: "doc.on.doc")
                            }
                        }
                    } else {
                        Text("Tailscale não detectado.")
                            .foregroundStyle(.secondary)
                    }

                    Text("Para teste remoto, prefira VPN mesh como Tailscale. Exposição pública direta de portas Sunshine deve ser avaliada fora deste MVP.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        PageContainer(title: "Moonlight", subtitle: "Guia de pareamento sem depender de APIs internas do mecanismo de vídeo.") {
            GroupBox("Acesso rápido") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            Task { await appState.openSunshineWebUI() }
                        } label: {
                            Label("Abrir painel avançado", systemImage: "safari")
                        }

                        Spacer()
                    }

                    ForEach(pairingAddresses, id: \.self) { address in
                        HStack {
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                appState.copyPairingAddress(address)
                            } label: {
                                Label("Copiar", systemImage: "doc.on.doc")
                            }
                        }
                    }

                    if pairingAddresses.isEmpty {
                        Text("Nenhum IP local foi detectado; execute o diagnóstico de rede antes do pareamento.")
                            .foregroundStyle(.secondary)
                    }
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

            GroupBox("Checklist pós-pareamento") {
                VStack(spacing: 10) {
                    ForEach(MoonlightChecklistItemID.allCases, id: \.self) { item in
                        Toggle(isOn: checklistBinding(for: item)) {
                            Text(item.title)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pairingAddresses: [String] {
        var addresses = appState.dashboard.networkStatus.localAddresses
        if let tailscale = appState.dashboard.networkStatus.tailscaleAddress {
            addresses.append(tailscale)
        }
        return addresses
    }

    private func checklistBinding(for item: MoonlightChecklistItemID) -> Binding<Bool> {
        Binding(
            get: { appState.completedMoonlightChecklistItems.contains(item) },
            set: { isComplete in
                if isComplete {
                    appState.markMoonlightChecklistItemComplete(item)
                }
            }
        )
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

            GroupBox("Suporte") {
                HStack {
                    Button {
                        Task { _ = await appState.exportSupportBundleZip() }
                    } label: {
                        Label("Exportar ZIP de suporte", systemImage: "archivebox")
                    }

                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Label("Reexecutar diagnóstico", systemImage: "arrow.clockwise")
                    }

                    Spacer()
                }
            }

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
                    TextField("Caminho manual do mecanismo de vídeo", text: $sunshineBinaryPath)
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

            GroupBox("MacStream Agent") {
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
                    Text("Essas ações operam apenas o LaunchAgent `com.macstream.host.agent` do usuário atual.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Modo remoto") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estado: \(appState.remoteWorkSession.state.displayName)")
                        .font(.headline)
                    HStack {
                        Toggle("Impedir sleep do sistema", isOn: powerPreventSleepBinding)
                        Toggle("Manter display acordado", isOn: powerDisplayAwakeBinding)
                    }
                    Toggle("Oferecer bloqueio de tela ao iniciar", isOn: hostLockOfferBinding)
                    Toggle("Permitir bloqueio manual do host", isOn: hostLockManualBinding)
                    Picker("Modo de bloqueio do host", selection: hostLockModeBinding) {
                        ForEach(HostPrivacyMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(hostLockModeExplanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                        Task { _ = await appState.exportSupportBundleZip() }
                    } label: {
                        Label("Exportar ZIP de suporte", systemImage: "archivebox")
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

    private var powerPreventSleepBinding: Binding<Bool> {
        Binding(
            get: { appState.runtimeSettings.powerPolicy.preventSystemSleep },
            set: { value in
                var policy = appState.runtimeSettings.powerPolicy
                policy.preventSystemSleep = value
                Task { await appState.enablePowerPolicy(policy) }
            }
        )
    }

    private var powerDisplayAwakeBinding: Binding<Bool> {
        Binding(
            get: { appState.runtimeSettings.powerPolicy.keepDisplayAwake },
            set: { value in
                var policy = appState.runtimeSettings.powerPolicy
                policy.keepDisplayAwake = value
                Task { await appState.enablePowerPolicy(policy) }
            }
        )
    }

    private var hostLockOfferBinding: Binding<Bool> {
        Binding(
            get: { appState.runtimeSettings.hostPrivacyPolicy.offerLockOnSessionStart },
            set: { value in
                var policy = appState.runtimeSettings.hostPrivacyPolicy
                policy.offerLockOnSessionStart = value
                Task { await appState.updateHostPrivacyPolicy(policy) }
            }
        )
    }

    private var hostLockManualBinding: Binding<Bool> {
        Binding(
            get: { appState.runtimeSettings.hostPrivacyPolicy.allowManualLock },
            set: { value in
                var policy = appState.runtimeSettings.hostPrivacyPolicy
                policy.allowManualLock = value
                Task { await appState.updateHostPrivacyPolicy(policy) }
            }
        )
    }

    private var hostLockModeBinding: Binding<HostPrivacyMode> {
        Binding(
            get: { appState.runtimeSettings.hostPrivacyPolicy.mode },
            set: { value in
                var policy = appState.runtimeSettings.hostPrivacyPolicy
                policy.mode = value
                Task { await appState.updateHostPrivacyPolicy(policy) }
            }
        )
    }

    private var hostLockModeExplanation: String {
        switch appState.runtimeSettings.hostPrivacyPolicy.mode {
        case .appOverlay:
            return "Cobre a tela do host com uma janela preta dentro do MacStream. Não toca na sessão gráfica, então o streaming Moonlight nunca cai."
        case .systemSuspend:
            return "Usa o bloqueio nativo do macOS (CGSession). Ainda não validado em streaming ativo — pode interromper vídeo/áudio/teclado se o macOS suspender a sessão gráfica."
        }
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
                return "O app vai carregar o MacStream Agent no domínio do usuário atual usando launchctl."
            case .launchAgent(.unload):
                return "O app vai descarregar apenas o LaunchAgent com o label com.macstream.host.agent."
            case .launchAgent(.remove):
                return "O app vai remover apenas o plist com.macstream.host.agent.plist criado pelo MacStream Host."
            case .softReset:
                return "O app vai parar somente a engine owned pelo MacStream Host, remover o LaunchAgent do app e arquivar a configuração isolada."
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

struct OperationalStateBanner: View {
    let state: HostOperationalState
    let nextStep: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(status: state.checkStatus)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.displayName)
                    .font(.title3.weight(.semibold))
                Text(nextStep)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

struct BlackHoleInstallExplainer: View {
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurar roteamento de áudio")
                        .font(.title2.weight(.bold))
                    Text("O MacStream usa um driver oficial para capturar o áudio do sistema durante o streaming.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                StepLine(number: 1, title: "Download verificado", detail: "O MacStream baixa o instalador oficial e confere o checksum SHA-256 antes de abrir.")
                StepLine(number: 2, title: "Instalador padrão do macOS", detail: "O Installer.app abre. Pode pedir sua senha de administrador para instalar o driver de sistema.")
                StepLine(number: 3, title: "Reinicialização (em alguns casos)", detail: "Drivers de áudio podem exigir reiniciar o Mac para ficar ativos. Você pode reabrir o MacStream depois sem perda de progresso.")
                StepLine(number: 4, title: "Detecção automática", detail: "Quando o driver aparecer, o MacStream marca esta etapa como concluída sem mais cliques.")
            }

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm()
                } label: {
                    Label("Baixar e abrir instalador", systemImage: "arrow.down.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct StepLine: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background(.blue.opacity(0.15), in: Circle())
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct RemoteWorkBanner: View {
    let report: RemoteWorkSessionReport
    let pairingAddresses: [String]
    var onCopyAddress: (String) -> Void = { _ in }

    init(
        report: RemoteWorkSessionReport,
        pairingAddresses: [String] = [],
        onCopyAddress: @escaping (String) -> Void = { _ in }
    ) {
        self.report = report
        self.pairingAddresses = pairingAddresses
        self.onCopyAddress = onCopyAddress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: headlineSymbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 44, height: 44)
                    .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(headlineTitle)
                        .font(.title2.weight(.bold))
                    Text(report.nextStep)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if !report.blockers.isEmpty {
                BannerMessageList(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    title: "Bloqueios a resolver",
                    items: report.blockers
                )
            }

            if !report.warnings.isEmpty {
                BannerMessageList(
                    icon: "info.circle.fill",
                    color: .yellow,
                    title: "Avisos",
                    items: report.warnings
                )
            }

            if report.state == .running && !pairingAddresses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Endereços para conectar pelo Moonlight", systemImage: "ipad.and.iphone")
                        .font(.headline)
                    ForEach(pairingAddresses, id: \.self) { address in
                        HStack {
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                onCopyAddress(address)
                            } label: {
                                Label("Copiar", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(10)
                .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var headlineTitle: String {
        switch report.state {
        case .running:
            return "Modo remoto ativo — conecte pelo Moonlight"
        case .ready:
            return "Pronto para começar"
        case .starting:
            return "Iniciando modo remoto..."
        case .stopping:
            return "Encerrando sessão..."
        case .degraded:
            return "Sessão ativa com avisos"
        case .blocked:
            return "Bloqueios impedem iniciar"
        case .notReady:
            return "Configuração inicial pendente"
        }
    }

    private var headlineSymbol: String {
        switch report.state {
        case .running: return "dot.radiowaves.left.and.right"
        case .ready: return "play.circle.fill"
        case .starting, .stopping: return "arrow.triangle.2.circlepath"
        case .degraded: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        case .notReady: return "wand.and.stars"
        }
    }

    private var accentColor: Color {
        switch report.state.checkStatus {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        case .unknown: return .blue
        }
    }
}

private struct BannerMessageList: View {
    let icon: String
    let color: Color
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingStepList: View {
    let steps: [OnboardingStep]

    var body: some View {
        GroupBox("Onboarding de primeira execução") {
            VStack(spacing: 10) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        StatusIcon(status: step.state.checkStatus)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(label(for: step.state))
                            .font(.caption)
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

    private func label(for state: OnboardingStepState) -> String {
        switch state {
        case .pending: return "Pendente"
        case .active: return "Ativo"
        case .passed: return "OK"
        case .warning: return "Atenção"
        case .failed: return "Falha"
        }
    }
}

struct DependencyRow: View {
    let dependency: DependencyStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(status: dependency.status)
            VStack(alignment: .leading, spacing: 6) {
                Text(dependency.id.displayName)
                    .font(.headline)
                Text(dependency.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let path = dependency.detectedPath {
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let version = dependency.detectedVersion {
                    Text("Versão: \(version)")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url = dependency.officialURL {
                Link(destination: url) {
                    Label("Site oficial", systemImage: "safari")
                }
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
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
