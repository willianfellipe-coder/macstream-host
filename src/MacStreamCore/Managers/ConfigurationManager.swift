// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum ConfigurationManagerError: Error, LocalizedError {
    case invalidSunshineConfiguration([String])
    case invalidAppsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSunshineConfiguration(let errors):
            return "Invalid Sunshine configuration: \(errors.joined(separator: ", "))"
        case .invalidAppsJSON:
            return "Generated apps.json is not valid JSON."
        }
    }
}

public final class DefaultConfigurationManager: ConfigurationManaging {
    public let configDirectory: URL
    public let sunshineConfigURL: URL
    public let appsJSONURL: URL

    private let fileManager: FileManager
    private let dateProvider: () -> Date

    public init(
        configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacStreamHost/sunshine"),
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.configDirectory = configDirectory
        self.sunshineConfigURL = configDirectory.appendingPathComponent("sunshine.conf")
        self.appsJSONURL = configDirectory.appendingPathComponent("apps.json")
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public func ensureDirectories() throws {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }

    public func writeDefaultConfig(overwrite: Bool, audioSink: String?) throws -> ConfigurationFileWriteResult {
        let contents = renderDefaultSunshineConfiguration(audioSink: audioSink)
        let validation = validateSunshineConfiguration(contents)

        guard validation.isValid else {
            throw ConfigurationManagerError.invalidSunshineConfiguration(validation.errors)
        }

        return try write(contents, to: sunshineConfigURL, overwrite: overwrite)
    }

    public func writeDefaultApps(overwrite: Bool) throws -> ConfigurationFileWriteResult {
        let contents = renderDefaultAppsJSON()

        guard let data = contents.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw ConfigurationManagerError.invalidAppsJSON
        }

        return try write(contents, to: appsJSONURL, overwrite: overwrite)
    }

    public func writeDefaultFiles(overwrite: Bool, audioSink: String?) throws -> [ConfigurationFileWriteResult] {
        [
            try writeDefaultConfig(overwrite: overwrite, audioSink: audioSink),
            try writeDefaultApps(overwrite: overwrite)
        ]
    }

    public func backupExistingConfig() throws -> [URL] {
        var backups: [URL] = []

        for url in [sunshineConfigURL, appsJSONURL] where fileManager.fileExists(atPath: url.path) {
            backups.append(try backup(url))
        }

        return backups
    }

    public func validate(_ configuration: RecommendedStreamingConfiguration) -> ConfigurationValidationResult {
        SunshineConfigurationValidator.validateStreamingConfiguration(configuration)
    }

    public func validateSunshineConfiguration(_ contents: String) -> ConfigurationValidationResult {
        SunshineConfigurationValidator.validateSunshineConfig(contents)
    }

    public func renderDefaultSunshineConfiguration(audioSink: String?) -> String {
        let sinkLine = "audio_sink = \(audioSink ?? "")"

        return [
            "sunshine_name = MacStream Host",
            "locale = pt_BR",
            "min_log_level = info",
            "system_tray = disabled",
            "",
            "keyboard = enabled",
            "mouse = enabled",
            "native_pen_touch = enabled",
            "high_resolution_scrolling = enabled",
            "",
            "stream_audio = enabled",
            "# MVP default: prefer native macOS audio capture when supported.",
            "# Fallback: set to BlackHole 2ch if native capture fails.",
            sinkLine,
            "",
            "upnp = disabled",
            "address_family = ipv4",
            "port = 47989",
            "origin_web_ui_allowed = pc",
            ""
        ].joined(separator: "\n")
    }

    public func renderDefaultAppsJSON() -> String {
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

    public func archiveConfigurationDirectory() throws -> URL? {
        guard fileManager.fileExists(atPath: configDirectory.path) else {
            return nil
        }

        let archiveURL = uniqueArchiveURL(for: configDirectory)
        try fileManager.moveItem(at: configDirectory, to: archiveURL)
        return archiveURL
    }

    private func write(_ contents: String, to url: URL, overwrite: Bool) throws -> ConfigurationFileWriteResult {
        try ensureDirectories()

        let fileExists = fileManager.fileExists(atPath: url.path)
        guard overwrite || !fileExists else {
            return ConfigurationFileWriteResult(url: url, action: .skippedExisting)
        }

        let backupURL = fileExists ? try backup(url) : nil
        try contents.write(to: url, atomically: true, encoding: .utf8)

        return ConfigurationFileWriteResult(
            url: url,
            action: fileExists ? .backedUpAndReplaced : .created,
            backupURL: backupURL
        )
    }

    private func backup(_ url: URL) throws -> URL {
        let backupURL = uniqueBackupURL(for: url)
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL
    }

    private func uniqueBackupURL(for url: URL) -> URL {
        let timestamp = Self.backupDateFormatter.string(from: dateProvider())
        let baseName = "\(url.lastPathComponent).backup-\(timestamp)"
        var candidate = url.deletingLastPathComponent().appendingPathComponent(baseName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(baseName)-\(suffix)")
            suffix += 1
        }

        return candidate
    }

    private func uniqueArchiveURL(for url: URL) -> URL {
        let timestamp = Self.backupDateFormatter.string(from: dateProvider())
        let parent = url.deletingLastPathComponent()
        let baseName = "\(url.lastPathComponent).reset-\(timestamp)"
        var candidate = parent.appendingPathComponent(baseName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName)-\(suffix)")
            suffix += 1
        }

        return candidate
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
