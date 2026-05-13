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

    public init(
        sunshineManager: SunshineManaging,
        blackHoleManager: BlackHoleManaging,
        permissionManager: PermissionManaging,
        audioDeviceManager: AudioDeviceManaging,
        networkDiagnosticsManager: NetworkDiagnosticsManaging,
        launchAgentManager: LaunchAgentManaging,
        logManager: LogManaging? = nil
    ) {
        self.sunshineManager = sunshineManager
        self.blackHoleManager = blackHoleManager
        self.permissionManager = permissionManager
        self.audioDeviceManager = audioDeviceManager
        self.networkDiagnosticsManager = networkDiagnosticsManager
        self.launchAgentManager = launchAgentManager
        self.logManager = logManager
    }

    public func runHealthCheck() async -> HealthCheckResult {
        let sunshine = await sunshineManager.status()
        let blackHole = await blackHoleManager.installationStatus()
        let permissions = await permissionManager.currentStatus()
        let audioStatus = await audioDeviceManager.validateAudioRoute()
        let network = await networkDiagnosticsManager.runDiagnostics()
        let launchAgent = await launchAgentManager.status()

        var checks = [
            macOSVersionCheck(),
            architectureCheck(),
            HealthCheck(
                id: .sunshine,
                title: "Sunshine",
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
                title: "Web UI Sunshine",
                status: sunshine.webUIReachable ? .pass : .warning,
                detail: sunshine.webUIReachable ? "https://localhost:47990 está acessível." : "Web UI será validada quando Sunshine estiver rodando."
            ),
            HealthCheck(
                id: .blackHole,
                title: "BlackHole 2ch",
                status: blackHole.checkStatus,
                detail: blackHole == .installed ? "BlackHole 2ch detectado." : "BlackHole não será instalado automaticamente nesta fase."
            ),
            HealthCheck(
                id: .permissions,
                title: "Permissões macOS",
                status: permissions.aggregateStatus,
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
                title: "LaunchAgent",
                status: launchAgent.checkStatus,
                detail: launchAgentDetail(for: launchAgent)
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
                return "Sunshine está rodando. Binário detectado em \(binaryPath)."
            }
            return "Sunshine está rodando, mas o binário ainda não foi localizado."
        case .stopped:
            if let binaryPath = status.binaryPath {
                return "Sunshine detectado em \(binaryPath), mas não está rodando."
            }
            return "Sunshine detectado, mas não está rodando."
        case .notInstalled:
            return "Detectar ou apontar um binário Sunshine antes de iniciar o servidor."
        case .failed:
            return "Consultar logs do Sunshine para identificar a causa."
        default:
            return "Sunshine ainda não foi iniciado pelo app."
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

        let joined = sunshineMessages.joined(separator: "\n").lowercased()

        if joined.contains("no screen capture permission") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime Sunshine",
                status: .fail,
                detail: "Sunshine reportou ausência de permissão de Gravação de Tela. Abra Ajustes do Sistema e conceda Screen Recording antes do teste real."
            )
        }

        if joined.contains("video failed to find working encoder")
            || joined.contains("unable to find display or encoder") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime Sunshine",
                status: .fail,
                detail: "Sunshine iniciou, mas não encontrou encoder/display funcional. Corrija permissões de tela e valide os logs antes de parear."
            )
        }

        if joined.contains("unrecognized configurable option") {
            return HealthCheck(
                id: .sunshineRuntime,
                title: "Runtime Sunshine",
                status: .warning,
                detail: "Sunshine reportou uma opção de configuração não reconhecida. Regere a configuração isolada com `preflight --overwrite`."
            )
        }

        return HealthCheck(
            id: .sunshineRuntime,
            title: "Runtime Sunshine",
            status: .pass,
            detail: "Nenhum erro crítico recente foi encontrado nos logs do Sunshine."
        )
    }

    private func audioDetail(for status: CheckStatus) -> String {
        switch status {
        case .pass:
            return "BlackHole 2ch foi detectado como rota de captura disponível."
        case .warning:
            return "Há dispositivos de áudio, mas BlackHole 2ch não foi detectado; validar captura nativa do macOS."
        case .fail:
            return "Nenhum dispositivo de áudio foi detectado via CoreAudio."
        case .unknown:
            return "Não foi possível determinar a rota de áudio."
        }
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

    private func launchAgentDetail(for status: LaunchAgentStatus) -> String {
        switch status {
        case .loaded:
            return "LaunchAgent carregado."
        case .installed:
            return "LaunchAgent instalado; use carregar para ativar nesta sessão."
        case .notInstalled:
            return "LaunchAgent ainda não instalado; gere e revise o plist antes de carregar."
        case .failed:
            return "LaunchAgent encontrado, mas o plist não passou na validação."
        case .unknown:
            return "Não foi possível determinar status do LaunchAgent."
        }
    }
}
