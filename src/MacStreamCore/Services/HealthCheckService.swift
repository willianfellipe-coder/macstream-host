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

        // Accessibility check: if our process isn't AX-trusted, keyboard
        // and mouse forwarding from Moonlight are silently dropped by
        // `CGEventPost`. We probe via `AXIsProcessTrusted()` from the GUI
        // process. Because the GUI and engine share Identifier and
        // Authority (org.macstream.host / MacStream Local Dev), the
        // result is representative of what the engine sees.
        checks.append(accessibilityCheck())

        checks.append(contentsOf: [
            HealthCheck(
                id: .webUI,
                title: "Pareamento",
                status: sunshine.webUIReachable ? .pass : .warning,
                detail: sunshine.webUIReachable ? "Interface local de pareamento está acessível." : "Pareamento será validado quando o motor estiver rodando."
            ),
            HealthCheck(
                id: .blackHole,
                title: "Roteamento de áudio",
                status: blackHole.checkStatus,
                detail: blackHole == .installed ? "Roteamento de áudio do MacStream detectado." : "Áudio pode exigir instalação/validação guiada."
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
                return "Motor de vídeo do MacStream rodando. Binário interno em \(binaryPath)."
            }
            return "Motor de vídeo rodando, mas o binário ainda não foi localizado."
        case .stopped:
            if let binaryPath = status.binaryPath {
                return "Motor de vídeo detectado em \(binaryPath), mas não está rodando."
            }
            return "Motor de vídeo detectado, mas não está rodando."
        case .notInstalled:
            return "Reinstale o MacStream Host — o motor de vídeo embarcado não foi encontrado no bundle."
        case .failed:
            return "Consulte os logs do motor de vídeo para identificar a causa."
        default:
            return "Motor de vídeo ainda não foi iniciado pelo MacStream."
        }
    }

    private func accessibilityCheck() -> HealthCheck {
        switch AccessibilityProbe.currentStatus() {
        case .granted:
            return HealthCheck(
                id: .sunshineAccessibility,
                title: "Acessibilidade (entrada do Moonlight)",
                status: .pass,
                detail: "Acessibilidade concedida — teclado e mouse do Moonlight serão injetados."
            )
        case .denied:
            return HealthCheck(
                id: .sunshineAccessibility,
                title: "Acessibilidade (entrada do Moonlight)",
                status: .fail,
                detail: "Sem Acessibilidade: o motor recebe os eventos do Moonlight mas o macOS descarta silenciosamente. Adicione MacStream Host em Ajustes > Privacidade > Acessibilidade."
            )
        case .unknown:
            return HealthCheck(
                id: .sunshineAccessibility,
                title: "Acessibilidade (entrada do Moonlight)",
                status: .warning,
                detail: "Não foi possível verificar Acessibilidade automaticamente."
            )
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

        // Detect Screen Recording TCC failures across every macOS version we
        // care about. On older macOS the missing grant crashed Sunshine; on
        // 14.5+/Sequoia the API now returns nil silently and Sunshine reports
        // an encoder-startup failure instead. Both shapes mean the same thing:
        // the embedded video engine has no permission to capture the screen.
        if detectsScreenRecordingTccFailure(joined) {
            return HealthCheck(
                id: .sunshineScreenRecording,
                title: "Permissão de Gravação de Tela",
                status: .fail,
                detail: "O motor de vídeo não tem permissão de Gravação de Tela. Abra Ajustes do Sistema → Privacidade → Gravação do Áudio do Sistema e da Tela e ative 'MacStream Host'."
            )
        }

        if joined.contains("no screen capture permission") {
            return HealthCheck(
                id: .sunshineScreenRecording,
                title: "Permissão de Gravação de Tela",
                status: .fail,
                detail: "O motor de vídeo reportou ausência de permissão de Gravação de Tela. Abra Ajustes do Sistema e ative 'MacStream Host'."
            )
        }

        if joined.contains("unrecognized configurable option") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime do motor de vídeo",
                status: .warning,
                detail: "O motor de vídeo reportou uma opção de configuração não reconhecida. Regere a configuração."
            )
        }

        return HealthCheck(
            id: .sunshineRuntime,
            title: "Runtime do motor de vídeo",
            status: .pass,
            detail: "Nenhum erro crítico recente foi encontrado nos logs do motor de vídeo."
        )
    }

    /// Recognises every signature we've seen for "Sunshine has no Screen
    /// Recording grant" across recent macOS versions:
    ///
    /// - Older macOS: the API returned `nil` displays which Sunshine fed
    ///   straight into `+[NSDictionary dictionaryWithObjects:forKeys:count:]`
    ///   and crashed with `NSInvalidArgumentException` / `+[AVVideo displayNames]`.
    /// - macOS 14.5+/Sequoia: the API silently returns no displays. Sunshine's
    ///   encoder probing then fails with `Encoder [videotoolbox] failed` +
    ///   `Encoder [software] failed` + `Unable to find display or encoder
    ///   during startup` / `Please check that a display is connected`. The
    ///   process keeps the HTTP server alive even though capture is broken,
    ///   so this is the only way to spot it from outside.
    private func detectsScreenRecordingTccFailure(_ joined: String) -> Bool {
        let hasNilInsertException =
            joined.contains("nsinvalidargumentexception")
                && joined.contains("initwithobjects:forkeys:count:")
                && joined.contains("attempt to insert nil object")
        let hasDisplayNamesFrame = joined.contains("avvideo displaynames")
        let hasNoDisplayDuringStartup =
            joined.contains("unable to find display or encoder during startup")
                || (joined.contains("please check that a display is connected")
                    && joined.contains("encoder"))
        let hasFailedEncoderProbe =
            joined.contains("encoder [videotoolbox] failed")
                && joined.contains("encoder [software] failed")
        return hasNilInsertException
            || hasDisplayNamesFrame
            || hasNoDisplayDuringStartup
            || hasFailedEncoderProbe
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

        return "IP local \(primaryAddress). Portas do motor foram verificadas localmente."
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
