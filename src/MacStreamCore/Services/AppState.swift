// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var dashboard: DashboardSnapshot
    @Published public private(set) var setupChecklist: [SetupChecklistItem]
    @Published public private(set) var healthCheckResult: HealthCheckResult
    @Published public private(set) var isSunshineOperationInProgress: Bool
    @Published public private(set) var lastSunshineOperationMessage: String?
    @Published public private(set) var runtimeSettings: MacStreamHostSettings
    @Published public private(set) var lastOperationMessage: String?

    public private(set) var sunshineManager: SunshineManaging
    public private(set) var blackHoleManager: BlackHoleManaging
    public private(set) var permissionManager: PermissionManaging
    public private(set) var audioDeviceManager: AudioDeviceManaging
    public private(set) var networkDiagnosticsManager: NetworkDiagnosticsManaging
    public private(set) var launchAgentManager: LaunchAgentManaging
    public private(set) var configurationManager: ConfigurationManaging
    public private(set) var settingsManager: SettingsManaging
    public private(set) var logManager: LogManaging
    public private(set) var pairingGuide: MoonlightPairingGuiding
    public private(set) var healthCheckService: HealthCheckServicing

    public init(
        sunshineManager: SunshineManaging,
        blackHoleManager: BlackHoleManaging,
        permissionManager: PermissionManaging,
        audioDeviceManager: AudioDeviceManaging,
        networkDiagnosticsManager: NetworkDiagnosticsManaging,
        launchAgentManager: LaunchAgentManaging,
        configurationManager: ConfigurationManaging,
        settingsManager: SettingsManaging,
        runtimeSettings: MacStreamHostSettings,
        logManager: LogManaging,
        pairingGuide: MoonlightPairingGuiding,
        healthCheckService: HealthCheckServicing
    ) {
        self.sunshineManager = sunshineManager
        self.blackHoleManager = blackHoleManager
        self.permissionManager = permissionManager
        self.audioDeviceManager = audioDeviceManager
        self.networkDiagnosticsManager = networkDiagnosticsManager
        self.launchAgentManager = launchAgentManager
        self.configurationManager = configurationManager
        self.settingsManager = settingsManager
        self.runtimeSettings = runtimeSettings
        self.logManager = logManager
        self.pairingGuide = pairingGuide
        self.healthCheckService = healthCheckService
        self.dashboard = .initial
        self.setupChecklist = []
        self.healthCheckResult = HealthCheckResult(checks: [])
        self.isSunshineOperationInProgress = false
        self.lastSunshineOperationMessage = nil
        self.lastOperationMessage = nil
    }

    public static func localDiagnostics(settingsManager: SettingsManaging = FileSettingsManager()) -> AppState {
        let settings = ((try? settingsManager.load()) ?? .defaults()).normalized()
        let dependencies = makeRuntimeDependencies(settings: settings)

        return AppState(
            sunshineManager: dependencies.sunshine,
            blackHoleManager: dependencies.blackHole,
            permissionManager: dependencies.permissions,
            audioDeviceManager: dependencies.audio,
            networkDiagnosticsManager: dependencies.network,
            launchAgentManager: dependencies.launchAgent,
            configurationManager: dependencies.configuration,
            settingsManager: settingsManager,
            runtimeSettings: settings,
            logManager: dependencies.log,
            pairingGuide: DefaultMoonlightPairingGuide(),
            healthCheckService: dependencies.health
        )
    }

    private static func makeRuntimeDependencies(settings: MacStreamHostSettings) -> RuntimeDependencies {
        let audioDeviceProvider = CoreAudioDeviceProvider()
        let configuration = DefaultConfigurationManager(configDirectory: settings.configDirectoryURL)
        let binaryResolver = SettingsSunshineBinaryResolver(explicitPath: settings.sunshineBinaryPath)
        let sunshineBinaryPath = binaryResolver.resolveBinary()?.path
            ?? settings.sunshineBinaryPath
            ?? "/opt/homebrew/bin/sunshine"
        let sunshine = DefaultSunshineManager(
            binaryResolver: binaryResolver,
            configurationManager: configuration,
            logDirectoryURL: settings.logDirectoryURL
        )
        let blackHole = DefaultBlackHoleManager(audioDeviceProvider: audioDeviceProvider)
        let permissions = DefaultPermissionManager()
        let audio = DefaultAudioDeviceManager(
            audioDeviceProvider: audioDeviceProvider,
            preferredModeOverride: settings.audioCaptureMode
        )
        let network = DefaultNetworkDiagnosticsManager()
        let log = DefaultLogManager(logDirectoryURL: settings.logDirectoryURL)
        let launchAgent = DefaultLaunchAgentManager(
            definition: LaunchAgentDefinition(
                sunshineBinaryPath: sunshineBinaryPath,
                sunshineConfigPath: settings.sunshineConfigURL.path,
                logDirectoryPath: settings.logDirectoryURL.path
            )
        )
        let health = DefaultHealthCheckService(
                sunshineManager: sunshine,
                blackHoleManager: blackHole,
                permissionManager: permissions,
                audioDeviceManager: audio,
                networkDiagnosticsManager: network,
                launchAgentManager: launchAgent,
                logManager: log
            )

        return RuntimeDependencies(
            sunshine: sunshine,
            blackHole: blackHole,
            permissions: permissions,
            audio: audio,
            network: network,
            launchAgent: launchAgent,
            configuration: configuration,
            log: log,
            health: health
        )
    }

    public func refresh() async {
        let sunshine = await sunshineManager.status()
        let blackHole = await blackHoleManager.installationStatus()
        let permissions = await permissionManager.currentStatus()
        let network = await networkDiagnosticsManager.runDiagnostics()
        let health = await healthCheckService.runHealthCheck()

        dashboard = DashboardSnapshot(
            sunshineStatus: sunshine,
            blackHoleStatus: blackHole,
            permissionsStatus: permissions,
            networkStatus: network,
            recommendedNextStep: health.recommendedNextStep
        )
        setupChecklist = makeSetupChecklist(
            sunshine: sunshine,
            blackHole: blackHole,
            permissions: permissions,
            network: network
        )
        healthCheckResult = health
    }

    public func createDefaultSunshineConfiguration() async {
        await runSunshineOperation(successMessage: "Configuração padrão do Sunshine gerada.") {
            _ = try configurationManager.writeDefaultFiles(overwrite: false, audioSink: runtimeSettings.audioSink)
        }
    }

    public func startSunshine() async {
        await runSunshineOperation(successMessage: "Sunshine iniciado com ownership do MacStream Host.") {
            try await sunshineManager.start()
        }
    }

    public func stopSunshine() async {
        await runSunshineOperation(successMessage: "Processo Sunshine owned pelo MacStream Host parado.") {
            try await sunshineManager.stop()
        }
    }

    public func restartSunshine() async {
        await runSunshineOperation(successMessage: "Processo Sunshine owned pelo MacStream Host reiniciado.") {
            try await sunshineManager.restart()
        }
    }

    public func openSunshineWebUI() async {
        await runOperation(successMessage: "Web UI do Sunshine aberta.") {
            try await sunshineManager.openWebUI()
        }
    }

    public func openSettings(for permission: MacPermission) async {
        await runOperation(successMessage: "Ajustes de \(permission.displayName) abertos.") {
            try await permissionManager.openSettings(for: permission)
        }
    }

    public func installLaunchAgent() async {
        await runOperation(successMessage: "LaunchAgent instalado.") {
            try await launchAgentManager.installLaunchAgent()
        }
    }

    public func loadLaunchAgent() async {
        await runOperation(successMessage: "LaunchAgent carregado.") {
            try await launchAgentManager.load()
        }
    }

    public func unloadLaunchAgent() async {
        await runOperation(successMessage: "LaunchAgent descarregado.") {
            try await launchAgentManager.unload()
        }
    }

    public func removeLaunchAgent() async {
        await runOperation(successMessage: "LaunchAgent removido.") {
            try await launchAgentManager.uninstallLaunchAgent()
        }
    }

    public func updateAudioCaptureMode(_ mode: AudioCaptureMode) async {
        var settings = runtimeSettings
        settings.audioCaptureMode = mode
        await saveSettings(settings, successMessage: "Modo de áudio salvo.")
    }

    public func saveSettings(
        sunshineBinaryPath: String?,
        configDirectoryPath: String,
        logDirectoryPath: String,
        audioCaptureMode: AudioCaptureMode
    ) async {
        let settings = MacStreamHostSettings(
            sunshineBinaryPath: sunshineBinaryPath?.isEmpty == true ? nil : sunshineBinaryPath,
            configDirectoryPath: configDirectoryPath,
            logDirectoryPath: logDirectoryPath,
            audioCaptureMode: audioCaptureMode
        )

        await saveSettings(settings, successMessage: "Preferências salvas.")
    }

    public func diagnosticsReport() async -> DiagnosticsReport {
        await refresh()
        return DiagnosticsReport(
            settings: runtimeSettings,
            dashboard: dashboard,
            health: healthCheckResult,
            audioDevices: await audioDeviceManager.listAudioDevices(),
            preferredAudioMode: await audioDeviceManager.preferredCaptureMode(),
            launchAgentStatus: await launchAgentManager.status()
        )
    }

    public func exportDiagnosticsSummary() async -> String {
        await logManager.exportDiagnosticsSummary()
    }

    public func writeSupportBundle(to parentDirectory: URL) async -> SupportBundleResult? {
        do {
            let report = await diagnosticsReport()
            let service = DefaultSupportBundleService(
                logManager: logManager,
                configurationManager: configurationManager
            )
            let result = try await service.writeBundle(to: parentDirectory, diagnostics: report)
            lastOperationMessage = "Pacote de suporte criado em \(result.directoryPath)."
            return result
        } catch {
            lastOperationMessage = error.localizedDescription
            await refresh()
            return nil
        }
    }

    public func softReset() async {
        await runOperation(successMessage: "Reset soft concluído.") {
            let service = DefaultSoftResetService(
                sunshineManager: sunshineManager,
                launchAgentManager: launchAgentManager,
                configurationManager: configurationManager
            )
            _ = try await service.reset()
        }
    }

    private func runSunshineOperation(successMessage: String, operation: () async throws -> Void) async {
        guard isSunshineOperationInProgress == false else { return }

        isSunshineOperationInProgress = true
        defer { isSunshineOperationInProgress = false }

        do {
            try await operation()
            lastSunshineOperationMessage = successMessage
        } catch {
            lastSunshineOperationMessage = error.localizedDescription
        }

        await refresh()
    }

    private func runOperation(successMessage: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            lastOperationMessage = successMessage
        } catch {
            lastOperationMessage = error.localizedDescription
        }

        await refresh()
    }

    private func saveSettings(_ settings: MacStreamHostSettings, successMessage: String) async {
        do {
            let normalized = settings.normalized()
            try settingsManager.save(normalized)
            runtimeSettings = normalized
            applyRuntimeDependencies(for: normalized)
            lastOperationMessage = successMessage
        } catch {
            lastOperationMessage = error.localizedDescription
        }

        await refresh()
    }

    private func applyRuntimeDependencies(for settings: MacStreamHostSettings) {
        let dependencies = Self.makeRuntimeDependencies(settings: settings)
        sunshineManager = dependencies.sunshine
        blackHoleManager = dependencies.blackHole
        permissionManager = dependencies.permissions
        audioDeviceManager = dependencies.audio
        networkDiagnosticsManager = dependencies.network
        launchAgentManager = dependencies.launchAgent
        configurationManager = dependencies.configuration
        logManager = dependencies.log
        healthCheckService = dependencies.health
    }

    private func makeSetupChecklist(
        sunshine: SunshineStatus,
        blackHole: BlackHoleInstallationStatus,
        permissions: MacOSPermissionsStatus,
        network: NetworkDiagnosticResult
    ) -> [SetupChecklistItem] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let isSupportedOS = version.majorVersion > 14 || (version.majorVersion == 14 && version.minorVersion >= 2)

        return [
            SetupChecklistItem(
                id: .macOSVersion,
                title: "Verificar versão do macOS",
                status: isSupportedOS ? .pass : .fail,
                detail: "Alvo inicial: macOS 14.2+."
            ),
            SetupChecklistItem(
                id: .permissions,
                title: "Verificar permissões",
                status: permissions.aggregateStatus,
                detail: "Gravação de tela, microfone e rede local precisam de validação guiada."
            ),
            SetupChecklistItem(
                id: .sunshineInstalled,
                title: "Verificar instalação do Sunshine",
                status: sunshine.state == .notInstalled ? .fail : .warning,
                detail: "MVP inicial só detecta/orienta; não instala automaticamente."
            ),
            SetupChecklistItem(
                id: .blackHoleInstalled,
                title: "Verificar instalação do BlackHole",
                status: blackHole.checkStatus,
                detail: "BlackHole 2ch é fallback oficial; captura nativa precisa de validação."
            ),
            SetupChecklistItem(
                id: .audioConfiguration,
                title: "Verificar configuração de áudio",
                status: blackHole == .installed ? .pass : .warning,
                detail: "Selecionar captura nativa ou BlackHole após testes reais."
            ),
            SetupChecklistItem(
                id: .networkPorts,
                title: "Verificar portas/rede",
                status: network.aggregateStatus,
                detail: "Diagnóstico inicial cobre IP local e portas comuns do Sunshine."
            ),
            SetupChecklistItem(
                id: .moonlightPairing,
                title: "Parear com Moonlight",
                status: sunshine.state == .running ? .warning : .unknown,
                detail: "Pareamento nativo depende de API estável ainda não validada."
            )
        ]
    }
}

private struct RuntimeDependencies {
    var sunshine: SunshineManaging
    var blackHole: BlackHoleManaging
    var permissions: PermissionManaging
    var audio: AudioDeviceManaging
    var network: NetworkDiagnosticsManaging
    var launchAgent: LaunchAgentManaging
    var configuration: ConfigurationManaging
    var log: LogManaging
    var health: HealthCheckServicing
}
