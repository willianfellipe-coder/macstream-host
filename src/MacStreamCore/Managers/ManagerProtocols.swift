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

public protocol PermissionManaging {
    func currentStatus() async -> MacOSPermissionsStatus
    func openSettings(for permission: MacPermission) async throws
}

public protocol AudioDeviceManaging {
    func listAudioDevices() async -> [AudioDevice]
    func preferredCaptureMode() async -> AudioCaptureMode
    func validateAudioRoute() async -> CheckStatus
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

public protocol ConfigurationManaging {
    var configDirectory: URL { get }
    var sunshineConfigURL: URL { get }
    var appsJSONURL: URL { get }

    func ensureDirectories() throws
    func writeDefaultConfig(overwrite: Bool, audioSink: String?) throws -> ConfigurationFileWriteResult
    func writeDefaultApps(overwrite: Bool) throws -> ConfigurationFileWriteResult
    func writeDefaultFiles(overwrite: Bool, audioSink: String?) throws -> [ConfigurationFileWriteResult]
    func backupExistingConfig() throws -> [URL]
    func validate(_ configuration: RecommendedStreamingConfiguration) -> ConfigurationValidationResult
    func validateSunshineConfiguration(_ contents: String) -> ConfigurationValidationResult
    func renderDefaultSunshineConfiguration(audioSink: String?) -> String
    func renderDefaultAppsJSON() -> String
    func archiveConfigurationDirectory() throws -> URL?
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
