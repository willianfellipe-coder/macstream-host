// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#endif

/// Discriminates the kind of privacy overlay currently active. The
/// dashboard and tray surfaces read this to pick the right unlock UI;
/// the app-level `PrivacyOverlayController` reads it to pick the
/// rendering strategy (small floating panel vs full-screen secure
/// overlay).
public enum PrivacyOverlayMode: Equatable {
    case none
    /// Classic dim-only mode — `lockHostForPrivacy()` with
    /// `HostPrivacyMode.appOverlay`. Brightness/gamma only, no
    /// mandatory password.
    case classic
    /// Secure overlay — `HostPrivacyMode.secureOverlay`.
    /// Full-screen local shield on every display with the mandatory
    /// password panel only on a safe non-streamed display.
    case secure
}

/// Errors thrown by the secure-lock pre-flight. Surfaced to the UI so
/// the dashboard / tray can present a recovery sheet instead of failing
/// silently or entering a broken state.
public enum SecureLockError: Error, LocalizedError, Equatable {
    /// Secure lock now requires a MacStream app password as a local
    /// fallback even when LocalAuthentication is available.
    case needsAppPassword
    /// Legacy fallback for impossible auth combinations. Current secure
    /// lock readiness normally returns `.needsAppPassword` first because
    /// the MacStream password is mandatory.
    case noAuthAvailable
    /// Streaming is active and the host has only one display — the same
    /// one Sunshine is capturing. There is no safe display to host the
    /// password panel without leaking into the Moonlight feed. UI should
    /// ask the user to disconnect Moonlight or plug in a second display
    /// before locking.
    case noSafeDisplayDuringStream
    /// The user is in the temporal lockout window after too many failed
    /// attempts. UI should display the wait time.
    case lockedOut(secondsRemaining: Int)

    public var errorDescription: String? {
        switch self {
        case .needsAppPassword:
            return SecureLockReadiness.needsAppPassword.userMessage
        case .noAuthAvailable:
            return "Bloqueio seguro exige uma forma de desbloqueio. Configure uma senha do MacStream em Ajustes ou ative Touch ID / senha do macOS."
        case .noSafeDisplayDuringStream:
            return SecureLockReadiness.noSafeDisplayDuringCapture.userMessage
        case .lockedOut(let secondsRemaining):
            return SecureLockReadiness.lockedOut(secondsRemaining: secondsRemaining).userMessage
        }
    }
}

/// Tiny provider so AppState can run the secure-lock pre-flight (count
/// physical displays + know which is being streamed) without depending
/// on AppKit. The default implementation uses CoreGraphics; tests inject
/// a stub.
public protocol DisplayInventoryProviding: Sendable {
    /// Active physical display IDs (built-in + connected externals,
    /// minus Sidecar / AirPlay). Empty if CoreGraphics fails.
    func activeDisplayIDs() -> [CGDirectDisplayID]
    /// Display Sunshine captures into the Moonlight stream — currently
    /// `CGMainDisplayID()` by Sunshine convention.
    func streamedDisplayID() -> CGDirectDisplayID
}

public struct DefaultDisplayInventoryProvider: DisplayInventoryProviding {
    public init() {}

    public func activeDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        var actualCount: UInt32 = 0
        guard CGGetActiveDisplayList(displayCount, &ids, &actualCount) == .success else {
            return []
        }
        return Array(ids.prefix(Int(actualCount)))
    }

    public func streamedDisplayID() -> CGDirectDisplayID {
        CGMainDisplayID()
    }
}

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
    @Published public private(set) var remoteWorkSession: RemoteWorkSessionReport
    @Published public private(set) var agentStatus: MacStreamAgentStatus
    @Published public private(set) var managedEngineStatus: ManagedEngineStatus
    @Published public private(set) var powerAssertionStatus: PowerAssertionStatus
    @Published public private(set) var hostPrivacyStatus: HostPrivacyStatus
    @Published public private(set) var lastPermissionRequestResults: [PermissionRequestResult]
    @Published public private(set) var lastAgentRecoveryAttempt: Date?
    /// Discriminates which overlay (classic vs secure) is currently
    /// covering the host. `.none` means the host is unlocked. UI surfaces
    /// pick the right unlock control by reading this enum.
    @Published public private(set) var privacyOverlayMode: PrivacyOverlayMode = .none
    /// Backwards-compatible read for callers that only need "is the host
    /// locked at all" — both .classic and .secure return true. Maps
    /// directly onto the @Published mode so SwiftUI re-renders correctly.
    public var privacyOverlayActive: Bool { privacyOverlayMode != .none }
    /// While set, the secure overlay is in temporal lockout after too
    /// many failed unlock attempts. UI displays a countdown.
    @Published public private(set) var secureLockoutUntil: Date?
    @Published public private(set) var isAppPasswordSet: Bool = false

    /// Transient counter (in-memory) — number of consecutive failed
    /// unlock attempts in the current lock session. Reset to 0 on
    /// successful auth or on a fresh lock.
    private var secureUnlockAttempts: Int = 0

    public let appPasswordStore: AppPasswordStoring
    public let commandRunner: CommandRunning
    public let localAuthenticationService: LocalAuthenticationServicing
    public let displayInventory: DisplayInventoryProviding

    private let agentRecoveryCooldown: TimeInterval = 60
    private let dateProvider: () -> Date

    /// Background watcher that auto-dismisses the privacy overlay when the
    /// Moonlight client disconnects. Created lazily when the host is locked
    /// during an active session; cancelled on dismiss or app teardown.
    private var streamEndWatcher: Task<Void, Never>?

    /// CoreAudio property listener + the task that drains its events into
    /// `refresh()`. Started by `startLiveMonitors()` and torn down by
    /// `stopLiveMonitors()`. Lets the dashboard react the moment BlackHole
    /// finishes installing without the user reopening the app.
    private let audioDeviceMonitor = AudioDeviceMonitor()
    private var audioDeviceMonitorTask: Task<Void, Never>?

    /// Foreground refresh loop. Polls `refresh()` while the app window is
    /// visible so the user sees state changes (engine respawn, BlackHole
    /// detection, audio routing) without manually pressing Atualizar.
    private var foregroundRefreshTask: Task<Void, Never>?

    /// Identity store used by the "Resetar pareamentos" action.
    private let sunshineIdentityStore: SunshineIdentityStoring = DefaultSunshineIdentityStore()

    /// macOS Login Item registration used by the "Iniciar com o sistema"
    /// toggle. Wraps `SMAppService.mainApp`.
    private let loginItemService: LoginItemManaging = DefaultLoginItemService()

    /// Last result the foreground monitor saw from `AXIsProcessTrusted()`.
    /// Used by `evaluateAccessibilityRecovery` to detect a `false → true`
    /// transition (user just granted Accessibility) and automatically
    /// restart the engine so Sunshine re-evaluates its cached trust.
    private var lastObservedAccessibilityTrusted: Bool = false

    /// Tracks whether the engine restart has already been proposed for the
    /// current grant cycle so we don't spam restarts.
    private var accessibilityRecoveryRestartInFlight: Bool = false

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
    public private(set) var agentManager: AgentManaging
    public private(set) var managedEngineManager: ManagedEngineManaging
    public private(set) var powerAssertionManager: PowerAssertionManaging
    public private(set) var hostPrivacyManager: HostPrivacyManaging
    public private(set) var remoteWorkSessionManager: RemoteWorkSessionManaging

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
        healthCheckService: HealthCheckServicing,
        agentManager: AgentManaging? = nil,
        managedEngineManager: ManagedEngineManaging? = nil,
        powerAssertionManager: PowerAssertionManaging? = nil,
        hostPrivacyManager: HostPrivacyManaging? = nil,
        remoteWorkSessionManager: RemoteWorkSessionManaging? = nil,
        appPasswordStore: AppPasswordStoring? = nil,
        commandRunner: CommandRunning = ProcessCommandRunner(),
        localAuthenticationService: LocalAuthenticationServicing? = nil,
        displayInventory: DisplayInventoryProviding = DefaultDisplayInventoryProvider(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.dateProvider = dateProvider
        self.appPasswordStore = appPasswordStore ?? KeychainAppPasswordStore()
        self.commandRunner = commandRunner
        self.localAuthenticationService = localAuthenticationService ?? DefaultLocalAuthenticationService()
        self.displayInventory = displayInventory
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
        let fallbackAgentManager = agentManager ?? DefaultAgentManager(
            launchAgentManager: launchAgentManager,
            statusURL: runtimeSettings.agentStatusURL,
            commandURL: runtimeSettings.agentCommandURL
        )
        let fallbackManagedEngineManager = managedEngineManager ?? DefaultManagedEngineManager(
            sunshineManager: sunshineManager,
            audioDeviceManager: audioDeviceManager,
            networkDiagnosticsManager: networkDiagnosticsManager
        )
        let fallbackPowerAssertionManager = powerAssertionManager ?? DefaultPowerAssertionManager(
            initialPolicy: runtimeSettings.powerPolicy
        )
        let fallbackHostPrivacyManager = hostPrivacyManager ?? DefaultHostPrivacyManager(
            policy: runtimeSettings.hostPrivacyPolicy
        )
        self.agentManager = fallbackAgentManager
        self.managedEngineManager = fallbackManagedEngineManager
        self.powerAssertionManager = fallbackPowerAssertionManager
        self.hostPrivacyManager = fallbackHostPrivacyManager
        self.remoteWorkSessionManager = remoteWorkSessionManager ?? DefaultRemoteWorkSessionManager(
            agentManager: fallbackAgentManager,
            configurationManager: configurationManager,
            sunshineManager: sunshineManager,
            blackHoleManager: blackHoleManager,
            permissionManager: permissionManager,
            managedEngineManager: fallbackManagedEngineManager,
            powerAssertionManager: fallbackPowerAssertionManager,
            hostPrivacyManager: fallbackHostPrivacyManager,
            settingsProvider: { runtimeSettings }
        )
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
        self.remoteWorkSession = .initial
        self.agentStatus = .initial
        self.managedEngineStatus = .initial
        self.powerAssertionStatus = .inactive
        self.hostPrivacyStatus = .initial
        self.lastPermissionRequestResults = []
        self.lastAgentRecoveryAttempt = nil
        self.isAppPasswordSet = (appPasswordStore ?? self.appPasswordStore).isPasswordSet()
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
            healthCheckService: dependencies.health,
            agentManager: dependencies.agent,
            managedEngineManager: dependencies.engine,
            powerAssertionManager: dependencies.power,
            hostPrivacyManager: dependencies.privacy,
            remoteWorkSessionManager: dependencies.remoteWork
        )
    }

    private static func makeRuntimeDependencies(settings: MacStreamHostSettings) -> RuntimeDependencies {
        let audioDeviceProvider = CoreAudioDeviceProvider()
        let configuration = DefaultConfigurationManager(configDirectory: settings.configDirectoryURL)
        let binaryResolver = SettingsSunshineBinaryResolver(explicitPath: settings.sunshineBinaryPath)
        let agentExecutablePath = settings.agentExecutablePath
            ?? DefaultAgentExecutableResolver().resolveExecutable()?.path
            ?? "/Applications/MacStream Host.app/Contents/MacOS/macstream-agent"
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
                executablePath: agentExecutablePath,
                arguments: ["run"],
                logDirectoryPath: settings.logDirectoryURL.path
            )
        )
        let agent = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: settings.agentStatusURL,
            commandURL: settings.agentCommandURL
        )
        let engine = DefaultManagedEngineManager(
            sunshineManager: sunshine,
            audioDeviceManager: audio,
            networkDiagnosticsManager: network
        )
        let power = DefaultPowerAssertionManager(initialPolicy: settings.powerPolicy)
        let privacy = DefaultHostPrivacyManager(policy: settings.hostPrivacyPolicy)
        let remoteWork = DefaultRemoteWorkSessionManager(
            agentManager: agent,
            configurationManager: configuration,
            sunshineManager: sunshine,
            blackHoleManager: blackHole,
            permissionManager: permissions,
            managedEngineManager: engine,
            powerAssertionManager: power,
            hostPrivacyManager: privacy,
            settingsProvider: { settings }
        )
        let health = DefaultHealthCheckService(
                sunshineManager: sunshine,
                blackHoleManager: blackHole,
                permissionManager: permissions,
                audioDeviceManager: audio,
                networkDiagnosticsManager: network,
                launchAgentManager: launchAgent,
                logManager: log,
                agentManager: agent,
                powerAssertionManager: power,
                hostPrivacyManager: privacy,
                remoteWorkSessionManager: remoteWork
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
            health: health,
            agent: agent,
            engine: engine,
            power: power,
            privacy: privacy,
            remoteWork: remoteWork
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
        var agent = await agentManager.status()
        if shouldAttemptAgentRecovery(for: agent) {
            lastAgentRecoveryAttempt = dateProvider()
            if (try? await agentManager.recoverIfStale()) == true {
                agent = await agentManager.status()
            }
        }
        let engine = await managedEngineManager.status()
        let localPower = await powerAssertionManager.currentStatus()
        let localPrivacy = await hostPrivacyManager.currentStatus()
        let remoteWork = await remoteWorkSessionManager.status()
        let effectivePower = remoteWork.powerStatus.isActive ? remoteWork.powerStatus : localPower
        let effectivePrivacy = remoteWork.agentStatus.isRunning ? remoteWork.hostPrivacyStatus : localPrivacy

        dashboard = DashboardSnapshot(
            sunshineStatus: sunshine,
            blackHoleStatus: blackHole,
            permissionsStatus: permissions,
            networkStatus: network,
            recommendedNextStep: health.recommendedNextStep
        )
        dependencyStatuses = dependencies
        agentStatus = agent
        managedEngineStatus = engine
        powerAssertionStatus = effectivePower
        hostPrivacyStatus = effectivePrivacy
        remoteWorkSession = remoteWork
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

    /// Starts the CoreAudio device listener and the foreground refresh loop.
    /// Idempotent — safe to call from `.task` modifiers without guarding the
    /// caller. The audio listener triggers a refresh whenever a device is
    /// added/removed, which is the natural signal for "BlackHole just
    /// finished installing" and similar.
    public func startLiveMonitors(refreshInterval: TimeInterval = 5) {
        if audioDeviceMonitorTask == nil {
            audioDeviceMonitor.start()
            audioDeviceMonitorTask = Task { [weak self] in
                guard let stream = self?.audioDeviceMonitor.events else { return }
                for await _ in stream {
                    await self?.refresh()
                }
            }
        }

        if foregroundRefreshTask == nil {
            let nanoseconds = UInt64(max(1, refreshInterval) * 1_000_000_000)
            foregroundRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    if Task.isCancelled { break }
                    await self?.refresh()
                    await self?.evaluateAccessibilityRecovery()
                }
            }
        }

        // Seed the AX trust observation so the first transition is detected
        // accurately (otherwise a true → true on first tick would look like
        // a transition from false).
        lastObservedAccessibilityTrusted =
            (AccessibilityProbe.currentStatus() == .granted)
    }

    public func stopLiveMonitors() {
        audioDeviceMonitorTask?.cancel()
        audioDeviceMonitorTask = nil
        audioDeviceMonitor.stop()
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
    }

    /// Watches for a `false → true` transition in `AXIsProcessTrusted()` —
    /// the user just toggled Accessibility on for MacStream Host in System
    /// Settings. Sunshine caches the trust check at engine startup, so the
    /// running engine will keep silently dropping CGEventPost until it
    /// respawns. Auto-restart bridges that gap.
    private func evaluateAccessibilityRecovery() async {
        let nowTrusted = (AccessibilityProbe.currentStatus() == .granted)
        defer { lastObservedAccessibilityTrusted = nowTrusted }

        // We only act on the rising edge AND only when an engine is alive
        // — otherwise there's nothing to recycle and `restartSunshine()`
        // would no-op or fail.
        let justGranted = (lastObservedAccessibilityTrusted == false && nowTrusted)
        let engineOwned = (dashboard.sunshineStatus.ownedProcessID != nil)
        guard justGranted, engineOwned, !accessibilityRecoveryRestartInFlight else {
            return
        }

        accessibilityRecoveryRestartInFlight = true
        defer { accessibilityRecoveryRestartInFlight = false }

        lastOperationMessage = "Acessibilidade concedida — reiniciando o motor para aplicar."
        await restartSunshine()
    }

    /// Drops any stored Moonlight client certificates from Sunshine's state
    /// so the iPad starts a clean pairing handshake. Used when the iPad
    /// shows a duplicate offline "MacStream Host" entry because a previous
    /// install regenerated certificates.
    public func resetMoonlightPairings() async {
        do {
            try sunshineIdentityStore.resetClientPairings()
            lastOperationMessage = "Pareamentos Moonlight resetados. Reinicie o motor e pareie novamente pelo iPad."
        } catch {
            lastOperationMessage = "Não foi possível resetar pareamentos: \(error.localizedDescription)"
        }
        await refresh()
    }

    public func runPreflight(startAfterValidation: Bool, overwriteConfig: Bool) async {
        var writes: [ConfigurationFileWriteResult] = []
        var startedSunshine = false

        do {
            try logManager.rotateLogs(maxBytes: 5 * 1024 * 1024, backupCount: 3)
            writes = try configurationManager.writeDefaultFiles(
                overwrite: overwriteConfig,
                audioSink: runtimeSettings.audioSink,
                lowLatency: runtimeSettings.lowLatencyMode
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

    public func prepareRemoteWorkMode() async {
        await runRemoteWorkOperation {
            try await remoteWorkSessionManager.prepare(overwriteConfig: false)
        }
    }

    public func startRemoteWorkMode() async {
        await runRemoteWorkOperation {
            try await remoteWorkSessionManager.start(overwriteConfig: false)
        }
    }

    public func stopRemoteWorkMode() async {
        await runRemoteWorkOperation {
            try await remoteWorkSessionManager.stop()
        }
    }

    public func refreshAgentStatus() async {
        agentStatus = await agentManager.status()
        remoteWorkSession = await remoteWorkSessionManager.status()
    }

    public func enablePowerPolicy(_ policy: PowerPolicy) async {
        var settings = runtimeSettings
        settings.powerPolicy = policy
        await saveSettings(settings, successMessage: "Politica de energia salva.")
    }

    public func updateHostPrivacyPolicy(_ policy: HostPrivacyPolicy) async {
        var settings = runtimeSettings
        settings.hostPrivacyPolicy = policy
        await saveSettings(settings, successMessage: "Politica de privacidade salva.")
    }

    /// Tries to route the system's default audio output to BlackHole 2ch
    /// so the engine can actually capture system audio. Surfaces a user-
    /// readable message and lets the caller know whether the previous
    /// device should be remembered for a "restore" action.
    @discardableResult
    public func routeSystemAudioToMacStream() async -> AudioRoutingResult {
        let result = await audioDeviceManager.routeSystemOutputToBlackHole()
        switch result {
        case .routed(let previous, let new):
            let restore = previous.map { " (anterior: \($0.name))" } ?? ""
            lastOperationMessage = "Saída do sistema agora é \(new.name)\(restore)."
        case .alreadyRouted(let current):
            lastOperationMessage = "Saída do sistema já está em \(current.name)."
        case .targetDeviceUnavailable:
            lastOperationMessage = "Roteamento de áudio do MacStream não está disponível. Conclua a instalação do mecanismo de áudio em Components."
        case .routingFailed(let message):
            lastOperationMessage = "Não foi possível trocar a saída do sistema: \(message)"
        }
        return result
    }

    /// Restores the system output device to the given identifier — used by
    /// the UI to put the previous device back after the user finishes a
    /// streaming session.
    @discardableResult
    public func restoreSystemAudioOutput(to deviceID: String) async -> AudioRoutingResult {
        let result = await audioDeviceManager.routeSystemOutput(to: deviceID)
        switch result {
        case .routed(_, let new):
            lastOperationMessage = "Saída do sistema restaurada para \(new.name)."
        case .alreadyRouted(let current):
            lastOperationMessage = "Saída do sistema já está em \(current.name)."
        case .targetDeviceUnavailable:
            lastOperationMessage = "Dispositivo de áudio anterior não está mais disponível."
        case .routingFailed(let message):
            lastOperationMessage = "Não foi possível restaurar a saída do sistema: \(message)"
        }
        return result
    }

    public func lockHostForPrivacy() async {
        switch runtimeSettings.hostPrivacyPolicy.mode {
        case .appOverlay:
            privacyOverlayMode = .classic
            lastOperationMessage = "Tela do host ocultada. O cliente remoto continua vendo o desktop. Clique 'Desbloquear' no Mac para sair."
            startStreamEndWatcher()
        case .systemSuspend:
            await runRemoteWorkOperation {
                try await remoteWorkSessionManager.lockHostForPrivacy()
            }
        case .secureOverlay:
            do {
                try enterSecureLockPreflight()
            } catch let error as SecureLockError {
                lastOperationMessage = error.errorDescription
                return
            } catch {
                lastOperationMessage = error.localizedDescription
                return
            }
            secureUnlockAttempts = 0
            secureLockoutUntil = nil
            privacyOverlayMode = .secure
            lastOperationMessage = "Host bloqueado com senha. Desbloqueio acontece na tela do Mac — o cliente remoto continua usando o desktop."
            startStreamEndWatcher()
        }
    }

    /// True when the user can actually unlock the secure overlay — at
    /// least the mandatory MacStream fallback password exists. macOS
    /// authentication can be offered as the preferred path, but it never
    /// replaces the app password fallback.
    public var secureUnlockAvailable: Bool {
        isAppPasswordSet
    }

    public var secureLockCaptureRiskActive: Bool {
        remoteWorkSession.state.isStreamingActive
            || dashboard.sunshineStatus.state.isOperational
    }

    public func secureLockReadiness() -> SecureLockReadiness {
        if let until = secureLockoutUntil, until > dateProvider() {
            let seconds = Int(until.timeIntervalSince(dateProvider()).rounded(.up))
            return .lockedOut(secondsRemaining: seconds)
        }

        guard isAppPasswordSet else {
            return .needsAppPassword
        }

        if secureLockCaptureRiskActive {
            let displays = displayInventory.activeDisplayIDs()
            let streamed = displayInventory.streamedDisplayID()
            let safeDisplays = displays.filter { $0 != streamed }
            if safeDisplays.isEmpty {
                return .noSafeDisplayDuringCapture
            }
        }

        return .ready
    }

    public func reportSecureLockReadiness(_ readiness: SecureLockReadiness) {
        lastOperationMessage = readiness.userMessage
    }

    /// Pre-flight runs synchronously before flipping the overlay mode.
    /// Throws `SecureLockError` cases the UI can match on.
    public func enterSecureLockPreflight() throws {
        switch secureLockReadiness() {
        case .ready:
            return
        case .needsAppPassword:
            throw SecureLockError.needsAppPassword
        case .noSafeDisplayDuringCapture:
            throw SecureLockError.noSafeDisplayDuringStream
        case .lockedOut(let secondsRemaining):
            throw SecureLockError.lockedOut(secondsRemaining: secondsRemaining)
        }
    }

    /// Manual unlock with the MacStream app password. Returns true on
    /// success. On failure increments the attempt counter and, when the
    /// cap is reached, sets `secureLockoutUntil` to a temporal backoff
    /// window. The UI reads `secureLockoutUntil` to render the countdown.
    @discardableResult
    public func dismissSecureOverlay(withAppPassword candidate: String) -> Bool {
        guard privacyOverlayMode == .secure else { return false }
        if let until = secureLockoutUntil, until > dateProvider() { return false }
        if appPasswordStore.verify(candidate) {
            return finishSecureUnlock()
        }
        registerFailedSecureAttempt()
        return false
    }

    /// Manual unlock via Touch ID / macOS user password. Triggers the
    /// system auth dialog. Returns true on success.
    @discardableResult
    public func dismissSecureOverlay(withBiometrics _: Void = ()) async -> Bool {
        guard privacyOverlayMode == .secure else { return false }
        if let until = secureLockoutUntil, until > dateProvider() { return false }
        guard runtimeSettings.hostPrivacyPolicy.secureAllowMacOSAuthentication else {
            lastOperationMessage = "Desbloqueio por Touch ID / senha do macOS está desativado nas configurações."
            return false
        }
        do {
            let ok = try await localAuthenticationService.authenticate(
                reason: "Desbloquear o MacStream Host"
            )
            if ok {
                return finishSecureUnlock()
            }
            registerFailedSecureAttempt()
            return false
        } catch {
            lastOperationMessage = error.localizedDescription
            return false
        }
    }

    private func finishSecureUnlock() -> Bool {
        secureUnlockAttempts = 0
        secureLockoutUntil = nil
        streamEndWatcher?.cancel()
        streamEndWatcher = nil
        privacyOverlayMode = .none
        lastOperationMessage = "Host desbloqueado."
        return true
    }

    private func registerFailedSecureAttempt() {
        secureUnlockAttempts += 1
        let max = runtimeSettings.hostPrivacyPolicy.secureMaxUnlockAttempts
        if secureUnlockAttempts >= max {
            // Backoff: 30s × (attempts - max + 1), capped at 5 min.
            let extra = secureUnlockAttempts - max + 1
            let seconds = min(30 * extra, 300)
            secureLockoutUntil = dateProvider().addingTimeInterval(TimeInterval(seconds))
            lastOperationMessage = "Tentativas excedidas. Aguarde \(seconds) segundos antes de tentar novamente."
        } else {
            lastOperationMessage = "Senha incorreta. Tente novamente."
        }
    }

    /// Polls the Sunshine log every 2 seconds for `CLIENT DISCONNECTED` while
    /// the host is locked during an active Moonlight session. When the most
    /// recent disconnect arrives AFTER the lock activation, automatically
    /// dismisses the privacy overlay so the user doesn't return to a Mac
    /// stuck in lock mode after the remote session ends.
    private func startStreamEndWatcher() {
        streamEndWatcher?.cancel()
        let activatedAt = dateProvider()
        streamEndWatcher = Task { @MainActor [weak self] in
            // Give the engine a beat to register the active session before we
            // start checking — otherwise we may dismiss right after locking.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            while !Task.isCancelled {
                guard let self, self.privacyOverlayActive else { return }
                if SunshineSessionTracker.sessionEndedAfter(activatedAt) {
                    // Auto-release works for both classic and secure modes —
                    // there's no remote viewer left to protect against.
                    self.streamEndWatcher?.cancel()
                    self.streamEndWatcher = nil
                    self.secureUnlockAttempts = 0
                    self.secureLockoutUntil = nil
                    self.privacyOverlayMode = .none
                    self.lastOperationMessage = "Sessão Moonlight encerrou. Tela do host restaurada automaticamente."
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Whether the overlay should prompt for the app password before clearing.
    /// True only when both a password is set AND the policy requires it.
    public var overlayUnlockRequiresPassword: Bool {
        isAppPasswordSet && runtimeSettings.appPasswordPolicy.requireOnOverlayUnlock
    }

    /// Hook the UI layer can call after the overlay has tried to dim displays.
    /// Surfaces the result through the same lastOperationMessage channel as
    /// other ops so the user immediately sees whether the lock actually
    /// affected the local screen or stayed in panel-only mode.
    public func reportPrivacyLockDimResult(_ summary: String, didDimAny: Bool) {
        if didDimAny {
            lastOperationMessage = "Tela do host ocultada. \(summary)"
        } else {
            lastOperationMessage = "Não foi possível escurecer este Mac. " +
                "O painel de desbloqueio está visível, mas a tela física não foi escurecida — " +
                "verifique se o display interno está conectado ao sistema."
        }
    }

    @discardableResult
    public func dismissPrivacyOverlay(passwordCandidate: String? = nil) -> Bool {
        return dismissPrivacyOverlay(passwordCandidate: passwordCandidate, autoTriggered: false)
    }

    @discardableResult
    private func dismissPrivacyOverlay(passwordCandidate: String?, autoTriggered: Bool) -> Bool {
        // Secure mode has its own dismiss methods (`dismissSecureOverlay`)
        // with the lockout / biometrics paths. The classic dismiss route
        // never grants secure unlock — that would bypass the password
        // gate that defines secure mode.
        if privacyOverlayMode == .secure, !autoTriggered {
            lastOperationMessage = "Use o painel de bloqueio seguro na tela do Mac para desbloquear."
            return false
        }
        // Auto-triggered dismisses come from the stream-end watcher and skip
        // the password gate — the remote user is gone, so there's nothing to
        // protect against. Manual dismisses still require the password when
        // policy demands it.
        if !autoTriggered, overlayUnlockRequiresPassword {
            guard let candidate = passwordCandidate,
                  appPasswordStore.verify(candidate) else {
                lastOperationMessage = "Senha incorreta. Tente novamente."
                return false
            }
        }
        streamEndWatcher?.cancel()
        streamEndWatcher = nil
        privacyOverlayMode = .none
        if !autoTriggered {
            lastOperationMessage = "Tela do host restaurada."
        }
        return true
    }

    @discardableResult
    public func setAppPassword(_ password: String) -> Bool {
        do {
            try appPasswordStore.setPassword(password)
            isAppPasswordSet = appPasswordStore.isPasswordSet()
            lastOperationMessage = "Senha do app salva."
            return true
        } catch {
            lastOperationMessage = error.localizedDescription
            return false
        }
    }

    public func clearAppPassword() {
        do {
            try appPasswordStore.clearPassword()
            isAppPasswordSet = appPasswordStore.isPasswordSet()
            var settings = runtimeSettings
            if settings.appPasswordPolicy.requireOnOverlayUnlock {
                settings.appPasswordPolicy.requireOnOverlayUnlock = false
                runtimeSettings = settings
                try? settingsManager.save(settings)
            }
            lastOperationMessage = "Senha do app removida."
        } catch {
            lastOperationMessage = error.localizedDescription
        }
    }

    public func updateAppPasswordPolicy(_ policy: AppPasswordPolicy) async {
        var settings = runtimeSettings
        settings.appPasswordPolicy = policy
        await saveSettings(settings, successMessage: "Politica de senha do app atualizada.")
    }

    public func updateShowMenuBarItem(_ visible: Bool) async {
        var settings = runtimeSettings
        settings.showMenuBarItem = visible
        await saveSettings(settings, successMessage: visible ? "Icone na barra de menus ativado." : "Icone na barra de menus ocultado.")
    }

    /// Persists the user's preference and synchronizes it with the macOS
    /// Login Items registry (`SMAppService.mainApp`). When enabled, the
    /// app auto-launches on login and runs as a tray-only accessory (no
    /// Dock icon, no main window). Dashboard is reachable on demand via
    /// the menu bar item.
    public func updateStartInBackground(_ enabled: Bool) async {
        var settings = runtimeSettings
        settings.startInBackground = enabled
        do {
            try loginItemService.setRegistered(enabled)
        } catch {
            lastOperationMessage = error.localizedDescription
            return
        }
        await saveSettings(
            settings,
            successMessage: enabled
                ? "Iniciar com o sistema ativado — o MacStream Host vai subir em segundo plano após login."
                : "Iniciar com o sistema desativado."
        )
    }

    /// Returns the current login-item registration as macOS reports it.
    /// Useful for the Settings toggle to reflect external changes the user
    /// may have made via System Settings > General > Login Items.
    public var isLoginItemRegistered: Bool {
        loginItemService.isRegistered
    }

    /// Toggles the low-latency Sunshine profile (fec_percentage=0,
    /// min_threads=4, min_log_level=warning). Persists the new setting,
    /// regenerates `sunshine.conf` from the template, and respawns the
    /// engine so the new values take effect immediately. Without the
    /// restart the live engine would keep streaming with whatever it
    /// loaded at boot.
    public func updateLowLatencyMode(_ enabled: Bool) async {
        var settings = runtimeSettings
        settings.lowLatencyMode = enabled
        do {
            try settingsManager.save(settings.normalized())
            runtimeSettings = settings.normalized()
        } catch {
            lastOperationMessage = "Não foi possível salvar o perfil de latência: \(error.localizedDescription)"
            return
        }

        // Regenerate sunshine.conf with the new profile applied and
        // restart the engine so Sunshine picks up the new values.
        await runSunshineOperation(
            successMessage: enabled
                ? "Perfil Baixa latência ativado. Motor reiniciado com FEC=0 / min_threads=4."
                : "Perfil Baixa latência desativado. Motor reiniciado com valores padrão."
        ) {
            _ = try configurationManager.writeDefaultFiles(
                overwrite: true,
                audioSink: runtimeSettings.audioSink,
                lowLatency: runtimeSettings.lowLatencyMode
            )
            // Restart only if the engine is actually owned by us — if
            // it isn't running yet the new conf will be read on next
            // start anyway.
            let sunshine = await sunshineManager.status()
            if sunshine.ownedProcessID != nil {
                try await sunshineManager.restart()
            }
        }
    }

    public func exportRemoteWorkSupportBundle() async -> SupportBundleResult? {
        await exportSupportBundleZip()
    }

    public func createDefaultSunshineConfiguration() async {
        await runSunshineOperation(successMessage: "Configuração padrão do motor gerada.") {
            _ = try configurationManager.writeDefaultFiles(
                overwrite: false,
                audioSink: runtimeSettings.audioSink,
                lowLatency: runtimeSettings.lowLatencyMode
            )
        }
    }

    public func startSunshine() async {
        await runSunshineOperation(successMessage: "Motor de vídeo iniciado.") {
            try await sunshineManager.start()
        }
    }

    public func stopSunshine() async {
        await runSunshineOperation(successMessage: "Motor de vídeo parado.") {
            try await sunshineManager.stop()
        }
    }

    public func restartSunshine() async {
        await runSunshineOperation(successMessage: "Motor de vídeo reiniciado.") {
            try await sunshineManager.restart()
        }
    }

    /// Rebuilds the engine configuration (sunshine.conf + apps.json) using
    /// the current settings, then restarts the video engine. Useful when the
    /// audio mode changes, the config gets corrupted, or settings shift while
    /// the engine is live.
    public func regenerateAndRestartVideo() async {
        await runSunshineOperation(successMessage: "Configuração regerada e mecanismo de vídeo reiniciado.") {
            _ = try configurationManager.writeDefaultFiles(
                overwrite: true,
                audioSink: runtimeSettings.audioSink,
                lowLatency: runtimeSettings.lowLatencyMode
            )
            try await sunshineManager.restart()
        }
    }

    public func openSunshineWebUI() async {
        await runOperation(successMessage: "Painel do motor aberto.") {
            try await sunshineManager.openWebUI()
        }
    }

    public func openSettings(for permission: MacPermission) async {
        await runOperation(successMessage: "Ajustes de \(permission.displayName) abertos.") {
            try await permissionManager.openSettings(for: permission)
        }
    }

    /// Resets the macOS TCC entry so a clean grant flow can run. macOS
    /// invalidates Screen Recording grants when the host bundle is replaced;
    /// this command clears any zombie entries (including legacy entries from
    /// when the engine was a separate sub-bundle), truncates the engine logs
    /// so stale crash dumps stop tripping the detection banner, then opens the
    /// Screen Recording pane in System Settings.
    public func resetSunshineScreenRecordingGrant() async {
        // After the flatten in the Etapa 1 rework, the engine inherits
        // MacStream Host's TCC identity (org.macstream.host) — that's the only
        // bundle id that matters now. We still reset the legacy sub-bundle id
        // and the upstream LizardByte id in case the user is upgrading from
        // an older build that left zombie entries in the TCC database.
        let bundleIDs = [
            "org.macstream.host",
            "org.macstream.host.engine.sunshine",
            "dev.lizardbyte.app.Sunshine"
        ]
        var combinedExit: Int32 = 0
        var combinedError = ""
        for bundleID in bundleIDs {
            let result = await commandRunner.run(
                executablePath: "/usr/bin/tccutil",
                arguments: ["reset", "ScreenCapture", bundleID],
                timeout: 5
            )
            if result.exitCode != 0 {
                combinedExit = result.exitCode
                combinedError = result.standardError
            }
        }
        let result = CommandResult(exitCode: combinedExit, standardError: combinedError)
        truncateSunshineLogs()
        if result.exitCode == 0 {
            lastOperationMessage = "Permissão de Gravação de Tela resetada. Abra Ajustes do Sistema e ative o toggle apenas para 'MacStream Host'."
        } else {
            let detail = result.standardError.isEmpty
                ? "tccutil retornou código \(result.exitCode)."
                : result.standardError
            lastOperationMessage = "Não foi possível resetar a permissão: \(detail)"
        }
        try? await permissionManager.openSettings(for: .screenRecording)
        await refresh()
    }

    private func truncateSunshineLogs() {
        let logDir = runtimeSettings.logDirectoryURL
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            logDir.appendingPathComponent("sunshine.out.log"),
            logDir.appendingPathComponent("sunshine.err.log"),
            // Sunshine writes its own structured log here and that's the one
            // we read for diagnostics. Truncating only the redirected stdout
            // leaves stale crash dumps in this file forever.
            home.appendingPathComponent(".config/sunshine/sunshine.log")
        ]
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? Data().write(to: url, options: .atomic)
        }
    }

    /// Convenience flag derived from the current health check — true when the
    /// runtime log analysis matched the Screen Recording TCC failure pattern.
    public var hasSunshineScreenRecordingFailure: Bool {
        healthCheckResult.checks.contains {
            $0.id == .sunshineScreenRecording && $0.status == .fail
        }
    }

    /// True when the engine's process identity reports `AXIsProcessTrusted=false`.
    /// Surfaces an in-app banner that explains why keyboard/mouse from
    /// Moonlight don't reach the Mac (silently dropped CGEventPost) and
    /// offers a one-click reset + System Settings deep link.
    public var hasSunshineAccessibilityFailure: Bool {
        healthCheckResult.checks.contains {
            $0.id == .sunshineAccessibility && $0.status == .fail
        }
    }

    /// Companion to `resetSunshineScreenRecordingGrant`. Clears the
    /// Accessibility TCC entry for `org.macstream.host` so the user gets a
    /// clean re-grant, opens the Accessibility pane, then refreshes.
    /// After re-granting the user should restart the engine so it
    /// re-evaluates `AXIsProcessTrusted()` (Sunshine caches the result
    /// at boot). The banner offers that restart as a separate action.
    public func resetSunshineAccessibilityGrant() async {
        let bundleIDs = [
            "org.macstream.host",
            // Legacy ids — harmless if they don't exist.
            "macstream-agent",
            "macstreamctl"
        ]
        var combinedExit: Int32 = 0
        var combinedError = ""
        for bundleID in bundleIDs {
            let result = await commandRunner.run(
                executablePath: "/usr/bin/tccutil",
                arguments: ["reset", "Accessibility", bundleID],
                timeout: 5
            )
            if result.exitCode != 0 {
                combinedExit = result.exitCode
                combinedError = result.standardError
            }
        }
        if combinedExit == 0 {
            lastOperationMessage = "Permissão de Acessibilidade resetada. Ative MacStream Host na lista e clique em 'Reiniciar motor' para aplicar."
        } else {
            let detail = combinedError.isEmpty
                ? "tccutil retornou código \(combinedExit)."
                : combinedError
            lastOperationMessage = "Não foi possível resetar Acessibilidade: \(detail)"
        }
        try? await permissionManager.openSettings(for: .accessibility)
        await refresh()
    }

    public func requestMacOSPermissions() async {
        let permissionsToRequest: [MacPermission] = [
            .screenRecording,
            .microphone,
            .accessibility
        ]
        let results = await permissionManager.requestPermissions(permissionsToRequest)
        lastPermissionRequestResults = results

        if results.allSatisfy({ $0.statusAfter == .granted }) {
            lastOperationMessage = "Permissões solicitadas. Gravação de Tela da engine será validada pelo teste real."
        } else {
            let pending = results
                .filter { $0.statusAfter != .granted }
                .map { $0.id.displayName }
                .joined(separator: ", ")
            lastOperationMessage = pending.isEmpty
                ? "Permissões solicitadas."
                : "Permissões ainda pendentes: \(pending). Abra Ajustes do Sistema se o macOS não exibiu prompt."
        }

        await refresh()
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
            agentExecutablePath: runtimeSettings.agentExecutablePath,
            configDirectoryPath: configDirectoryPath,
            logDirectoryPath: logDirectoryPath,
            audioCaptureMode: audioCaptureMode,
            powerPolicy: runtimeSettings.powerPolicy,
            hostPrivacyPolicy: runtimeSettings.hostPrivacyPolicy
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
            agentStatus: await agentManager.status(),
            remoteWorkSession: await remoteWorkSessionManager.status(),
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
            detail: "Restaurando mecanismo de vídeo a partir do release upstream fixado."
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

    public func installMissingDependencies() async {
        let sunshine = await sunshineManager.status()
        if sunshine.state == .notInstalled {
            await installManagedSunshine()
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

    private func runRemoteWorkOperation(_ operation: () async throws -> RemoteWorkSessionReport) async {
        do {
            let report = try await operation()
            remoteWorkSession = report
            agentStatus = report.agentStatus
            managedEngineStatus = report.engineStatus
            powerAssertionStatus = report.powerStatus
            hostPrivacyStatus = report.hostPrivacyStatus
            lastOperationMessage = report.nextStep
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
                    ? "Motor de vídeo não disponível. Reinstale o MacStream Host."
                    : "Motor de vídeo pronto\(sunshine.binaryPath.map { " em \($0)" } ?? ".").",
                detectedPath: sunshine.binaryPath,
                detectedVersion: sunshine.version,
                officialURL: URL(string: "https://github.com/LizardByte/Sunshine/releases")
            ),
            DependencyStatus(
                id: .blackHole,
                // BlackHole is optional now that Sunshine v2026.516+ captures
                // system audio via the macOS Tap API on 14.2+. When the user
                // is on native capture, treat "missing" as PASS so the
                // dashboard doesn't keep nagging — the row stays informational.
                status: effectiveBlackHoleStatus(blackHole),
                detail: blackHoleDetail(blackHole),
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

    private func effectiveBlackHoleStatus(_ blackHole: BlackHoleInstallationStatus) -> CheckStatus {
        if runtimeSettings.audioCaptureMode == .blackHole2ch {
            return blackHole.checkStatus
        }
        // Native macOS Tap API capture handles audio without BlackHole.
        // Surface the driver as a passing optional component so the
        // dashboard isn't yellow forever on a perfectly healthy install.
        return .pass
    }

    private func blackHoleDetail(_ blackHole: BlackHoleInstallationStatus) -> String {
        switch (runtimeSettings.audioCaptureMode, blackHole) {
        case (.blackHole2ch, .installed):
            return "Roteamento de áudio do MacStream ativo."
        case (.blackHole2ch, _):
            return "Modo de captura selecionado precisa do driver BlackHole 2ch — clique em Configurar roteamento de áudio."
        case (_, .installed):
            return "Driver disponível como fallback. Captura nativa do macOS está em uso."
        default:
            return "Captura nativa do macOS em uso. O driver é opcional para quem precisar de um Multi-Output Device."
        }
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
            OnboardingStep(id: .sunshine, title: "Verificar mecanismo de vídeo", state: stepState(for: dependencyStatus(.sunshine, dependencies)), detail: dependencies.first(where: { $0.id == .sunshine })?.detail ?? "Validar mecanismo de vídeo."),
            OnboardingStep(id: .blackHole, title: "Verificar roteamento de áudio", state: stepState(for: dependencyStatus(.blackHole, dependencies)), detail: dependencies.first(where: { $0.id == .blackHole })?.detail ?? "Validar roteamento de áudio."),
            OnboardingStep(id: .audio, title: "Configurar áudio", state: stepState(for: audioStatus), detail: audioStatus == .pass ? "Rota de áudio validada." : "Escolha captura nativa do macOS ou roteamento avançado."),
            OnboardingStep(id: .permissions, title: "Validar permissões", state: stepState(for: dashboard.permissionsStatus.aggregateStatus), detail: dashboard.permissionsStatus.aggregateStatus == .pass ? "Permissões críticas OK." : "Permissões críticas (Gravação de Tela ou Microfone) pendentes."),
            OnboardingStep(id: .configuration, title: "Gerar configuração", state: hasConfig ? .passed : .pending, detail: runtimeSettings.sunshineConfigURL.path),
            OnboardingStep(id: .startSunshine, title: "Iniciar streaming", state: dashboard.sunshineStatus.state == .running ? .passed : .pending, detail: dashboard.sunshineStatus.state.displayName),
            OnboardingStep(id: .webUI, title: "Abrir painel avançado", state: dashboard.sunshineStatus.webUIReachable ? .passed : .pending, detail: "https://localhost:47990"),
            OnboardingStep(id: .moonlightPairing, title: "Parear cliente Moonlight", state: allMoonlightItemsDone ? .passed : .active, detail: "Use um IP listado e conclua o checklist no app."),
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

    public func dependencyStatus(for id: DependencyID) -> CheckStatus {
        dependencyStatus(id, dependencyStatuses)
    }

    private func shouldAttemptAgentRecovery(for agent: MacStreamAgentStatus) -> Bool {
        guard agent.launchAgentStatus == .loaded, agent.isRunning == false else {
            return false
        }
        guard let last = lastAgentRecoveryAttempt else { return true }
        return dateProvider().timeIntervalSince(last) >= agentRecoveryCooldown
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
        agentManager = dependencies.agent
        managedEngineManager = dependencies.engine
        powerAssertionManager = dependencies.power
        hostPrivacyManager = dependencies.privacy
        remoteWorkSessionManager = dependencies.remoteWork
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
                status: permissions.runtimeGuidanceStatus,
                detail: "Permissões do app não bloqueiam o start; a captura real é validada pelos logs da engine."
            ),
            SetupChecklistItem(
                id: .sunshineInstalled,
                title: "Verificar mecanismo de vídeo",
                status: sunshine.state == .notInstalled ? .fail : .warning,
                detail: "Embarcado dentro do MacStream Host. Reinstale o app se faltar."
            ),
            SetupChecklistItem(
                id: .blackHoleInstalled,
                title: "Verificar roteamento de áudio",
                status: effectiveBlackHoleStatus(blackHole),
                detail: runtimeSettings.audioCaptureMode == .blackHole2ch
                    ? "Roteamento dedicado selecionado: requer o driver BlackHole 2ch."
                    : "Captura nativa do macOS em uso; o driver é opcional para Multi-Output Device."
            ),
            SetupChecklistItem(
                id: .audioConfiguration,
                title: "Verificar configuração de áudio",
                status: effectiveBlackHoleStatus(blackHole),
                detail: "Modo de captura: \(runtimeSettings.audioCaptureMode.displayName)."
            ),
            SetupChecklistItem(
                id: .networkPorts,
                title: "Verificar portas/rede",
                status: network.aggregateStatus,
                detail: "Diagnóstico inicial cobre IP local e portas do motor."
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
    var agent: AgentManaging
    var engine: ManagedEngineManaging
    var power: PowerAssertionManaging
    var privacy: HostPrivacyManaging
    var remoteWork: RemoteWorkSessionManaging
}
