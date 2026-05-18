// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public protocol SunshineManaging {
    func isInstalled() async -> Bool
    func status() async -> SunshineStatus
    func start() async throws
    func stop() async throws
    func restart() async throws
    func openWebUI() async throws
}

public protocol BlackHoleManaging {
    func installationStatus() async -> BlackHoleInstallationStatus
    func installationGuidance() async -> String
}

public protocol DependencyInstalling {
    var artifacts: [DependencyArtifact] { get }

    func artifact(for dependencyID: ManagedDependencyID) -> DependencyArtifact?
    func installManagedSunshine() async throws -> DependencyInstallResult
}

public protocol PermissionManaging {
    func currentStatus() async -> MacOSPermissionsStatus
    func requestPermissions(_ permissions: [MacPermission]) async -> [PermissionRequestResult]
    func openSettings(for permission: MacPermission) async throws
}

public protocol AudioDeviceManaging {
    func listAudioDevices() async -> [AudioDevice]
    func preferredCaptureMode() async -> AudioCaptureMode
    func validateAudioRoute() async -> CheckStatus

    /// Returns the device the system is currently routing output to (the
    /// "default output" device in Audio MIDI Setup). Returns nil when the
    /// CoreAudio query fails or no default output is configured.
    func currentSystemOutputDevice() async -> AudioDevice?

    /// Switches the system's default audio output to BlackHole 2ch so the
    /// engine actually captures something. Without this, Sunshine reads
    /// silence regardless of `audio_sink = BlackHole 2ch` in the config.
    /// The call doesn't require any TCC permission — it's plain CoreAudio
    /// routing.
    func routeSystemOutputToBlackHole() async -> AudioRoutingResult

    /// Switches the system's default audio output to the provided device.
    /// Used by the UI to restore the previous output after a routing.
    func routeSystemOutput(to deviceID: String) async -> AudioRoutingResult
}

public protocol NetworkDiagnosticsManaging {
    func runDiagnostics() async -> NetworkDiagnosticResult
}

public protocol SettingsManaging {
    var settingsURL: URL { get }

    func load() throws -> MacStreamHostSettings
    func save(_ settings: MacStreamHostSettings) throws
    func reset() throws -> MacStreamHostSettings
}

public protocol LaunchAgentManaging {
    var label: String { get }
    var installedPlistURL: URL { get }
    var draftPlistURL: URL { get }

    func status() async -> LaunchAgentStatus
    func renderPlist() throws -> String
    func validatePlist(_ contents: String) -> LaunchAgentValidationResult
    func writeDraftLaunchAgent(overwrite: Bool) throws -> ConfigurationFileWriteResult
    func installLaunchAgent() async throws
    func uninstallLaunchAgent() async throws
    func load() async throws
    func unload() async throws
}

public protocol AgentManaging {
    var statusURL: URL { get }
    var commandURL: URL { get }

    func status() async -> MacStreamAgentStatus
    func install() async throws
    func load() async throws
    func unload() async throws
    func writeCommand(_ command: MacStreamAgentCommand) throws
    func readLastReport() throws -> RemoteWorkSessionReport?
    func writeReport(_ report: RemoteWorkSessionReport) throws
    func recoverIfStale() async throws -> Bool
}

public protocol PowerAssertionManaging {
    func currentStatus() async -> PowerAssertionStatus
    func acquire(policy: PowerPolicy) async throws -> PowerAssertionStatus
    func release() async throws -> PowerAssertionStatus
}

public protocol HostPrivacyManaging {
    func currentStatus() async -> HostPrivacyStatus
    func apply(policy: HostPrivacyPolicy) async
    func lockHost() async throws -> HostPrivacyStatus
}

public protocol ManagedEngineManaging {
    func status() async -> ManagedEngineStatus
}

public protocol RemoteWorkSessionManaging {
    func prepare(overwriteConfig: Bool) async throws -> RemoteWorkSessionReport
    func start(overwriteConfig: Bool) async throws -> RemoteWorkSessionReport
    func stop() async throws -> RemoteWorkSessionReport
    func status() async -> RemoteWorkSessionReport
    func lockHostForPrivacy() async throws -> RemoteWorkSessionReport
}

public protocol ConfigurationManaging {
    var configDirectory: URL { get }
    var sunshineConfigURL: URL { get }
    var appsJSONURL: URL { get }

    func ensureDirectories() throws
    func writeDefaultConfig(overwrite: Bool, audioSink: String?, lowLatency: Bool) throws -> ConfigurationFileWriteResult
    func writeDefaultApps(overwrite: Bool) throws -> ConfigurationFileWriteResult
    func writeDefaultFiles(overwrite: Bool, audioSink: String?, lowLatency: Bool) throws -> [ConfigurationFileWriteResult]
    func backupExistingConfig() throws -> [URL]
    func validate(_ configuration: RecommendedStreamingConfiguration) -> ConfigurationValidationResult
    func validateSunshineConfiguration(_ contents: String) -> ConfigurationValidationResult
    func renderDefaultSunshineConfiguration(audioSink: String?, lowLatency: Bool) -> String
    func renderDefaultAppsJSON() -> String
    func archiveConfigurationDirectory() throws -> URL?
}

public extension ConfigurationManaging {
    /// Backwards-compatible defaults so callers that don't care about
    /// latency tuning keep the previous behaviour.
    func writeDefaultConfig(overwrite: Bool, audioSink: String?) throws -> ConfigurationFileWriteResult {
        try writeDefaultConfig(overwrite: overwrite, audioSink: audioSink, lowLatency: false)
    }

    func writeDefaultFiles(overwrite: Bool, audioSink: String?) throws -> [ConfigurationFileWriteResult] {
        try writeDefaultFiles(overwrite: overwrite, audioSink: audioSink, lowLatency: false)
    }

    func renderDefaultSunshineConfiguration(audioSink: String?) -> String {
        renderDefaultSunshineConfiguration(audioSink: audioSink, lowLatency: false)
    }
}

public protocol LogManaging {
    var logDirectoryURL: URL { get }

    func recentLogs(maxLines: Int) async -> [LogEntry]
    func exportDiagnosticsSummary() async -> String
    func rotateLogs(maxBytes: UInt64, backupCount: Int) throws
}

public protocol MoonlightPairingGuiding {
    func pairingSteps() -> [PairingStep]
}

public protocol HealthCheckServicing {
    func runHealthCheck() async -> HealthCheckResult
}

public protocol SoftResetServicing {
    func reset() async throws -> SoftResetResult
}

public protocol SupportBundleServicing {
    func writeBundle(options: SupportBundleOptions, diagnostics: DiagnosticsReport, buildInfo: AppBuildInfo) async throws -> SupportBundleResult
}
