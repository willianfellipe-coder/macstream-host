// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultSoftResetService: SoftResetServicing {
    private let sunshineManager: SunshineManaging
    private let launchAgentManager: LaunchAgentManaging
    private let configurationManager: ConfigurationManaging

    public init(
        sunshineManager: SunshineManaging,
        launchAgentManager: LaunchAgentManaging,
        configurationManager: ConfigurationManaging
    ) {
        self.sunshineManager = sunshineManager
        self.launchAgentManager = launchAgentManager
        self.configurationManager = configurationManager
    }

    public func reset() async throws -> SoftResetResult {
        var actions: [String] = []
        var archivedConfigDirectory: URL?

        do {
            try await sunshineManager.stop()
            actions.append("Stopped owned Sunshine process.")
        } catch SunshineManagerError.noOwnedProcess {
            actions.append("No owned Sunshine process was running.")
        }

        do {
            try await launchAgentManager.unload()
            actions.append("Unloaded LaunchAgent.")
        } catch {
            actions.append("LaunchAgent unload skipped: \(error.localizedDescription)")
        }

        do {
            try await launchAgentManager.uninstallLaunchAgent()
            actions.append("Removed LaunchAgent.")
        } catch {
            actions.append("LaunchAgent removal skipped: \(error.localizedDescription)")
        }

        archivedConfigDirectory = try configurationManager.archiveConfigurationDirectory()
        if let archivedConfigDirectory {
            actions.append("Archived config directory at \(archivedConfigDirectory.path).")
        } else {
            actions.append("No config directory to archive.")
        }

        return SoftResetResult(actions: actions, archivedConfigDirectory: archivedConfigDirectory)
    }
}
