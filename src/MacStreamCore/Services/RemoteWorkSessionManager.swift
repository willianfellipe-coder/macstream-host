// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultRemoteWorkSessionManager: RemoteWorkSessionManaging {
    private let agentManager: AgentManaging
    private let configurationManager: ConfigurationManaging
    private let sunshineManager: SunshineManaging
    private let blackHoleManager: BlackHoleManaging
    private let permissionManager: PermissionManaging
    private let managedEngineManager: ManagedEngineManaging
    private let powerAssertionManager: PowerAssertionManaging
    private let hostPrivacyManager: HostPrivacyManaging
    private let settingsProvider: () -> MacStreamHostSettings

    public init(
        agentManager: AgentManaging,
        configurationManager: ConfigurationManaging,
        sunshineManager: SunshineManaging,
        blackHoleManager: BlackHoleManaging,
        permissionManager: PermissionManaging,
        managedEngineManager: ManagedEngineManaging,
        powerAssertionManager: PowerAssertionManaging,
        hostPrivacyManager: HostPrivacyManaging,
        settingsProvider: @escaping () -> MacStreamHostSettings
    ) {
        self.agentManager = agentManager
        self.configurationManager = configurationManager
        self.sunshineManager = sunshineManager
        self.blackHoleManager = blackHoleManager
        self.permissionManager = permissionManager
        self.managedEngineManager = managedEngineManager
        self.powerAssertionManager = powerAssertionManager
        self.hostPrivacyManager = hostPrivacyManager
        self.settingsProvider = settingsProvider
    }

    public func prepare(overwriteConfig: Bool) async throws -> RemoteWorkSessionReport {
        let settings = settingsProvider()
        _ = try configurationManager.writeDefaultFiles(
            overwrite: overwriteConfig,
            audioSink: settings.audioSink,
            lowLatency: settings.lowLatencyMode
        )
        try await agentManager.install()
        return await makeReport(stateOverride: nil)
    }

    public func start(overwriteConfig: Bool) async throws -> RemoteWorkSessionReport {
        let settings = settingsProvider()
        _ = try configurationManager.writeDefaultFiles(
            overwrite: overwriteConfig,
            audioSink: settings.audioSink,
            lowLatency: settings.lowLatencyMode
        )
        try await agentManager.install()
        try agentManager.writeCommand(MacStreamAgentCommand(kind: .startRemoteWork))
        try await agentManager.load()
        return await makeReport(stateOverride: .starting)
    }

    public func stop() async throws -> RemoteWorkSessionReport {
        try agentManager.writeCommand(MacStreamAgentCommand(kind: .stopRemoteWork))
        return await makeReport(stateOverride: .stopping)
    }

    public func status() async -> RemoteWorkSessionReport {
        let agentStatus = await agentManager.status()
        if var report = try? agentManager.readLastReport(), agentStatus.isRunning {
            report.agentStatus = agentStatus
            return sanitizedAgentReport(report)
        }

        return await makeReport(stateOverride: nil)
    }

    public func lockHostForPrivacy() async throws -> RemoteWorkSessionReport {
        try agentManager.writeCommand(MacStreamAgentCommand(kind: .lockHost))
        return await makeReport(stateOverride: nil)
    }

    private func makeReport(stateOverride: RemoteWorkModeState?) async -> RemoteWorkSessionReport {
        let agent = await agentManager.status()
        let engine = await managedEngineManager.status()
        let power = await powerAssertionManager.currentStatus()
        let privacy = await hostPrivacyManager.currentStatus()
        let sunshine = await sunshineManager.status()
        let blackHole = await blackHoleManager.installationStatus()
        let settings = settingsProvider()

        var blockers: [String] = []
        var warnings: [String] = []

        if sunshine.state == .notInstalled {
            blockers.append("Engine de video do MacStream ainda nao instalada.")
        }

        if sunshine.state == .running && sunshine.ownedProcessID == nil {
            blockers.append("Ha um processo externo de video rodando; o MacStream nao vai controla-lo.")
        }

        if settings.audioCaptureMode == .blackHole2ch && blackHole != .installed {
            warnings.append("Rota de audio gerenciada ainda precisa concluir instalacao/validacao.")
        }

        let derivedState: RemoteWorkModeState
        if let stateOverride {
            derivedState = stateOverride
        } else if blockers.isEmpty == false {
            derivedState = .blocked
        } else if sunshine.state == .running && engine.aggregateStatus == .pass {
            derivedState = .running
        } else if sunshine.state == .running {
            derivedState = .degraded
        } else if agent.launchAgentStatus == .loaded || agent.isRunning {
            derivedState = .ready
        } else {
            derivedState = .notReady
        }

        return RemoteWorkSessionReport(
            state: derivedState,
            agentStatus: agent,
            engineStatus: engine,
            powerStatus: power,
            hostPrivacyStatus: privacy,
            blockers: blockers,
            warnings: warnings,
            nextStep: nextStep(for: derivedState, blockers: blockers, warnings: warnings)
        )
    }

    private func nextStep(
        for state: RemoteWorkModeState,
        blockers: [String],
        warnings: [String]
    ) -> String {
        if let blocker = blockers.first {
            return blocker
        }

        switch state {
        case .notReady:
            return "Prepare o MacStream para instalar o agente e gerar configuracao."
        case .ready:
            return "Inicie o modo remoto e conecte pelo Moonlight no iPad."
        case .starting:
            return "Aguarde o agente iniciar as engines gerenciadas."
        case .running:
            return "Conecte pelo Moonlight e valide video, audio e entrada."
        case .degraded:
            return warnings.first ?? "Modo remoto ativo com avisos; exporte diagnostico se o teste falhar."
        case .stopping:
            return "Aguarde o agente parar a sessao remota gerenciada."
        case .blocked:
            return "Corrija os bloqueios antes de iniciar o modo remoto."
        }
    }

    private func sanitizedAgentReport(_ report: RemoteWorkSessionReport) -> RemoteWorkSessionReport {
        var sanitized = report
        sanitized.blockers = report.blockers.filter {
            $0.localizedCaseInsensitiveContains("permissoes criticas") == false &&
            $0.localizedCaseInsensitiveContains("permissões críticas") == false
        }

        if report.state == .blocked && sanitized.blockers.isEmpty {
            sanitized.state = report.engineStatus.aggregateStatus == .pass ? .running : .degraded
            sanitized.nextStep = nextStep(
                for: sanitized.state,
                blockers: sanitized.blockers,
                warnings: sanitized.warnings
            )
        }

        return sanitized
    }
}
