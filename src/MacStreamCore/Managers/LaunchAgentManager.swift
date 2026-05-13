// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import Darwin
#endif

public enum LaunchAgentManagerError: Error, LocalizedError {
    case invalidPlist([String])
    case missingAgentExecutable(String)
    case missingSunshineBinary(String)
    case missingSunshineConfiguration(String)
    case logDirectoryNotWritable(String)
    case launchctlFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPlist(let errors):
            return "Invalid LaunchAgent plist: \(errors.joined(separator: ", "))"
        case .missingAgentExecutable(let path):
            return "MacStream agent executable is missing or not executable at \(path)."
        case .missingSunshineBinary(let path):
            return "Sunshine binary is missing or not executable at \(path)."
        case .missingSunshineConfiguration(let path):
            return "Sunshine config is missing at \(path)."
        case .logDirectoryNotWritable(let path):
            return "Log directory is not writable at \(path)."
        case .launchctlFailed(let message):
            return "launchctl failed: \(message)"
        }
    }
}

public final class DefaultLaunchAgentManager: LaunchAgentManaging {
    public let label: String
    public let installedPlistURL: URL
    public let draftPlistURL: URL

    private let definition: LaunchAgentDefinition
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let runner: CommandRunning
    private let uidProvider: () -> uid_t

    public init(
        definition: LaunchAgentDefinition,
        installedPlistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.macstream.host.agent.plist"),
        draftPlistURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacStreamHost/LaunchAgents/com.macstream.host.agent.plist"),
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init,
        runner: CommandRunning = ProcessCommandRunner(),
        uidProvider: @escaping () -> uid_t = {
            #if os(macOS)
            return getuid()
            #else
            return 0
            #endif
        }
    ) {
        self.definition = definition
        self.label = definition.label
        self.installedPlistURL = installedPlistURL
        self.draftPlistURL = draftPlistURL
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.runner = runner
        self.uidProvider = uidProvider
    }

    public convenience init(
        configurationManager: ConfigurationManaging = DefaultConfigurationManager(),
        agentExecutablePath: String? = DefaultAgentExecutableResolver().resolveExecutable()?.path
    ) {
        let fallbackAgentExecutable = "/Applications/MacStream Host.app/Contents/MacOS/macstream-agent"
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacStreamHost")
            .path

        self.init(
            definition: LaunchAgentDefinition(
                executablePath: agentExecutablePath ?? fallbackAgentExecutable,
                arguments: ["run"],
                logDirectoryPath: logDirectory
            )
        )
    }

    public func status() async -> LaunchAgentStatus {
        guard fileManager.fileExists(atPath: installedPlistURL.path) else {
            return .notInstalled
        }

        guard let contents = try? String(contentsOf: installedPlistURL, encoding: .utf8),
              validatePlist(contents).isValid else {
            return .failed
        }

        let result = await runner.run(
            executablePath: "/bin/launchctl",
            arguments: ["print", "gui/\(uidProvider())/\(label)"],
            timeout: 2
        )

        return result.exitCode == 0 ? .loaded : .installed
    }

    public func renderPlist() throws -> String {
        let data = try PropertyListSerialization.data(
            fromPropertyList: definition.propertyList,
            format: .xml,
            options: 0
        )

        guard let contents = String(data: data, encoding: .utf8) else {
            throw LaunchAgentManagerError.invalidPlist(["Generated plist is not valid UTF-8."])
        }

        let validation = validatePlist(contents)
        guard validation.isValid else {
            throw LaunchAgentManagerError.invalidPlist(validation.errors)
        }

        return contents
    }

    public func validatePlist(_ contents: String) -> LaunchAgentValidationResult {
        guard let data = contents.data(using: .utf8) else {
            return LaunchAgentValidationResult(isValid: false, errors: ["Plist contents are not valid UTF-8."])
        }

        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let plist = object as? [String: Any] else {
                return LaunchAgentValidationResult(isValid: false, errors: ["LaunchAgent plist root must be a dictionary."])
            }

            return validatePropertyList(plist)
        } catch {
            return LaunchAgentValidationResult(isValid: false, errors: [error.localizedDescription])
        }
    }

    public func writeDraftLaunchAgent(overwrite: Bool) throws -> ConfigurationFileWriteResult {
        let contents = try renderPlist()
        let directory = draftPlistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let exists = fileManager.fileExists(atPath: draftPlistURL.path)
        guard overwrite || !exists else {
            return ConfigurationFileWriteResult(url: draftPlistURL, action: .skippedExisting)
        }

        let backupURL = exists ? try backup(draftPlistURL) : nil
        try contents.write(to: draftPlistURL, atomically: true, encoding: .utf8)

        return ConfigurationFileWriteResult(
            url: draftPlistURL,
            action: exists ? .backedUpAndReplaced : .created,
            backupURL: backupURL
        )
    }

    public func installLaunchAgent() async throws {
        try validateInstallPreconditions()
        let contents = try renderPlist()
        let directory = installedPlistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: installedPlistURL.path) {
            _ = try backup(installedPlistURL)
            try fileManager.removeItem(at: installedPlistURL)
        }

        try contents.write(to: installedPlistURL, atomically: true, encoding: .utf8)
    }

    public func uninstallLaunchAgent() async throws {
        guard fileManager.fileExists(atPath: installedPlistURL.path) else {
            return
        }

        try fileManager.removeItem(at: installedPlistURL)
    }

    public func load() async throws {
        if await status() == .loaded {
            return
        }

        if !fileManager.fileExists(atPath: installedPlistURL.path) {
            try await installLaunchAgent()
        }

        let result = await runner.run(
            executablePath: "/bin/launchctl",
            arguments: ["bootstrap", "gui/\(uidProvider())", installedPlistURL.path],
            timeout: 10
        )

        guard result.exitCode == 0 else {
            if await status() == .loaded {
                return
            }

            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw LaunchAgentManagerError.launchctlFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func unload() async throws {
        guard fileManager.fileExists(atPath: installedPlistURL.path) else {
            return
        }

        let result = await runner.run(
            executablePath: "/bin/launchctl",
            arguments: ["bootout", "gui/\(uidProvider())", installedPlistURL.path],
            timeout: 10
        )

        if result.exitCode != 0 {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("No such process") == false &&
                message.localizedCaseInsensitiveContains("not bootstrapped") == false {
                throw LaunchAgentManagerError.launchctlFailed(message)
            }
        }
    }

    private func validateInstallPreconditions() throws {
        guard fileManager.isExecutableFile(atPath: definition.executablePath) else {
            if definition.label == "com.macstream.host.sunshine" {
                throw LaunchAgentManagerError.missingSunshineBinary(definition.executablePath)
            }
            throw LaunchAgentManagerError.missingAgentExecutable(definition.executablePath)
        }

        for requiredFilePath in definition.requiredFilePaths {
            guard fileManager.fileExists(atPath: requiredFilePath) else {
                throw LaunchAgentManagerError.missingSunshineConfiguration(requiredFilePath)
            }
        }

        let logDirectoryURL = URL(fileURLWithPath: definition.logDirectoryPath)
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)

        guard fileManager.isWritableFile(atPath: logDirectoryURL.path) else {
            throw LaunchAgentManagerError.logDirectoryNotWritable(logDirectoryURL.path)
        }
    }

    private func validatePropertyList(_ plist: [String: Any]) -> LaunchAgentValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if plist["Label"] as? String != label {
            errors.append("Label must be \(label).")
        }

        if let arguments = plist["ProgramArguments"] as? [String] {
            if arguments.isEmpty {
                errors.append("ProgramArguments must contain the MacStream agent executable.")
            }

            if arguments.first?.isEmpty != false {
                errors.append("MacStream agent executable path is required.")
            }
        } else {
            errors.append("ProgramArguments must be an array of strings.")
        }

        if plist["RunAtLoad"] as? Bool == nil {
            errors.append("RunAtLoad must be a boolean.")
        }

        if plist["KeepAlive"] as? Bool == nil {
            errors.append("KeepAlive must be a boolean.")
        }

        if plist["StandardOutPath"] as? String == nil {
            warnings.append("StandardOutPath is missing.")
        }

        if plist["StandardErrorPath"] as? String == nil {
            warnings.append("StandardErrorPath is missing.")
        }

        return LaunchAgentValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
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

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
