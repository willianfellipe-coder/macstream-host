// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct DiagnosticsReport: Codable, Equatable {
    public var generatedAt: Date
    public var settings: MacStreamHostSettings
    public var dashboard: DashboardSnapshot
    public var health: HealthCheckResult
    public var audioDevices: [AudioDevice]
    public var preferredAudioMode: AudioCaptureMode
    public var launchAgentStatus: LaunchAgentStatus
    public var agentStatus: MacStreamAgentStatus
    public var remoteWorkSession: RemoteWorkSessionReport
    public var dependencies: [DependencyStatus]
    public var buildInfo: AppBuildInfo

    public init(
        generatedAt: Date = Date(),
        settings: MacStreamHostSettings,
        dashboard: DashboardSnapshot,
        health: HealthCheckResult,
        audioDevices: [AudioDevice],
        preferredAudioMode: AudioCaptureMode,
        launchAgentStatus: LaunchAgentStatus,
        agentStatus: MacStreamAgentStatus = .initial,
        remoteWorkSession: RemoteWorkSessionReport = .initial,
        dependencies: [DependencyStatus] = [],
        buildInfo: AppBuildInfo = .current
    ) {
        self.generatedAt = generatedAt
        self.settings = settings
        self.dashboard = dashboard
        self.health = health
        self.audioDevices = audioDevices
        self.preferredAudioMode = preferredAudioMode
        self.launchAgentStatus = launchAgentStatus
        self.agentStatus = agentStatus
        self.remoteWorkSession = remoteWorkSession
        self.dependencies = dependencies
        self.buildInfo = buildInfo
    }
}
