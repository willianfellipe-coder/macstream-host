// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import MacStreamCore

final class MockSunshineManager: SunshineManaging {
    private var currentStatus: SunshineStatus
    var didOpenWebUI = false

    init(currentStatus: SunshineStatus = SunshineStatus(state: .stopped, version: nil, webUIReachable: false)) {
        self.currentStatus = currentStatus
    }

    func isInstalled() async -> Bool {
        currentStatus.state != .notInstalled
    }

    func status() async -> SunshineStatus {
        currentStatus
    }

    func start() async throws {
        currentStatus.state = .running
        currentStatus.webUIReachable = true
        currentStatus.ownedProcessID = 123
    }

    func stop() async throws {
        currentStatus.state = .stopped
        currentStatus.webUIReachable = false
        currentStatus.ownedProcessID = nil
    }

    func restart() async throws {
        try await stop()
        try await start()
    }

    func openWebUI() async throws {
        didOpenWebUI = true
    }
}

final class MockBlackHoleManager: BlackHoleManaging {
    private let statusValue: BlackHoleInstallationStatus

    init(status: BlackHoleInstallationStatus = .missing) {
        self.statusValue = status
    }

    func installationStatus() async -> BlackHoleInstallationStatus {
        statusValue
    }

    func installationGuidance() async -> String {
        "Detectar BlackHole 2ch instalado pelo usuário ou orientar instalação manual segura."
    }
}

final class MockDependencyInstallerManager: DependencyInstalling {
    let artifacts: [DependencyArtifact]
    var sunshineResult: DependencyInstallResult
    var blackHoleResult: DependencyInstallResult

    init() {
        let sunshineArtifact = DependencyArtifact(
            id: .sunshine,
            displayName: "Sunshine Test",
            version: "test",
            downloadURL: URL(string: "https://example.com/sunshine.dmg")!,
            sourceURL: URL(string: "https://example.com/sunshine")!,
            sha256: "00",
            fileName: "sunshine.dmg",
            installerKind: .macOSDMGApplication,
            requiresAdministrator: false,
            requiresReboot: false,
            isPrerelease: false
        )
        let blackHoleArtifact = DependencyArtifact(
            id: .blackHole,
            displayName: "BlackHole Test",
            version: "test",
            downloadURL: URL(string: "https://example.com/blackhole.pkg")!,
            sourceURL: URL(string: "https://example.com/blackhole")!,
            sha256: "00",
            fileName: "blackhole.pkg",
            installerKind: .macOSPKG,
            requiresAdministrator: true,
            requiresReboot: true,
            isPrerelease: false
        )
        self.artifacts = [sunshineArtifact, blackHoleArtifact]
        self.sunshineResult = DependencyInstallResult(
            dependencyID: .sunshine,
            artifact: sunshineArtifact,
            downloadedPath: "/tmp/sunshine.dmg",
            installedPath: "/tmp/Sunshine.app",
            installedBinaryPath: "/tmp/Sunshine.app/Contents/MacOS/sunshine",
            requiresUserCompletion: false,
            message: "Sunshine installed for tests."
        )
        self.blackHoleResult = DependencyInstallResult(
            dependencyID: .blackHole,
            artifact: blackHoleArtifact,
            downloadedPath: "/tmp/blackhole.pkg",
            requiresUserCompletion: true,
            message: "BlackHole installer opened for tests."
        )
    }

    func artifact(for dependencyID: ManagedDependencyID) -> DependencyArtifact? {
        artifacts.first { $0.id == dependencyID }
    }

    func installManagedSunshine() async throws -> DependencyInstallResult {
        sunshineResult
    }

    func downloadAndOpenBlackHoleInstaller() async throws -> DependencyInstallResult {
        blackHoleResult
    }
}

final class MockPermissionManager: PermissionManaging {
    private let permissionsStatus: MacOSPermissionsStatus
    private(set) var requestedPermissions: [MacPermission] = []

    init(
        permissionsStatus: MacOSPermissionsStatus = MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .requiresValidation, detail: "Validar gravação de tela com Sunshine ou teste prático."),
            PermissionCheck(id: .microphone, status: .requiresValidation, detail: "Necessária para rotas de áudio baseadas em loopback."),
            PermissionCheck(id: .localNetwork, status: .granted, detail: "Rede local validada no teste."),
            PermissionCheck(id: .accessibility, status: .notDetermined, detail: "Desejável para entrada em alguns aplicativos.")
        ])
    ) {
        self.permissionsStatus = permissionsStatus
    }

    func currentStatus() async -> MacOSPermissionsStatus {
        permissionsStatus
    }

    func requestPermissions(_ permissions: [MacPermission]) async -> [PermissionRequestResult] {
        requestedPermissions.append(contentsOf: permissions)
        return permissions.map { permission in
            let status = permissionsStatus.checks.first(where: { $0.id == permission })?.status ?? .unknown
            return PermissionRequestResult(
                id: permission,
                statusBefore: status,
                statusAfter: status,
                promptAttempted: status != .granted,
                detail: "Requested \(permission.displayName)."
            )
        }
    }

    func openSettings(for permission: MacPermission) async throws {}
}

final class MockAudioDeviceManager: AudioDeviceManaging {
    private let devices: [AudioDevice]
    private let captureMode: AudioCaptureMode
    private let routeStatus: CheckStatus?

    init(
        devices: [AudioDevice] = [
            AudioDevice(id: "test-built-in-output", name: "Mac Speakers", channels: 2, sampleRate: 48_000, isInput: false, isOutput: true, status: .available)
        ],
        captureMode: AudioCaptureMode = .nativeSystemAudio,
        routeStatus: CheckStatus? = nil
    ) {
        self.devices = devices
        self.captureMode = captureMode
        self.routeStatus = routeStatus
    }

    func listAudioDevices() async -> [AudioDevice] {
        devices
    }

    func preferredCaptureMode() async -> AudioCaptureMode {
        captureMode
    }

    func validateAudioRoute() async -> CheckStatus {
        if let routeStatus {
            return routeStatus
        }

        return devices.isEmpty ? .warning : .pass
    }
}

final class MockNetworkDiagnosticsManager: NetworkDiagnosticsManaging {
    private let result: NetworkDiagnosticResult

    init(
        result: NetworkDiagnosticResult = NetworkDiagnosticResult(
            localAddresses: ["192.168.1.20"],
            tailscaleAddress: nil,
            portChecks: [
                NetworkPortCheck(name: "Web UI", protocolKind: .tcp, port: 47990, status: .warning, detail: "Sunshine ainda não está rodando no teste."),
                NetworkPortCheck(name: "Streaming video", protocolKind: .udp, port: 47998, status: .unknown, detail: "UDP será validado quando Sunshine estiver ativo.")
            ],
            firewallStatus: .unknown
        )
    ) {
        self.result = result
    }

    func runDiagnostics() async -> NetworkDiagnosticResult {
        result
    }
}

final class MockLaunchAgentManager: LaunchAgentManaging {
    private var currentStatus: LaunchAgentStatus
    let label = "com.macstream.host.sunshine"
    let installedPlistURL: URL
    let draftPlistURL: URL

    init(
        status: LaunchAgentStatus = .notInstalled,
        installedPlistURL: URL = URL(fileURLWithPath: "/tmp/com.macstream.host.sunshine.plist"),
        draftPlistURL: URL = URL(fileURLWithPath: "/tmp/com.macstream.host.sunshine.draft.plist")
    ) {
        self.currentStatus = status
        self.installedPlistURL = installedPlistURL
        self.draftPlistURL = draftPlistURL
    }

    func status() async -> LaunchAgentStatus {
        currentStatus
    }

    func renderPlist() throws -> String {
        "<plist version=\"1.0\"><dict><key>Label</key><string>\(label)</string></dict></plist>"
    }

    func validatePlist(_ contents: String) -> LaunchAgentValidationResult {
        LaunchAgentValidationResult(isValid: contents.contains(label))
    }

    func writeDraftLaunchAgent(overwrite: Bool) throws -> ConfigurationFileWriteResult {
        ConfigurationFileWriteResult(url: draftPlistURL, action: .created)
    }

    func installLaunchAgent() async throws {
        currentStatus = .installed
    }

    func uninstallLaunchAgent() async throws {
        currentStatus = .notInstalled
    }

    func load() async throws {
        currentStatus = .loaded
    }

    func unload() async throws {
        currentStatus = .installed
    }
}

final class MockAgentManager: AgentManaging {
    let statusURL: URL
    let commandURL: URL
    var currentStatus: MacStreamAgentStatus
    var lastReport: RemoteWorkSessionReport?
    var commands: [MacStreamAgentCommand] = []
    var didInstall = false
    var didLoad = false
    var didUnload = false

    init(
        statusURL: URL = URL(fileURLWithPath: "/tmp/macstream-agent-status.json"),
        commandURL: URL = URL(fileURLWithPath: "/tmp/macstream-agent-command.json"),
        status: MacStreamAgentStatus = .initial
    ) {
        self.statusURL = statusURL
        self.commandURL = commandURL
        self.currentStatus = status
    }

    func status() async -> MacStreamAgentStatus {
        currentStatus
    }

    func install() async throws {
        didInstall = true
        currentStatus.launchAgentStatus = .installed
    }

    func load() async throws {
        didLoad = true
        currentStatus.launchAgentStatus = .loaded
        currentStatus.isRunning = true
        currentStatus.lastHeartbeat = Date()
    }

    func unload() async throws {
        didUnload = true
        currentStatus.launchAgentStatus = .installed
        currentStatus.isRunning = false
    }

    func writeCommand(_ command: MacStreamAgentCommand) throws {
        commands.append(command)
    }

    func readLastReport() throws -> RemoteWorkSessionReport? {
        lastReport
    }

    func writeReport(_ report: RemoteWorkSessionReport) throws {
        lastReport = report
    }
}

final class MockPowerAssertionManager: PowerAssertionManaging {
    var current = PowerAssertionStatus.inactive
    var acquiredPolicies: [PowerPolicy] = []
    var didRelease = false

    func currentStatus() async -> PowerAssertionStatus {
        current
    }

    func acquire(policy: PowerPolicy) async throws -> PowerAssertionStatus {
        acquiredPolicies.append(policy)
        current = PowerAssertionStatus(isActive: true, policy: policy, assertionID: 42, detail: "Power assertion active.")
        return current
    }

    func release() async throws -> PowerAssertionStatus {
        didRelease = true
        current = PowerAssertionStatus(isActive: false, detail: "Power assertion released.")
        return current
    }
}

final class MockHostPrivacyManager: HostPrivacyManaging {
    var current = HostPrivacyStatus.initial

    func currentStatus() async -> HostPrivacyStatus {
        current
    }

    func apply(policy: HostPrivacyPolicy) async {
        current.policy = policy
    }

    func lockHost() async throws -> HostPrivacyStatus {
        current = HostPrivacyStatus(lastAction: .lockSucceeded, detail: "Host lock requested.")
        return current
    }
}

final class MockManagedEngineManager: ManagedEngineManaging {
    var current = ManagedEngineStatus(components: [
        ManagedEngineComponentStatus(id: .video, status: .pass, detail: "Video OK."),
        ManagedEngineComponentStatus(id: .audio, status: .pass, detail: "Audio OK."),
        ManagedEngineComponentStatus(id: .network, status: .pass, detail: "Network OK.")
    ])

    func status() async -> ManagedEngineStatus {
        current
    }
}

final class MockRemoteWorkSessionManager: RemoteWorkSessionManaging {
    var prepared = false
    var started = false
    var stopped = false
    var didLock = false
    var report = RemoteWorkSessionReport.initial

    func prepare(overwriteConfig: Bool) async throws -> RemoteWorkSessionReport {
        prepared = true
        report.state = .ready
        report.nextStep = "Ready."
        return report
    }

    func start(overwriteConfig: Bool) async throws -> RemoteWorkSessionReport {
        started = true
        report.state = .starting
        report.nextStep = "Starting."
        return report
    }

    func stop() async throws -> RemoteWorkSessionReport {
        stopped = true
        report.state = .stopping
        report.nextStep = "Stopping."
        return report
    }

    func status() async -> RemoteWorkSessionReport {
        report
    }

    func lockHostForPrivacy() async throws -> RemoteWorkSessionReport {
        didLock = true
        report.hostPrivacyStatus = HostPrivacyStatus(lastAction: .lockRequested, detail: "Lock requested.")
        return report
    }
}

final class MockConfigurationManager: ConfigurationManaging {
    let configDirectory: URL
    let sunshineConfigURL: URL
    let appsJSONURL: URL
    var archivedConfigurationDirectory: URL?

    init(
        configDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostTestConfig")
    ) {
        self.configDirectory = configDirectory
        self.sunshineConfigURL = configDirectory.appendingPathComponent("sunshine.conf")
        self.appsJSONURL = configDirectory.appendingPathComponent("apps.json")
    }

    func ensureDirectories() throws {}

    func writeDefaultConfig(overwrite: Bool, audioSink: String?) throws -> ConfigurationFileWriteResult {
        ConfigurationFileWriteResult(url: sunshineConfigURL, action: .created)
    }

    func writeDefaultApps(overwrite: Bool) throws -> ConfigurationFileWriteResult {
        ConfigurationFileWriteResult(url: appsJSONURL, action: .created)
    }

    func writeDefaultFiles(overwrite: Bool, audioSink: String?) throws -> [ConfigurationFileWriteResult] {
        [
            try writeDefaultConfig(overwrite: overwrite, audioSink: audioSink),
            try writeDefaultApps(overwrite: overwrite)
        ]
    }

    func backupExistingConfig() throws -> [URL] {
        []
    }

    func validate(_ configuration: RecommendedStreamingConfiguration) -> ConfigurationValidationResult {
        SunshineConfigurationValidator.validateStreamingConfiguration(configuration)
    }

    func validateSunshineConfiguration(_ contents: String) -> ConfigurationValidationResult {
        SunshineConfigurationValidator.validateSunshineConfig(contents)
    }

    func renderDefaultSunshineConfiguration(audioSink: String?) -> String {
        [
            "sunshine_name = MacStream Host",
            "locale = pt_BR",
            "min_log_level = info",
            "stream_audio = enabled",
            "audio_sink = \(audioSink ?? "")",
            "upnp = disabled",
            "address_family = ipv4",
            "port = 47989",
            "origin_web_ui_allowed = pc"
        ].joined(separator: "\n")
    }

    func renderDefaultAppsJSON() -> String {
        """
        {
          "env": {},
          "apps": [
            {
              "name": "Desktop",
              "output": "",
              "cmd": "",
              "detached": [],
              "image-path": "desktop.png"
            }
          ]
        }
        """
    }

    func archiveConfigurationDirectory() throws -> URL? {
        archivedConfigurationDirectory = configDirectory.deletingLastPathComponent()
            .appendingPathComponent("\(configDirectory.lastPathComponent).reset-test")
        return archivedConfigurationDirectory
    }
}

final class MockSettingsManager: SettingsManaging {
    let settingsURL: URL
    var settings: MacStreamHostSettings

    init(
        settings: MacStreamHostSettings = .defaults(),
        settingsURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostTestSettings.json")
    ) {
        self.settings = settings
        self.settingsURL = settingsURL
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

final class MockLogManager: LogManaging {
    let logDirectoryURL: URL
    private let entries: [LogEntry]

    init(
        logDirectoryURL: URL = URL(fileURLWithPath: "/tmp/MacStreamHostLogs"),
        entries: [LogEntry] = [
            LogEntry(subsystem: "MacStreamCore", message: "Test diagnostics initialized."),
            LogEntry(subsystem: "Sunshine", message: "Test Sunshine log.")
        ]
    ) {
        self.logDirectoryURL = logDirectoryURL
        self.entries = entries
    }

    func recentLogs(maxLines: Int) async -> [LogEntry] {
        entries.prefix(maxLines).map { $0 }
    }

    func exportDiagnosticsSummary() async -> String {
        "MacStream Host test diagnostics."
    }

    func rotateLogs(maxBytes: UInt64, backupCount: Int) throws {}
}

final class StaticMoonlightPairingGuide: MoonlightPairingGuiding {
    func pairingSteps() -> [PairingStep] {
        [
            PairingStep(id: 1, title: "Abra Moonlight", detail: "Use o cliente Moonlight."),
            PairingStep(id: 2, title: "Encontre o Mac", detail: "Selecione o host."),
            PairingStep(id: 3, title: "Use o PIN", detail: "Digite o PIN na Web UI."),
            PairingStep(id: 4, title: "Abra Desktop", detail: "Valide a transmissão.")
        ]
    }
}

@MainActor
func makeTestAppState(
    sunshine: SunshineManaging = MockSunshineManager(),
    blackHole: BlackHoleManaging = MockBlackHoleManager(),
    dependencyInstaller: DependencyInstalling = MockDependencyInstallerManager(),
    permissions: PermissionManaging = MockPermissionManager(),
    audio: AudioDeviceManaging = MockAudioDeviceManager(),
    network: NetworkDiagnosticsManaging = MockNetworkDiagnosticsManager(),
    launchAgent: LaunchAgentManaging = MockLaunchAgentManager(),
    configuration: ConfigurationManaging = MockConfigurationManager(),
    settingsManager: SettingsManaging = MockSettingsManager(),
    runtimeSettings: MacStreamHostSettings = .defaults(),
    log: LogManaging = MockLogManager(),
    pairingGuide: MoonlightPairingGuiding = StaticMoonlightPairingGuide(),
    agent: AgentManaging = MockAgentManager(),
    engine: ManagedEngineManaging = MockManagedEngineManager(),
    power: PowerAssertionManaging = MockPowerAssertionManager(),
    privacy: HostPrivacyManaging = MockHostPrivacyManager(),
    remoteWork: RemoteWorkSessionManaging = MockRemoteWorkSessionManager()
) -> AppState {
    AppState(
        sunshineManager: sunshine,
        blackHoleManager: blackHole,
        dependencyInstallerManager: dependencyInstaller,
        permissionManager: permissions,
        audioDeviceManager: audio,
        networkDiagnosticsManager: network,
        launchAgentManager: launchAgent,
        configurationManager: configuration,
        settingsManager: settingsManager,
        runtimeSettings: runtimeSettings,
        logManager: log,
        pairingGuide: pairingGuide,
        healthCheckService: DefaultHealthCheckService(
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
        ),
        agentManager: agent,
        managedEngineManager: engine,
        powerAssertionManager: power,
        hostPrivacyManager: privacy,
        remoteWorkSessionManager: remoteWork
    )
}
