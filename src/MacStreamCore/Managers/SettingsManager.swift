// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum SettingsManagerError: Error, LocalizedError {
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid settings path: \(path)"
        }
    }
}

public final class FileSettingsManager: SettingsManaging {
    public let settingsURL: URL

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacStreamHost/settings.json"),
        fileManager: FileManager = .default
    ) {
        self.settingsURL = settingsURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> MacStreamHostSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .defaults()
        }

        let data = try Data(contentsOf: settingsURL)
        let settings = try decoder.decode(MacStreamHostSettings.self, from: data)
        return settings.normalized()
    }

    public func save(_ settings: MacStreamHostSettings) throws {
        let normalized = settings.normalized()
        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(normalized)
        try data.write(to: settingsURL, options: .atomic)
    }

    public func reset() throws -> MacStreamHostSettings {
        let defaults = MacStreamHostSettings.defaults()
        try save(defaults)
        return defaults
    }
}

public final class SettingsSunshineBinaryResolver: SunshineBinaryResolving {
    private let explicitPath: String?
    private let fallback: SunshineBinaryResolving
    private let fileManager: FileManager

    public init(
        explicitPath: String?,
        fallback: SunshineBinaryResolving = DefaultSunshineBinaryResolver(),
        fileManager: FileManager = .default
    ) {
        self.explicitPath = explicitPath
        self.fallback = fallback
        self.fileManager = fileManager
    }

    public func resolveBinary() -> URL? {
        if let explicitPath, explicitPath.isEmpty == false {
            let expanded = (explicitPath as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        return fallback.resolveBinary()
    }
}
