// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import MacStreamCore

@main
struct MacStreamCTL {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"
        let commandArguments = Array(arguments.dropFirst())

        switch command {
        case "doctor":
            await runDoctor(arguments: commandArguments)
        case "paths":
            printPaths(arguments: commandArguments)
        case "status":
            await printStatus(arguments: commandArguments)
        case "configure":
            configure(arguments: commandArguments)
        case "preflight":
            await preflight(arguments: commandArguments)
        case "launchagent":
            await launchAgent(arguments: commandArguments)
        case "start":
            await controlSunshine(action: .start, arguments: commandArguments)
        case "stop":
            await controlSunshine(action: .stop, arguments: commandArguments)
        case "restart":
            await controlSunshine(action: .restart, arguments: commandArguments)
        case "logs":
            await printLogs(arguments: commandArguments)
        case "support-bundle":
            await writeSupportBundle(arguments: commandArguments)
        case "reset":
            await softReset(arguments: commandArguments)
        case "webui":
            await openWebUI(arguments: commandArguments)
        default:
            printHelp()
        }
    }

    private static func runDoctor(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        await state.refresh()

        if options.json {
            let report = await state.diagnosticsReport()
            printJSON(report)
            return
        }

        print("MacStream Host Doctor")
        print("")

        for check in await state.healthCheckResult.checks {
            print("[\(symbol(for: check.status))] \(check.title): \(check.detail)")
        }

        print("")
        print("Result: \(await state.healthCheckResult.status.rawValue.uppercased())")
        print("Next action: \(await state.healthCheckResult.recommendedNextStep)")
    }

    private static func printPaths(arguments: [String]) {
        let options = parseRuntimeOptions(arguments)
        let settings = makeSettings(options: options)
        let manager = DefaultConfigurationManager(configDirectory: settings.configDirectoryURL)
        print("Config directory: \(manager.configDirectory.path)")
        print("sunshine.conf: \(manager.sunshineConfigURL.path)")
        print("apps.json: \(manager.appsJSONURL.path)")
        print("Log directory: \(settings.logDirectoryURL.path)")
        print("Sunshine binary: \(settings.sunshineBinaryPath ?? DefaultSunshineBinaryResolver().resolveBinary()?.path ?? "not configured")")
    }

    private static func configure(arguments: [String]) {
        let options = parseConfigurationOptions(arguments)
        let runtimeOptions = RuntimeCLIOptions(
            configDirectoryPath: options.configDirectoryPath,
            sunshineBinaryPath: nil,
            logDirectoryPath: nil,
            audioCaptureMode: options.audioSinkWasSpecified
                ? (options.audioSink == nil ? .nativeSystemAudio : .blackHole2ch)
                : nil
        )
        let settings = makeSettings(options: runtimeOptions)
        let manager = DefaultConfigurationManager(configDirectory: settings.configDirectoryURL)
        let audioSink = options.audioSinkWasSpecified ? options.audioSink : settings.audioSink

        do {
            let results = try manager.writeDefaultFiles(overwrite: options.overwrite, audioSink: audioSink)

            print("MacStream Host configuration")
            print("Config directory: \(manager.configDirectory.path)")
            print("")

            for result in results {
                print("\(result.action.description): \(result.url.path)")
                if let backupURL = result.backupURL {
                    print("  backup: \(backupURL.path)")
                }
            }
        } catch {
            print("Failed to write configuration: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func preflight(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        let configurationManager = await state.configurationManager
        let runtimeSettings = await state.runtimeSettings

        do {
            let results = try configurationManager.writeDefaultFiles(
                overwrite: options.overwrite,
                audioSink: runtimeSettings.audioSink
            )
            print("MacStream Host preflight")
            print("")
            print("Configuration:")
            for result in results {
                print("- \(result.action.description): \(result.url.path)")
            }

            if options.startAfterPreflight {
                try await state.sunshineManager.start()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                print("")
                print("Sunshine: start requested with MacStream Host ownership.")
            }

            await state.refresh()

            if options.json {
                let report = await state.diagnosticsReport()
                printJSON(report)
                return
            }

            let dashboard = await state.dashboard
            print("")
            print("Readiness:")
            print("- Sunshine: \(dashboard.sunshineStatus.state.displayName)")
            print("- Web UI: \(dashboard.sunshineStatus.webUIReachable ? "reachable" : "not reachable")")
            print("- BlackHole: \(dashboard.blackHoleStatus.displayName)")
            print("- Permissions: \(dashboard.permissionsStatus.aggregateStatus.displayName)")
            print("- Network: \(dashboard.networkStatus.aggregateStatus.displayName)")
            print("- Local IPs: \(dashboard.networkStatus.localAddresses.joined(separator: ", "))")
            if let tailscale = dashboard.networkStatus.tailscaleAddress {
                print("- Tailscale: \(tailscale)")
            }
            print("")
            print("Next action: \(await state.healthCheckResult.recommendedNextStep)")
            print("Pairing: open the Sunshine Web UI, then add this Mac in Moonlight using one of the listed IPs.")
        } catch {
            print("Preflight failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func printStatus(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        await state.refresh()

        if options.json {
            let report = await state.diagnosticsReport()
            printJSON(report)
            return
        }

        let dashboard = await state.dashboard
        print("Sunshine: \(dashboard.sunshineStatus.state.displayName)")
        if let binaryPath = dashboard.sunshineStatus.binaryPath {
            print("Sunshine binary: \(binaryPath)")
        }
        print("Sunshine Web UI: \(dashboard.sunshineStatus.webUIReachable ? "reachable" : "not reachable")")
        print("BlackHole: \(dashboard.blackHoleStatus.displayName)")
        let audioDevices = await state.audioDeviceManager.listAudioDevices()
        let preferredAudioMode = await state.audioDeviceManager.preferredCaptureMode()
        print("Audio devices: \(audioDevices.count)")
        print("Preferred audio mode: \(preferredAudioMode.displayName)")
        print("Permissions: \(dashboard.permissionsStatus.aggregateStatus.displayName)")
        for permission in dashboard.permissionsStatus.checks {
            print("\(permission.id.displayName): \(permission.status.displayName)")
        }
        print("Network: \(dashboard.networkStatus.aggregateStatus.displayName)")
        print("Local addresses: \(dashboard.networkStatus.localAddresses.joined(separator: ", "))")
        if let tailscaleAddress = dashboard.networkStatus.tailscaleAddress {
            print("Tailscale address: \(tailscaleAddress)")
        }
        for portCheck in dashboard.networkStatus.portChecks {
            print("\(portCheck.protocolKind.rawValue.uppercased()) \(portCheck.port) \(portCheck.name): \(portCheck.status.displayName)")
        }
        let launchAgentStatus = await state.launchAgentManager.status()
        print("LaunchAgent: \(launchAgentStatus.displayName)")
    }

    private static func launchAgent(arguments: [String]) async {
        let options = parseLaunchAgentOptions(arguments)
        let manager = makeLaunchAgentManager(options: options)

        switch options.action {
        case "status":
            let status = await manager.status()
            print("LaunchAgent: \(status.displayName)")
            print("Label: \(manager.label)")
            print("Installed plist: \(manager.installedPlistURL.path)")
            print("Draft plist: \(manager.draftPlistURL.path)")
        case "preview":
            do {
                print(try manager.renderPlist())
            } catch {
                print("Failed to render LaunchAgent plist: \(error.localizedDescription)")
                Foundation.exit(1)
            }
        case "generate":
            do {
                let result = try manager.writeDraftLaunchAgent(overwrite: options.overwrite)
                print("\(result.action.description): \(result.url.path)")
                if let backupURL = result.backupURL {
                    print("backup: \(backupURL.path)")
                }
                print("No launchctl command was run.")
            } catch {
                print("Failed to generate LaunchAgent draft: \(error.localizedDescription)")
                Foundation.exit(1)
            }
        case "install":
            do {
                try await manager.installLaunchAgent()
                print("LaunchAgent installed: \(manager.installedPlistURL.path)")
            } catch {
                print("Failed to install LaunchAgent: \(error.localizedDescription)")
                Foundation.exit(1)
            }
        case "load":
            do {
                try await manager.load()
                print("LaunchAgent loaded: \(manager.label)")
            } catch {
                print("Failed to load LaunchAgent: \(error.localizedDescription)")
                Foundation.exit(1)
            }
        case "unload":
            do {
                try await manager.unload()
                print("LaunchAgent unloaded: \(manager.label)")
            } catch {
                print("Failed to unload LaunchAgent: \(error.localizedDescription)")
                Foundation.exit(1)
            }
        case "uninstall", "remove":
            do {
                try await manager.uninstallLaunchAgent()
                print("LaunchAgent removed: \(manager.installedPlistURL.path)")
            } catch {
                print("Failed to remove LaunchAgent: \(error.localizedDescription)")
                Foundation.exit(1)
            }
        default:
            print("Unknown launchagent action: \(options.action)")
            Foundation.exit(1)
        }
    }

    private static func controlSunshine(action: SunshineControlAction, arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        let manager = await state.sunshineManager

        do {
            switch action {
            case .start:
                try await manager.start()
                print("Sunshine start requested with MacStream Host ownership.")
            case .stop:
                try await manager.stop()
                print("Owned Sunshine process stopped.")
            case .restart:
                try await manager.restart()
                print("Owned Sunshine process restarted.")
            }
        } catch {
            print("Sunshine \(action.rawValue) failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func printLogs(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        let logs = await state.logManager.recentLogs(maxLines: options.maxLogLines)

        if options.json {
            printJSON(logs)
            return
        }

        if logs.isEmpty {
            print("No MacStream Host logs found.")
            return
        }

        for log in logs {
            print("[\(log.subsystem)] \(log.message)")
        }
    }

    private static func writeSupportBundle(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        let report = await state.diagnosticsReport()
        let defaultOutputURL = await state.logManager.logDirectoryURL
            .appendingPathComponent("SupportBundles", isDirectory: true)
        let outputURL = URL(
            fileURLWithPath: expandTilde(options.outputPath ?? defaultOutputURL.path),
            isDirectory: true
        )
        let service = await DefaultSupportBundleService(
            logManager: state.logManager,
            configurationManager: state.configurationManager
        )

        do {
            let result = try await service.writeBundle(to: outputURL, diagnostics: report)
            if options.json {
                printJSON(result)
            } else {
                print("Support bundle: \(result.directoryPath)")
                for file in result.files {
                    print("- \(file)")
                }
            }
        } catch {
            print("Failed to write support bundle: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func softReset(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        guard options.confirmReset else {
            print("Refusing reset without --confirm. This only resets MacStream Host owned files/processes.")
            Foundation.exit(1)
        }

        let state = await makeAppState(options: options)
        let service = await DefaultSoftResetService(
            sunshineManager: state.sunshineManager,
            launchAgentManager: state.launchAgentManager,
            configurationManager: state.configurationManager
        )

        do {
            let result = try await service.reset()
            if options.json {
                printJSON(result)
            } else {
                print("MacStream Host soft reset")
                for action in result.actions {
                    print("- \(action)")
                }
            }
        } catch {
            print("Reset failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func openWebUI(arguments: [String]) async {
        let options = parseRuntimeOptions(arguments)
        let state = await makeAppState(options: options)
        do {
            try await state.sunshineManager.openWebUI()
            print("Opened Sunshine Web UI.")
        } catch {
            print("Failed to open Sunshine Web UI: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func printHelp() {
        print("""
        macstreamctl

        Commands:
          doctor      Run a local health check with safe Sunshine discovery.
          paths       Print active configuration, log, and binary paths.
          status      Print dashboard status with safe Sunshine discovery.
          configure   Write safe default sunshine.conf and apps.json.
          preflight   Write config, validate runtime state, and optionally start Sunshine.
          launchagent Generate or inspect a safe LaunchAgent draft.
          start       Start Sunshine only when no external Sunshine is running.
          stop        Stop only a Sunshine process owned by MacStream Host.
          restart     Restart only through MacStream Host ownership.
          webui       Open the local Sunshine Web UI.
          logs        Print recent MacStream Host and Sunshine logs.
          support-bundle
                      Export sanitized diagnostics, logs, and config.
          reset       Soft reset only MacStream Host owned state; requires --confirm.

        Shared options:
          --json                 Print JSON for doctor/status/logs/reset.
          --sunshine-binary PATH Override Sunshine binary path.
          --config-dir PATH      Override config directory.
          --log-dir PATH         Override log directory.
          --native-audio         Prefer native macOS audio capture.
          --audio-sink NAME      Prefer BlackHole when NAME is "BlackHole 2ch".
          --output PATH          Output parent directory for support-bundle.
          --overwrite            Backup and replace config during preflight/configure.
          --start                Start Sunshine after preflight config validation.

        Configure options:
          --config-dir PATH       Override config directory.
          --overwrite             Backup and replace existing files.
          --audio-sink NAME       Set audio_sink, for example "BlackHole 2ch".
          --native-audio          Leave audio_sink empty for native macOS capture validation.

        LaunchAgent commands:
          launchagent status
          launchagent preview
          launchagent generate [--overwrite]
          launchagent install
          launchagent load
          launchagent unload
          launchagent uninstall

        LaunchAgent options:
          --sunshine-binary PATH   Override Sunshine binary path in plist.
          --config PATH            Override Sunshine config path in plist.
          --log-dir PATH           Override Sunshine log directory in plist.
          --output PATH            Write draft plist to this path.
          --overwrite              Backup and replace existing draft plist.
        """)
    }

    private static func symbol(for status: CheckStatus) -> String {
        switch status {
        case .pass: return "OK"
        case .warning: return "!!"
        case .fail: return "FAIL"
        case .unknown: return "??"
        }
    }

    private static func parseConfigurationOptions(_ arguments: [String]) -> ConfigurationCLIOptions {
        var options = ConfigurationCLIOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--overwrite":
                options.overwrite = true
            case "--native-audio":
                options.audioSink = nil
                options.audioSinkWasSpecified = true
            case "--audio-sink":
                guard index + 1 < arguments.count else {
                    print("Missing value for --audio-sink")
                    Foundation.exit(1)
                }
                options.audioSink = arguments[index + 1]
                options.audioSinkWasSpecified = true
                index += 1
            case "--config-dir":
                guard index + 1 < arguments.count else {
                    print("Missing value for --config-dir")
                    Foundation.exit(1)
                }
                options.configDirectoryPath = arguments[index + 1]
                index += 1
            default:
                print("Unknown option: \(argument)")
                Foundation.exit(1)
            }

            index += 1
        }

        return options
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func makeLaunchAgentManager(options: LaunchAgentCLIOptions) -> DefaultLaunchAgentManager {
        let settings = makeSettings(options: options.runtimeOptions)
        let resolver = SettingsSunshineBinaryResolver(explicitPath: settings.sunshineBinaryPath)
        let sunshineBinaryPath = options.sunshineBinaryPath
            ?? resolver.resolveBinary()?.path
            ?? settings.sunshineBinaryPath
            ?? "/opt/homebrew/bin/sunshine"
        let configPath = options.configPath ?? settings.sunshineConfigURL.path
        let logDirectory = options.logDirectoryPath ?? settings.logDirectoryURL.path
        let definition = LaunchAgentDefinition(
            sunshineBinaryPath: expandTilde(sunshineBinaryPath),
            sunshineConfigPath: expandTilde(configPath),
            logDirectoryPath: expandTilde(logDirectory)
        )

        if let outputPath = options.outputPath {
            return DefaultLaunchAgentManager(
                definition: definition,
                draftPlistURL: URL(fileURLWithPath: expandTilde(outputPath))
            )
        }

        return DefaultLaunchAgentManager(definition: definition)
    }

    private static func parseLaunchAgentOptions(_ arguments: [String]) -> LaunchAgentCLIOptions {
        var options = LaunchAgentCLIOptions()
        var index = 0

        if let first = arguments.first, !first.hasPrefix("--") {
            options.action = first
            index = 1
        }

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--overwrite":
                options.overwrite = true
            case "--sunshine-binary":
                guard index + 1 < arguments.count else {
                    print("Missing value for --sunshine-binary")
                    Foundation.exit(1)
                }
                options.sunshineBinaryPath = arguments[index + 1]
                index += 1
            case "--config":
                guard index + 1 < arguments.count else {
                    print("Missing value for --config")
                    Foundation.exit(1)
                }
                options.configPath = arguments[index + 1]
                index += 1
            case "--log-dir":
                guard index + 1 < arguments.count else {
                    print("Missing value for --log-dir")
                    Foundation.exit(1)
                }
                options.logDirectoryPath = arguments[index + 1]
                index += 1
            case "--output":
                guard index + 1 < arguments.count else {
                    print("Missing value for --output")
                    Foundation.exit(1)
                }
                options.outputPath = arguments[index + 1]
                index += 1
            case "--config-dir":
                guard index + 1 < arguments.count else {
                    print("Missing value for --config-dir")
                    Foundation.exit(1)
                }
                options.runtimeOptions.configDirectoryPath = arguments[index + 1]
                index += 1
            default:
                print("Unknown option: \(argument)")
                Foundation.exit(1)
            }

            index += 1
        }

        return options
    }

    private static func parseRuntimeOptions(_ arguments: [String]) -> RuntimeCLIOptions {
        var options = RuntimeCLIOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--json":
                options.json = true
            case "--confirm":
                options.confirmReset = true
            case "--overwrite":
                options.overwrite = true
            case "--start":
                options.startAfterPreflight = true
            case "--native-audio":
                options.audioCaptureMode = .nativeSystemAudio
            case "--audio-sink":
                guard index + 1 < arguments.count else {
                    print("Missing value for --audio-sink")
                    Foundation.exit(1)
                }
                let value = arguments[index + 1]
                options.audioCaptureMode = value.localizedCaseInsensitiveContains("blackhole") ? .blackHole2ch : .manualDevice
                index += 1
            case "--config-dir":
                guard index + 1 < arguments.count else {
                    print("Missing value for --config-dir")
                    Foundation.exit(1)
                }
                options.configDirectoryPath = arguments[index + 1]
                index += 1
            case "--sunshine-binary":
                guard index + 1 < arguments.count else {
                    print("Missing value for --sunshine-binary")
                    Foundation.exit(1)
                }
                options.sunshineBinaryPath = arguments[index + 1]
                index += 1
            case "--log-dir":
                guard index + 1 < arguments.count else {
                    print("Missing value for --log-dir")
                    Foundation.exit(1)
                }
                options.logDirectoryPath = arguments[index + 1]
                index += 1
            case "--lines":
                guard index + 1 < arguments.count, let lines = Int(arguments[index + 1]) else {
                    print("Missing numeric value for --lines")
                    Foundation.exit(1)
                }
                options.maxLogLines = lines
                index += 1
            case "--output":
                guard index + 1 < arguments.count else {
                    print("Missing value for --output")
                    Foundation.exit(1)
                }
                options.outputPath = arguments[index + 1]
                index += 1
            default:
                print("Unknown option: \(argument)")
                Foundation.exit(1)
            }

            index += 1
        }

        return options
    }

    private static func makeAppState(options: RuntimeCLIOptions) async -> AppState {
        await AppState.localDiagnostics(settingsManager: CLISettingsManager(settings: makeSettings(options: options)))
    }

    private static func makeSettings(options: RuntimeCLIOptions) -> MacStreamHostSettings {
        var settings = ((try? FileSettingsManager().load()) ?? .defaults()).normalized()

        if let configDirectoryPath = options.configDirectoryPath {
            settings.configDirectoryPath = expandTilde(configDirectoryPath)
        }

        if let sunshineBinaryPath = options.sunshineBinaryPath {
            settings.sunshineBinaryPath = expandTilde(sunshineBinaryPath)
        }

        if let logDirectoryPath = options.logDirectoryPath {
            settings.logDirectoryPath = expandTilde(logDirectoryPath)
        }

        if let audioCaptureMode = options.audioCaptureMode {
            settings.audioCaptureMode = audioCaptureMode
        }

        return settings.normalized()
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(value)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            print("Failed to encode JSON: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }
}

private struct ConfigurationCLIOptions {
    var overwrite = false
    var audioSink: String?
    var audioSinkWasSpecified = false
    var configDirectoryPath: String?
}

private struct LaunchAgentCLIOptions {
    var action = "status"
    var overwrite = false
    var runtimeOptions = RuntimeCLIOptions()
    var sunshineBinaryPath: String?
    var configPath: String?
    var logDirectoryPath: String?
    var outputPath: String?
}

private struct RuntimeCLIOptions {
    var json = false
    var confirmReset = false
    var overwrite = false
    var startAfterPreflight = false
    var configDirectoryPath: String?
    var sunshineBinaryPath: String?
    var logDirectoryPath: String?
    var outputPath: String?
    var audioCaptureMode: AudioCaptureMode?
    var maxLogLines = 80
}

private enum SunshineControlAction: String {
    case start
    case stop
    case restart
}

private final class CLISettingsManager: SettingsManaging {
    let settingsURL = URL(fileURLWithPath: "/dev/null")
    private var settings: MacStreamHostSettings

    init(settings: MacStreamHostSettings) {
        self.settings = settings
    }

    func load() throws -> MacStreamHostSettings {
        settings
    }

    func save(_ settings: MacStreamHostSettings) throws {
        self.settings = settings
    }

    func reset() throws -> MacStreamHostSettings {
        settings = .defaults()
        return settings
    }
}

private extension ConfigurationFileAction {
    var description: String {
        switch self {
        case .created: return "created"
        case .skippedExisting: return "skipped existing"
        case .backedUpAndReplaced: return "backed up and replaced"
        }
    }
}
