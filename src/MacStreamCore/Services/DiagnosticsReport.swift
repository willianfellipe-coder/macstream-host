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

    public init(
        generatedAt: Date = Date(),
        settings: MacStreamHostSettings,
        dashboard: DashboardSnapshot,
        health: HealthCheckResult,
        audioDevices: [AudioDevice],
        preferredAudioMode: AudioCaptureMode,
        launchAgentStatus: LaunchAgentStatus
    ) {
        self.generatedAt = generatedAt
        self.settings = settings
        self.dashboard = dashboard
        self.health = health
        self.audioDevices = audioDevices
        self.preferredAudioMode = preferredAudioMode
        self.launchAgentStatus = launchAgentStatus
    }
}
