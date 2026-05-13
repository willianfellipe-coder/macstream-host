// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var dashboard: DashboardSnapshot
    @Published public private(set) var setupChecklist: [SetupChecklistItem]
    @Published public private(set) var healthCheckResult: HealthCheckResult
    @Published public private(set) var isSunshineOperationInProgress: Bool
    @Published public private(set) var lastSunshineOperationMessage: String?
    @Published public private(set) var runtimeSettings: MacStreamHostSettings
    @Published public private(set) var lastOperationMessage: String?
    @Published public private(set) var dependencyStatuses: [DependencyStatus]
    @Published public private(set) var onboardingSteps: [OnboardingStep]
    @Published public private(set) var operationalState: HostOperationalState
    @Published public private(set) var lastPreflightResult: PreflightResult?
    @Published public private(set) var completedMoonlightChecklistItems: Set<MoonlightChecklistItemID>
    @Published public private(set) var dependencyInstallProgress: DependencyInstallProgress?
    @Published public private(set) var lastDependencyInstallResult: DependencyInstallResult?

    public private(set) var sunshineManager: SunshineManaging
    public private(set) var blackHoleManager: BlackHoleManaging
    public private(set) var dependencyInstallerManager: DependencyInstalling
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
        dependencyInstallerManager: DependencyInstalling,
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
        self.dependencyInstallerManager = dependencyInstallerManager
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
        self.dependencyStatuses = []
        self.onboardingSteps = []
        self.operationalState = .unknown
        self.lastPreflightResult = nil
        self.completedMoonlightChecklistItems = []
        self.dependencyInstallProgress = nil
        self.lastDependencyInstallResult = nil
    }

    public static func localDiagnostics(settingsManager: SettingsManaging = FileSettingsManager()) -> AppState {
        let settings = ((try? settingsManager.load()) ?? .defaults()).normalized()
        let dependencies = makeRuntimeDependencies(settings: settings)

        return AppState(
            sunshineManager: dependencies.sunshine,
            blackHoleManager: dependencies.blackHole,
            dependencyInstallerManager: dependencies.dependencyInstaller,
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
        let dependencyInstaller = DefaultDependencyInstallerManager(settings: settings)
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
            dependencyInstaller: dependencyInstaller,
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
        let dependencies = await makeDependencyStatuses(
            sunshine: sunshine,
            blackHole: blackHole
        )

        dashboard = DashboardSnapshot(
            sunshineStatus: sunshine,
            blackHoleStatus: blackHole,
            permissionsStatus: permissions,
            networkStatus: network,
            recommendedNextStep: health.recommendedNextStep
        )
        dependencyStatuses = dependencies
        setupChecklist = makeSetupChecklist(
            sunshine: sunshine,
            blackHole: blackHole,
            permissions: permissions,
            network: network
        )
        healthCheckResult = health
        operationalState = determineOperationalState(
            sunshine: sunshine,
            blackHole: blackHole,
            permissions: permissions,
            health: health
        )
        onboardingSteps = makeOnboardingSteps(
            dashboard: dashboard,
            health: health,
            dependencies: dependencies
        )
    }

    public func refreshDependencies() async {
        let sunshine = await sunshineManager.status()
        let blackHole = await blackHoleManager.installationStatus()
        dependencyStatuses = await makeDependencyStatuses(sunshine: sunshine, blackHole: blackHole)
    }

    public func runPreflight(startAfterValidation: Bool, overwriteConfig: Bool) async {
        var writes: [ConfigurationFileWriteResult] = []
        var startedSunshine = false

        do {
            try logManager.rotateLogs(maxBytes: 5 * 1024 * 1024, backupCount: 3)
            writes = try configurationManager.writeDefaultFiles(
                overwrite: overwriteConfig,
                audioSink: runtimeSettings.audioSink
            )

            if startAfterValidation {
                try await sunshineManager.start()
                startedSunshine = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            await refresh()
            let blockers = healthCheckResult.checks
                .filter { $0.status == .fail }
                .map(\.detail)
            lastPreflightResult = PreflightResult(
                configurationWrites: writes,
                dashboard: dashboard,
                health: healthCheckResult,
                operationalState: operationalState,
                blockers: blockers,
                nextStep: healthCheckResult.recommendedNextStep,
                startedSunshine: startedSunshine
            )
            lastOperationMessage = blockers.isEmpty ? "Preflight concluído." : "Preflight concluído com bloqueios."
        } catch {
            await refresh()
            lastPreflightResult = PreflightResult(
                configurationWrites: writes,
                dashboard: dashboard,
                health: healthCheckResult,
                operationalState: .blocked,
                blockers: [error.localizedDescription],
                nextStep: "Corrija o erro reportado e execute o preflight novamente.",
                startedSunshine: startedSunshine
            )
            lastOperationMessage = error.localizedDescription
        }
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
            launchAgentStatus: await launchAgentManager.status(),
            dependencies: dependencyStatuses,
            buildInfo: .current
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
            let result = try await service.writeBundle(
                options: SupportBundleOptions(parentDirectoryPath: parentDirectory.path),
                diagnostics: report,
                buildInfo: .current
            )
            lastOperationMessage = "Pacote de suporte criado em \(result.directoryPath)."
            return result
        } catch {
            lastOperationMessage = error.localizedDescription
            await refresh()
            return nil
        }
    }

    public func exportSupportBundleZip() async -> SupportBundleResult? {
        let outputURL = logManager.logDirectoryURL.appendingPathComponent("SupportBundles", isDirectory: true)
        do {
            let report = await diagnosticsReport()
            let service = DefaultSupportBundleService(
                logManager: logManager,
                configurationManager: configurationManager
            )
            let result = try await service.writeBundle(
                options: SupportBundleOptions(parentDirectoryPath: outputURL.path, includeZip: true),
                diagnostics: report,
                buildInfo: .current
            )
            lastOperationMessage = "Pacote de suporte criado em \(result.archivePath ?? result.directoryPath)."
            return result
        } catch {
            lastOperationMessage = error.localizedDescription
            await refresh()
            return nil
        }
    }

    public func copyPairingAddress(_ address: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #endif
        lastOperationMessage = "Endereço copiado: \(address)"
    }

    public func markMoonlightChecklistItemComplete(_ item: MoonlightChecklistItemID) {
        completedMoonlightChecklistItems.insert(item)
        onboardingSteps = makeOnboardingSteps(
            dashboard: dashboard,
            health: healthCheckResult,
            dependencies: dependencyStatuses
        )
    }

    public func installManagedSunshine() async {
        dependencyInstallProgress = DependencyInstallProgress(
            id: .sunshine,
            stage: .downloading,
            detail: "Baixando Sunshine do release upstream fixado."
        )

        do {
            let result = try await dependencyInstallerManager.installManagedSunshine()
            lastDependencyInstallResult = result
            dependencyInstallProgress = DependencyInstallProgress(
                id: .sunshine,
                stage: .completed,
                detail: result.message
            )

            if let binaryPath = result.installedBinaryPath {
                var settings = runtimeSettings
                settings.sunshineBinaryPath = binaryPath
                try settingsManager.save(settings.normalized())
                runtimeSettings = settings.normalized()
                applyRuntimeDependencies(for: runtimeSettings)
            }

            lastOperationMessage = result.message
        } catch {
            dependencyInstallProgress = DependencyInstallProgress(
                id: .sunshine,
                stage: .failed,
                detail: error.localizedDescription
            )
            lastOperationMessage = error.localizedDescription
        }

        await refresh()
    }

    public func installBlackHole() async {
        dependencyInstallProgress = DependencyInstallProgress(
            id: .blackHole,
            stage: .downloading,
            detail: "Baixando instalador oficial do BlackHole 2ch."
        )

        do {
            let result = try await dependencyInstallerManager.downloadAndOpenBlackHoleInstaller()
            lastDependencyInstallResult = result
            dependencyInstallProgress = DependencyInstallProgress(
                id: .blackHole,
                stage: result.requiresUserCompletion ? .waitingForUser : .completed,
                detail: result.message
            )
            lastOperationMessage = result.message
        } catch {
            dependencyInstallProgress = DependencyInstallProgress(
                id: .blackHole,
                stage: .failed,
                detail: error.localizedDescription
            )
            lastOperationMessage = error.localizedDescription
        }

        await refresh()
    }

    public func installMissingDependencies() async {
        let sunshine = await sunshineManager.status()
        let blackHole = await blackHoleManager.installationStatus()

        if sunshine.state == .notInstalled {
            await installManagedSunshine()
        }

        if blackHole != .installed {
            await installBlackHole()
        }

        await refresh()
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

    private func makeDependencyStatuses(
        sunshine: SunshineStatus,
        blackHole: BlackHoleInstallationStatus
    ) async -> [DependencyStatus] {
        [
            DependencyStatus(
                id: .sunshine,
                status: sunshine.state == .notInstalled ? .fail : .pass,
                detail: sunshine.state == .notInstalled
                    ? "Instale o Sunshine ou selecione o binário manualmente."
                    : "Sunshine detectado\(sunshine.binaryPath.map { " em \($0)" } ?? ".").",
                detectedPath: sunshine.binaryPath,
                detectedVersion: sunshine.version,
                officialURL: URL(string: "https://github.com/LizardByte/Sunshine/releases")
            ),
            DependencyStatus(
                id: .blackHole,
                status: blackHole.checkStatus,
                detail: blackHole == .installed
                    ? "BlackHole 2ch detectado para captura de áudio."
                    : await blackHoleManager.installationGuidance(),
                officialURL: URL(string: "https://github.com/ExistentialAudio/BlackHole")
            ),
            DependencyStatus(
                id: .moonlight,
                status: .warning,
                detail: "Use um cliente Moonlight no dispositivo que receberá o stream.",
                officialURL: URL(string: "https://moonlight-stream.org")
            )
        ]
    }

    private func determineOperationalState(
        sunshine: SunshineStatus,
        blackHole: BlackHoleInstallationStatus,
        permissions: MacOSPermissionsStatus,
        health: HealthCheckResult
    ) -> HostOperationalState {
        if sunshine.state == .running && sunshine.ownedProcessID == nil {
            return .externalConflict
        }

        if sunshine.state == .notInstalled {
            return .needsDependency
        }

        if runtimeSettings.audioCaptureMode == .blackHole2ch && blackHole != .installed {
            return .needsDependency
        }

        if permissions.aggregateStatus == .fail || permissions.criticalPermissionsSatisfied == false {
            return .needsPermission
        }

        if health.status == .failing {
            return .blocked
        }

        if sunshine.state == .running {
            return .running
        }

        return .ready
    }

    private func makeOnboardingSteps(
        dashboard: DashboardSnapshot,
        health: HealthCheckResult,
        dependencies: [DependencyStatus]
    ) -> [OnboardingStep] {
        let hasConfig = FileManager.default.fileExists(atPath: runtimeSettings.sunshineConfigURL.path)
            && FileManager.default.fileExists(atPath: runtimeSettings.appsJSONURL.path)
        let audioStatus = health.checks.first(where: { $0.id == .audio })?.status ?? .unknown
        let systemStatus = combinedStatus(for: [.macOSVersion, .architecture], in: health)
        let allMoonlightItemsDone = Set(MoonlightChecklistItemID.allCases).isSubset(of: completedMoonlightChecklistItems)

        return [
            OnboardingStep(id: .system, title: "Verificar sistema", state: stepState(for: systemStatus), detail: "macOS 14.2+ e Apple Silicon primeiro."),
            OnboardingStep(id: .sunshine, title: "Detectar Sunshine", state: stepState(for: dependencyStatus(.sunshine, dependencies)), detail: dependencies.first(where: { $0.id == .sunshine })?.detail ?? "Validar Sunshine."),
            OnboardingStep(id: .blackHole, title: "Detectar BlackHole", state: stepState(for: dependencyStatus(.blackHole, dependencies)), detail: dependencies.first(where: { $0.id == .blackHole })?.detail ?? "Validar BlackHole."),
            OnboardingStep(id: .audio, title: "Configurar áudio", state: stepState(for: audioStatus), detail: audioStatus == .pass ? "Rota de áudio validada." : "Escolha captura nativa ou BlackHole 2ch."),
            OnboardingStep(id: .permissions, title: "Validar permissões", state: stepState(for: dashboard.permissionsStatus.aggregateStatus), detail: dashboard.permissionsStatus.criticalPermissionsSatisfied ? "Permissões críticas OK." : "Abra Ajustes do Sistema para permissões pendentes."),
            OnboardingStep(id: .configuration, title: "Gerar configuração", state: hasConfig ? .passed : .pending, detail: runtimeSettings.sunshineConfigURL.path),
            OnboardingStep(id: .startSunshine, title: "Iniciar Sunshine", state: dashboard.sunshineStatus.state == .running ? .passed : .pending, detail: dashboard.sunshineStatus.state.displayName),
            OnboardingStep(id: .webUI, title: "Abrir Web UI", state: dashboard.sunshineStatus.webUIReachable ? .passed : .pending, detail: "https://localhost:47990"),
            OnboardingStep(id: .moonlightPairing, title: "Parear Moonlight", state: allMoonlightItemsDone ? .passed : .active, detail: "Use um IP listado e conclua o checklist no app."),
            OnboardingStep(id: .diagnostics, title: "Exportar diagnóstico", state: health.status == .failing ? .active : .pending, detail: "Gere um pacote de suporte se o teste falhar.")
        ]
    }

    private func combinedStatus(for ids: [HealthCheckID], in health: HealthCheckResult) -> CheckStatus {
        let statuses = health.checks.filter { ids.contains($0.id) }.map(\.status)
        if statuses.contains(.fail) { return .fail }
        if statuses.contains(where: { $0 == .warning || $0 == .unknown }) { return .warning }
        return statuses.isEmpty ? .unknown : .pass
    }

    private func dependencyStatus(_ id: DependencyID, _ dependencies: [DependencyStatus]) -> CheckStatus {
        dependencies.first(where: { $0.id == id })?.status ?? .unknown
    }

    private func stepState(for status: CheckStatus) -> OnboardingStepState {
        switch status {
        case .pass: return .passed
        case .warning: return .warning
        case .fail: return .failed
        case .unknown: return .pending
        }
    }

    private func applyRuntimeDependencies(for settings: MacStreamHostSettings) {
        let dependencies = Self.makeRuntimeDependencies(settings: settings)
        sunshineManager = dependencies.sunshine
        blackHoleManager = dependencies.blackHole
        dependencyInstallerManager = dependencies.dependencyInstaller
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
    var dependencyInstaller: DependencyInstalling
    var permissions: PermissionManaging
    var audio: AudioDeviceManaging
    var network: NetworkDiagnosticsManaging
    var launchAgent: LaunchAgentManaging
    var configuration: ConfigurationManaging
    var log: LogManaging
    var health: HealthCheckServicing
}
