// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import MacStreamCore

@main
struct MacStreamAgent {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--status") {
            await printStatus()
            return
        }

        await AgentRuntime().run()
    }

    private static func printStatus() async {
        let settings = ((try? FileSettingsManager().load()) ?? .defaults()).normalized()
        let manager = DefaultAgentManager(
            launchAgentManager: DefaultLaunchAgentManager(
                definition: LaunchAgentDefinition(
                    executablePath: DefaultAgentExecutableResolver().resolveExecutable()?.path
                        ?? settings.agentExecutablePath
                        ?? CommandLine.arguments.first
                        ?? "macstream-agent",
                    arguments: ["run"],
                    logDirectoryPath: settings.logDirectoryURL.path
                )
            ),
            statusURL: settings.agentStatusURL,
            commandURL: settings.agentCommandURL
        )

        if let report = try? manager.readLastReport() {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(report),
               let text = String(data: data, encoding: .utf8) {
                print(text)
                return
            }
        }

        print("{}")
    }
}

private final class AgentRuntime {
    private let settingsManager = FileSettingsManager()
    private let commandDecoder: JSONDecoder
    private var lastCommandID: UUID?
    private var powerManager: PowerAssertionManaging?
    private var privacyManager: HostPrivacyManaging?

    init() {
        commandDecoder = JSONDecoder()
        commandDecoder.dateDecodingStrategy = .iso8601
    }

    func run() async {
        var shouldExit = false

        while shouldExit == false {
            let settings = ((try? settingsManager.load()) ?? .defaults()).normalized()
            let runtime = makeRuntime(settings: settings)
            powerManager = runtime.power
            privacyManager = runtime.privacy
            await runtime.privacy.apply(policy: settings.hostPrivacyPolicy)

            if let command = readCommand(from: settings.agentCommandURL),
               command.id != lastCommandID {
                lastCommandID = command.id
                shouldExit = await handle(command, runtime: runtime, settings: settings)
            }

            let report = await makeReport(runtime: runtime, settings: settings)
            try? runtime.agent.writeReport(report)

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func handle(
        _ command: MacStreamAgentCommand,
        runtime: Runtime,
        settings: MacStreamHostSettings
    ) async -> Bool {
        switch command.kind {
        case .startRemoteWork:
            do {
                try runtime.log.rotateLogs(maxBytes: 5 * 1024 * 1024, backupCount: 3)
                _ = try runtime.configuration.writeDefaultFiles(overwrite: false, audioSink: settings.audioSink)
                _ = try await runtime.power.acquire(policy: settings.powerPolicy)
                try await runtime.sunshine.start()
            } catch {
                let report = await makeReport(
                    runtime: runtime,
                    settings: settings,
                    stateOverride: .blocked,
                    blockers: [error.localizedDescription]
                )
                try? runtime.agent.writeReport(report)
            }
            return false

        case .stopRemoteWork:
            do {
                try await runtime.sunshine.stop()
            } catch SunshineManagerError.noOwnedProcess {
            } catch {
                let report = await makeReport(
                    runtime: runtime,
                    settings: settings,
                    stateOverride: .degraded,
                    warnings: [error.localizedDescription]
                )
                try? runtime.agent.writeReport(report)
            }
            _ = try? await runtime.power.release()
            return false

        case .lockHost:
            do {
                _ = try await runtime.privacy.lockHost()
            } catch {
                let report = await makeReport(
                    runtime: runtime,
                    settings: settings,
                    stateOverride: nil,
                    warnings: [error.localizedDescription]
                )
                try? runtime.agent.writeReport(report)
            }
            return false

        case .shutdown:
            do {
                try await runtime.sunshine.stop()
            } catch {
            }
            _ = try? await runtime.power.release()
            return true
        }
    }

    private func makeRuntime(settings: MacStreamHostSettings) -> Runtime {
        let audioProvider = CoreAudioDeviceProvider()
        let configuration = DefaultConfigurationManager(configDirectory: settings.configDirectoryURL)
        let binaryResolver = SettingsSunshineBinaryResolver(explicitPath: settings.sunshineBinaryPath)
        let sunshine = DefaultSunshineManager(
            binaryResolver: binaryResolver,
            configurationManager: configuration,
            logDirectoryURL: settings.logDirectoryURL
        )
        let audio = DefaultAudioDeviceManager(
            audioDeviceProvider: audioProvider,
            preferredModeOverride: settings.audioCaptureMode
        )
        let network = DefaultNetworkDiagnosticsManager()
        let launchAgent = DefaultLaunchAgentManager(
            definition: LaunchAgentDefinition(
                executablePath: settings.agentExecutablePath
                    ?? DefaultAgentExecutableResolver().resolveExecutable()?.path
                    ?? CommandLine.arguments.first
                    ?? "macstream-agent",
                arguments: ["run"],
                logDirectoryPath: settings.logDirectoryURL.path
            )
        )
        let agent = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: settings.agentStatusURL,
            commandURL: settings.agentCommandURL
        )
        let power = powerManager ?? DefaultPowerAssertionManager(initialPolicy: settings.powerPolicy)
        let privacy = privacyManager ?? DefaultHostPrivacyManager(policy: settings.hostPrivacyPolicy)

        return Runtime(
            settings: settings,
            configuration: configuration,
            sunshine: sunshine,
            blackHole: DefaultBlackHoleManager(audioDeviceProvider: audioProvider),
            permissions: DefaultPermissionManager(),
            audio: audio,
            network: network,
            engine: DefaultManagedEngineManager(
                sunshineManager: sunshine,
                audioDeviceManager: audio,
                networkDiagnosticsManager: network
            ),
            log: DefaultLogManager(logDirectoryURL: settings.logDirectoryURL),
            agent: agent,
            power: power,
            privacy: privacy
        )
    }

    private func makeReport(
        runtime: Runtime,
        settings: MacStreamHostSettings,
        stateOverride: RemoteWorkModeState? = nil,
        blockers: [String] = [],
        warnings: [String] = []
    ) async -> RemoteWorkSessionReport {
        let launchStatus = await runtime.agent.status()
        let engine = await runtime.engine.status()
        let power = await runtime.power.currentStatus()
        let privacy = await runtime.privacy.currentStatus()
        let sunshine = await runtime.sunshine.status()

        var mergedBlockers = blockers
        var mergedWarnings = warnings

        if sunshine.state == .running && sunshine.ownedProcessID == nil {
            mergedBlockers.append("Ha uma engine de video externa rodando; o MacStream nao controla este processo.")
        }

        if settings.audioCaptureMode == .blackHole2ch,
           await runtime.blackHole.installationStatus() != .installed {
            mergedWarnings.append("Rota de audio gerenciada ainda nao foi detectada.")
        }

        let state = stateOverride ?? deriveState(
            sunshine: sunshine,
            engine: engine,
            blockers: mergedBlockers
        )

        let agentStatus = MacStreamAgentStatus(
            launchAgentStatus: launchStatus.launchAgentStatus,
            isRunning: true,
            version: AppBuildInfo.current.version,
            processID: Int32(ProcessInfo.processInfo.processIdentifier),
            lastHeartbeat: Date(),
            statePath: runtime.agent.statusURL.path,
            detail: "Agente residente do MacStream ativo."
        )

        return RemoteWorkSessionReport(
            state: state,
            agentStatus: agentStatus,
            engineStatus: engine,
            powerStatus: power,
            hostPrivacyStatus: privacy,
            blockers: mergedBlockers,
            warnings: mergedWarnings,
            nextStep: nextStep(for: state, blockers: mergedBlockers, warnings: mergedWarnings)
        )
    }

    private func readCommand(from url: URL) -> MacStreamAgentCommand? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? commandDecoder.decode(MacStreamAgentCommand.self, from: data)
    }

    private func deriveState(
        sunshine: SunshineStatus,
        engine: ManagedEngineStatus,
        blockers: [String]
    ) -> RemoteWorkModeState {
        if blockers.isEmpty == false {
            return .blocked
        }

        if sunshine.state == .running && engine.aggregateStatus == .pass {
            return .running
        }

        if sunshine.state == .running {
            return .degraded
        }

        return .ready
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
            return "Prepare o MacStream antes de iniciar uma sessao remota."
        case .ready:
            return "Inicie o modo remoto pelo app ou conecte o iPad se a engine ja estiver ativa."
        case .starting:
            return "Aguarde o MacStream iniciar a sessao remota."
        case .running:
            return "Conecte pelo Moonlight e valide video, audio e entrada."
        case .degraded:
            return warnings.first ?? "Sessao remota ativa com avisos."
        case .stopping:
            return "Aguarde o MacStream parar a sessao remota."
        case .blocked:
            return "Corrija os bloqueios antes de iniciar o modo remoto."
        }
    }
}

private struct Runtime {
    var settings: MacStreamHostSettings
    var configuration: ConfigurationManaging
    var sunshine: SunshineManaging
    var blackHole: BlackHoleManaging
    var permissions: PermissionManaging
    var audio: AudioDeviceManaging
    var network: NetworkDiagnosticsManaging
    var engine: ManagedEngineManaging
    var log: LogManaging
    var agent: AgentManaging
    var power: PowerAssertionManaging
    var privacy: HostPrivacyManaging
}
