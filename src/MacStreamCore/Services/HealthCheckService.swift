// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultHealthCheckService: HealthCheckServicing {
    private let sunshineManager: SunshineManaging
    private let blackHoleManager: BlackHoleManaging
    private let permissionManager: PermissionManaging
    private let audioDeviceManager: AudioDeviceManaging
    private let networkDiagnosticsManager: NetworkDiagnosticsManaging
    private let launchAgentManager: LaunchAgentManaging
    private let logManager: LogManaging?
    private let agentManager: AgentManaging?
    private let powerAssertionManager: PowerAssertionManaging?
    private let hostPrivacyManager: HostPrivacyManaging?
    private let remoteWorkSessionManager: RemoteWorkSessionManaging?

    public init(
        sunshineManager: SunshineManaging,
        blackHoleManager: BlackHoleManaging,
        permissionManager: PermissionManaging,
        audioDeviceManager: AudioDeviceManaging,
        networkDiagnosticsManager: NetworkDiagnosticsManaging,
        launchAgentManager: LaunchAgentManaging,
        logManager: LogManaging? = nil,
        agentManager: AgentManaging? = nil,
        powerAssertionManager: PowerAssertionManaging? = nil,
        hostPrivacyManager: HostPrivacyManaging? = nil,
        remoteWorkSessionManager: RemoteWorkSessionManaging? = nil
    ) {
        self.sunshineManager = sunshineManager
        self.blackHoleManager = blackHoleManager
        self.permissionManager = permissionManager
        self.audioDeviceManager = audioDeviceManager
        self.networkDiagnosticsManager = networkDiagnosticsManager
        self.launchAgentManager = launchAgentManager
        self.logManager = logManager
        self.agentManager = agentManager
        self.powerAssertionManager = powerAssertionManager
        self.hostPrivacyManager = hostPrivacyManager
        self.remoteWorkSessionManager = remoteWorkSessionManager
    }

    public func runHealthCheck() async -> HealthCheckResult {
        let sunshine = await sunshineManager.status()
        let blackHole = await blackHoleManager.installationStatus()
        let permissions = await permissionManager.currentStatus()
        let audioStatus = await audioHealthStatus(blackHole: blackHole)
        let network = await networkDiagnosticsManager.runDiagnostics()
        let launchAgent = await launchAgentManager.status()
        let agent = await agentManager?.status()
        let localPower = await powerAssertionManager?.currentStatus()
        let localPrivacy = await hostPrivacyManager?.currentStatus()
        let remoteWork = await remoteWorkSessionManager?.status()
        let effectivePower = remoteWork?.powerStatus.isActive == true ? remoteWork?.powerStatus : localPower
        let effectivePrivacy = remoteWork?.agentStatus.isRunning == true ? remoteWork?.hostPrivacyStatus : localPrivacy

        var checks = [
            macOSVersionCheck(),
            architectureCheck(),
            HealthCheck(
                id: .macStreamAgent,
                title: "MacStream Agent",
                status: agent?.checkStatus ?? .warning,
                detail: agent?.detail ?? "Agente residente ainda nao configurado."
            ),
            HealthCheck(
                id: .remoteWorkMode,
                title: "Modo remoto MacStream",
                status: remoteWork?.state.checkStatus ?? .warning,
                detail: remoteWork?.nextStep ?? "Prepare o MacStream antes de iniciar uma sessao remota."
            ),
            HealthCheck(
                id: .sunshine,
                title: "Engine de video",
                status: sunshine.state.checkStatus,
                detail: sunshineDetail(for: sunshine)
            )
        ]

        if let runtimeLogCheck = await sunshineRuntimeLogCheck() {
            checks.append(runtimeLogCheck)
        }

        checks.append(contentsOf: [
            HealthCheck(
                id: .webUI,
                title: "Pareamento",
                status: sunshine.webUIReachable ? .pass : .warning,
                detail: sunshine.webUIReachable ? "Interface local de pareamento esta acessivel." : "Pareamento sera validado quando a engine estiver rodando."
            ),
            HealthCheck(
                id: .blackHole,
                title: "Rota de audio gerenciada",
                status: blackHole.checkStatus,
                detail: blackHole == .installed ? "Driver de audio gerenciado detectado." : "Audio pode exigir instalacao/validacao guiada."
            ),
            HealthCheck(
                id: .permissions,
                title: "Permissões macOS",
                status: permissionHealthStatus(for: permissions),
                detail: permissionDetail(for: permissions)
            ),
            HealthCheck(
                id: .audio,
                title: "Rota de áudio",
                status: audioStatus,
                detail: audioDetail(for: audioStatus)
            ),
            HealthCheck(
                id: .network,
                title: "Rede",
                status: network.aggregateStatus,
                detail: networkDetail(for: network)
            ),
            HealthCheck(
                id: .launchAgent,
                title: "LaunchAgent MacStream",
                status: launchAgent.checkStatus,
                detail: launchAgentDetail(for: launchAgent)
            ),
            HealthCheck(
                id: .power,
                title: "Energia",
                status: effectivePower?.checkStatus ?? .warning,
                detail: effectivePower?.detail ?? "Keep-awake sera ativado durante o modo remoto."
            ),
            HealthCheck(
                id: .hostPrivacy,
                title: "Privacidade do host",
                status: effectivePrivacy?.checkStatus ?? .warning,
                detail: effectivePrivacy?.detail ?? "Bloqueio do host e opcional e precisa de validacao pratica."
            )
        ])

        return HealthCheckResult(checks: checks)
    }

    private func macOSVersionCheck() -> HealthCheck {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let isSupported = version.majorVersion > 14 || (version.majorVersion == 14 && version.minorVersion >= 2)
        let value = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        return HealthCheck(
            id: .macOSVersion,
            title: "macOS \(value)",
            status: isSupported ? .pass : .fail,
            detail: isSupported ? "macOS 14.2+ detectado." : "O alvo inicial exige macOS 14.2 ou superior."
        )
    }

    private func architectureCheck() -> HealthCheck {
        #if arch(arm64)
        return HealthCheck(id: .architecture, title: "Apple Silicon", status: .pass, detail: "Arquitetura arm64 detectada.")
        #else
        return HealthCheck(id: .architecture, title: "Intel", status: .warning, detail: "Intel ainda precisa de validação explícita no MVP.")
        #endif
    }

    private func sunshineDetail(for status: SunshineStatus) -> String {
        switch status.state {
        case .running:
            if let binaryPath = status.binaryPath {
                return "Engine de video gerenciada esta rodando. Binario interno em \(binaryPath)."
            }
            return "Engine de video esta rodando, mas o binario ainda nao foi localizado."
        case .stopped:
            if let binaryPath = status.binaryPath {
                return "Engine de video detectada em \(binaryPath), mas nao esta rodando."
            }
            return "Engine de video detectada, mas nao esta rodando."
        case .notInstalled:
            return "Instale/prepare a engine de video do MacStream antes de iniciar o modo remoto."
        case .failed:
            return "Consultar logs da engine de video para identificar a causa."
        default:
            return "Engine de video ainda nao foi iniciada pelo MacStream."
        }
    }

    private func sunshineRuntimeLogCheck() async -> HealthCheck? {
        guard let logManager else {
            return nil
        }

        let logs = await logManager.recentLogs(maxLines: 200)
        let sunshineMessages = logs
            .filter { $0.subsystem.localizedCaseInsensitiveContains("sunshine") }
            .map(\.message)

        guard sunshineMessages.isEmpty == false else {
            return nil
        }

        let currentStartupMessages = messagesFromCurrentSunshineStartup(sunshineMessages)
        let joined = currentStartupMessages.joined(separator: "\n").lowercased()

        if joined.contains("no screen capture permission") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime da engine de video",
                status: .fail,
                detail: "A engine de video reportou ausencia de permissao de Gravacao de Tela. Abra Ajustes do Sistema antes do teste real."
            )
        }

        if joined.contains("video failed to find working encoder")
            || joined.contains("unable to find display or encoder") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime da engine de video",
                status: .fail,
                detail: "A engine de video iniciou, mas nao encontrou encoder/display funcional. Corrija permissoes de tela e valide os logs antes de parear."
            )
        }

        if joined.contains("unrecognized configurable option") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime da engine de video",
                status: .warning,
                detail: "A engine de video reportou uma opcao de configuracao nao reconhecida. Regere a configuracao isolada."
            )
        }

        return HealthCheck(
            id: .sunshineRuntime,
            title: "Runtime da engine de video",
            status: .pass,
            detail: "Nenhum erro critico recente foi encontrado nos logs da engine de video."
        )
    }

    private func messagesFromCurrentSunshineStartup(_ messages: [String]) -> [String] {
        guard let startupIndex = messages.indices.reversed().first(where: {
            messages[$0].localizedCaseInsensitiveContains("Sunshine version:")
        }) else {
            return messages
        }

        return Array(messages[startupIndex...])
    }

    private func audioDetail(for status: CheckStatus) -> String {
        switch status {
        case .pass:
            return "Rota de audio do MacStream foi detectada."
        case .warning:
            return "Driver de audio detectado; validar audio no teste pratico do Moonlight."
        case .fail:
            return "Nenhum dispositivo de audio foi detectado via CoreAudio."
        case .unknown:
            return "Nao foi possivel determinar a rota de audio."
        }
    }

    private func audioHealthStatus(blackHole: BlackHoleInstallationStatus) async -> CheckStatus {
        let routeStatus = await audioDeviceManager.validateAudioRoute()

        if routeStatus == .fail && blackHole == .installed {
            return .warning
        }

        return routeStatus
    }

    private func networkDetail(for result: NetworkDiagnosticResult) -> String {
        if result.localAddresses.isEmpty {
            return "Nenhum IP local não-loopback foi detectado."
        }

        let primaryAddress = result.localAddresses.first ?? "IP local"
        if let tailscaleAddress = result.tailscaleAddress {
            return "IP local \(primaryAddress); Tailscale \(tailscaleAddress)."
        }

        return "IP local \(primaryAddress). Portas Sunshine foram verificadas localmente."
    }

    private func permissionDetail(for permissions: MacOSPermissionsStatus) -> String {
        if permissions.criticalPermissionsSatisfied {
            return "Permissões críticas aparentam estar OK."
        }

        let pending = permissions.checks
            .filter { $0.id.isCriticalForMVP && !$0.status.isSatisfied }
            .map { $0.id.displayName }

        if pending.isEmpty {
            return "Validar permissões opcionais conforme necessário."
        }

        return "Validar: \(pending.joined(separator: ", "))."
    }

    private func permissionHealthStatus(for permissions: MacOSPermissionsStatus) -> CheckStatus {
        // TCC is per executable. The app can guide permissions, but the real blocker for
        // streaming is detected from the managed video engine runtime/logs after start.
        permissions.aggregateStatus == .pass ? .pass : .warning
    }

    private func launchAgentDetail(for status: LaunchAgentStatus) -> String {
        switch status {
        case .loaded:
            return "LaunchAgent do MacStream carregado."
        case .installed:
            return "LaunchAgent do MacStream instalado; use carregar para ativar nesta sessao."
        case .notInstalled:
            return "LaunchAgent do MacStream ainda nao instalado."
        case .failed:
            return "LaunchAgent do MacStream encontrado, mas o plist nao passou na validacao."
        case .unknown:
            return "Nao foi possivel determinar status do LaunchAgent."
        }
    }
}
