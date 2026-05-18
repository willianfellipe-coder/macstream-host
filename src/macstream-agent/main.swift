// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import MacStreamCore

@main
struct MacStreamAgent {
    static func main() async {
        // Tell LaunchServices we're a background helper (no Dock icon,
        // no AppSwitcher entry). Without this, macOS treats the agent
        // as a regular .app — and because the agent and the MacStream
        // Host GUI share `Identifier=org.macstream.host` (necessary
        // for the TCC disclaim chain), LaunchServices groups the agent
        // into the parent bundle's Dock entry. Result: the user sees
        // a "ghost" MacStream Host icon in the Dock even with the GUI
        // fully closed. Setting .accessory here suppresses that.
        NSApplication.shared.setActivationPolicy(.accessory)

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

struct AgentLogger {
    enum Level: String { case info = "INFO", warn = "WARN", error = "ERROR" }
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func info(_ message: String) { emit(.info, message, stream: stdout) }
    func warn(_ message: String) { emit(.warn, message, stream: stderr) }
    func error(_ message: String) { emit(.error, message, stream: stderr) }

    private let stdout = FileHandle.standardOutput
    private let stderr = FileHandle.standardError

    private func emit(_ level: Level, _ message: String, stream: FileHandle) {
        let line = "[\(Self.formatter.string(from: Date()))] [\(level.rawValue)] [agent] \(message)\n"
        if let data = line.data(using: .utf8) {
            try? stream.write(contentsOf: data)
        }
    }
}

private final class AgentRuntime {
    private let settingsManager = FileSettingsManager()
    private let commandDecoder: JSONDecoder
    private let logger = AgentLogger()
    private var lastCommandID: UUID?
    private var powerManager: PowerAssertionManaging?
    private var privacyManager: HostPrivacyManaging?

    /// Set to true after a successful `.startRemoteWork`; reset on stop or
    /// shutdown. When true and the engine isn't running, the supervision
    /// loop attempts to bring it back. Without this flag we'd respawn an
    /// engine the user explicitly stopped.
    private var remoteWorkActive: Bool = false

    /// Timestamps of recent auto-respawn attempts. Used to apply a
    /// circuit-breaker: at most 3 restarts within a 60-second window so a
    /// persistently-crashing engine (e.g. permanent TCC failure) doesn't
    /// burn the CPU in a tight restart loop.
    private var engineRestartAttempts: [Date] = []
    private let engineRestartWindow: TimeInterval = 60
    private let engineRestartMaxAttempts: Int = 3

    /// PID we expect the engine to be running with. Updated whenever we
    /// see it healthy and used to detect transitions to "unexpectedly
    /// dead" (the parent process didn't request a stop but the engine
    /// stopped running anyway — typically the
    /// `+[AVVideo displayNames]` NSDictionary-nil crash post sleep/wake).
    private var lastSeenEnginePID: Int32?

    init() {
        commandDecoder = JSONDecoder()
        commandDecoder.dateDecodingStrategy = .iso8601
    }

    func run() async {
        logger.info("macstream-agent started (pid \(ProcessInfo.processInfo.processIdentifier), version \(AppBuildInfo.current.version))")
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
                logger.info("received command \(command.kind.rawValue) (id \(command.id.uuidString))")
                shouldExit = await handle(command, runtime: runtime, settings: settings)
            }

            // Supervise the engine: when the user has asked for remote work
            // to be active but the engine stopped running (Sunshine likes to
            // crash with NSDictionary-nil after macOS revokes screen capture
            // permission post sleep/wake), bring it back. Rate-limited so a
            // permanently-broken engine doesn't enter a restart loop.
            await superviseEngineIfNeeded(runtime: runtime, settings: settings)

            let report = await makeReport(runtime: runtime, settings: settings)
            do {
                try runtime.agent.writeReport(report)
            } catch {
                logger.warn("failed to write status report: \(error.localizedDescription)")
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        logger.info("macstream-agent exiting")
    }

    /// Re-spawns the video engine when it's supposed to be running but
    /// isn't. Skips when the user has not started remote work mode, and
    /// when the circuit-breaker has tripped.
    private func superviseEngineIfNeeded(
        runtime: Runtime,
        settings: MacStreamHostSettings
    ) async {
        guard remoteWorkActive else { return }

        let status = await runtime.sunshine.status()
        switch status.state {
        case .running:
            // Healthy. Remember the current PID so we'd notice if it
            // changed without us asking.
            lastSeenEnginePID = status.ownedProcessID
            return
        case .notInstalled:
            // Nothing to respawn — the binary is gone (rare, e.g. user
            // moved the app out of /Applications mid-session).
            logger.warn("engine binary missing while remote work is active; not attempting respawn")
            remoteWorkActive = false
            return
        default:
            break
        }

        let now = Date()
        engineRestartAttempts.removeAll { now.timeIntervalSince($0) > engineRestartWindow }
        guard engineRestartAttempts.count < engineRestartMaxAttempts else {
            // Circuit broken — surface the situation but stop pounding.
            // The user will see "Engine de video parada" in the dashboard
            // and can intervene (re-grant Screen Recording, etc).
            return
        }

        engineRestartAttempts.append(now)
        let priorPIDDescription = lastSeenEnginePID.map { "(was pid \($0))" } ?? "(no prior pid)"
        logger.warn("engine stopped unexpectedly \(priorPIDDescription); attempting respawn \(engineRestartAttempts.count)/\(engineRestartMaxAttempts)")

        do {
            try await runtime.sunshine.start()
            logger.info("engine respawn succeeded")
            // Refresh recorded PID on next loop iteration via the
            // `.running` branch above. No need to capture it here — the
            // resolver in DefaultSunshineManager.status() handles it.
        } catch {
            logger.error("engine respawn failed: \(error.localizedDescription)")
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
                _ = try runtime.configuration.writeDefaultFiles(
                    overwrite: false,
                    audioSink: settings.audioSink,
                    lowLatency: settings.lowLatencyMode
                )
                _ = try await runtime.power.acquire(policy: settings.powerPolicy)
                try await runtime.sunshine.start()
                logger.info("started remote work mode")
                // Arm the supervision loop. From here on, an unexpected
                // engine death triggers an auto-respawn (rate-limited).
                remoteWorkActive = true
                engineRestartAttempts.removeAll()
                lastSeenEnginePID = nil
            } catch {
                logger.error("failed to start remote work mode: \(error.localizedDescription)")
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
            // Disarm the supervision loop FIRST so a slow-stopping engine
            // doesn't get respawned by us between the stop call and the
            // process actually exiting.
            remoteWorkActive = false
            engineRestartAttempts.removeAll()
            lastSeenEnginePID = nil
            do {
                try await runtime.sunshine.stop()
                logger.info("stopped remote work mode")
            } catch SunshineManagerError.noOwnedProcess {
                logger.info("stop requested but no MacStream-owned video process was running")
            } catch {
                logger.warn("stop encountered an error: \(error.localizedDescription)")
                let report = await makeReport(
                    runtime: runtime,
                    settings: settings,
                    stateOverride: .degraded,
                    warnings: [error.localizedDescription]
                )
                try? runtime.agent.writeReport(report)
            }
            if (try? await runtime.power.release()) == nil {
                logger.warn("power assertion release failed")
            }
            return false

        case .lockHost:
            do {
                _ = try await runtime.privacy.lockHost()
                logger.info("system-suspend host lock issued")
            } catch {
                logger.warn("host lock failed: \(error.localizedDescription)")
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
            logger.info("shutdown command received")
            // Same as stopRemoteWork — disarm before the actual stop call
            // so we don't race the respawn supervisor.
            remoteWorkActive = false
            engineRestartAttempts.removeAll()
            lastSeenEnginePID = nil
            do {
                try await runtime.sunshine.stop()
            } catch {
                logger.warn("shutdown stop failed: \(error.localizedDescription)")
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
        let mergedWarnings = warnings

        if sunshine.state == .running && sunshine.ownedProcessID == nil {
            mergedBlockers.append("Ha uma engine de video externa rodando; o MacStream nao controla este processo.")
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
