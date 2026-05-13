// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultSupportBundleService: SupportBundleServicing {
    private let logManager: LogManaging
    private let configurationManager: ConfigurationManaging
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let homePath: String

    public init(
        logManager: LogManaging,
        configurationManager: ConfigurationManaging,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.logManager = logManager
        self.configurationManager = configurationManager
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.homePath = homePath
    }

    public func writeBundle(to parentDirectory: URL, diagnostics: DiagnosticsReport) async throws -> SupportBundleResult {
        let bundleURL = parentDirectory.appendingPathComponent(
            "MacStreamHost-Support-\(Self.timestampFormatter.string(from: dateProvider()))",
            isDirectory: true
        )
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var files: [String] = []

        try writeDiagnosticsJSON(diagnostics, to: bundleURL.appendingPathComponent("diagnostics.json"))
        files.append("diagnostics.json")

        try writeText(summary(for: diagnostics), to: bundleURL.appendingPathComponent("summary.txt"))
        files.append("summary.txt")

        let logSummary = await logManager.exportDiagnosticsSummary()
        try writeText(redact(logSummary), to: bundleURL.appendingPathComponent("logs.txt"))
        files.append("logs.txt")

        if fileManager.fileExists(atPath: configurationManager.sunshineConfigURL.path) {
            let config = try String(contentsOf: configurationManager.sunshineConfigURL, encoding: .utf8)
            try writeText(redact(config), to: bundleURL.appendingPathComponent("sunshine.conf.txt"))
            files.append("sunshine.conf.txt")
        }

        return SupportBundleResult(directoryPath: bundleURL.path, files: files.sorted())
    }

    private func writeDiagnosticsJSON(_ diagnostics: DiagnosticsReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(diagnostics)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try writeText(redact(text), to: url)
    }

    private func writeText(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func summary(for diagnostics: DiagnosticsReport) -> String {
        let dashboard = diagnostics.dashboard
        let network = dashboard.networkStatus
        var lines = [
            "MacStream Host support bundle",
            "Generated: \(Self.isoFormatter.string(from: diagnostics.generatedAt))",
            "",
            "Sunshine: \(dashboard.sunshineStatus.state.displayName)",
            "Sunshine Web UI: \(dashboard.sunshineStatus.webUIReachable ? "reachable" : "not reachable")",
            "BlackHole: \(dashboard.blackHoleStatus.displayName)",
            "Permissions: \(dashboard.permissionsStatus.aggregateStatus.displayName)",
            "Network: \(network.aggregateStatus.displayName)",
            "Local addresses: \(network.localAddresses.joined(separator: ", "))",
            "Tailscale: \(network.tailscaleAddress ?? "not detected")",
            "LaunchAgent: \(diagnostics.launchAgentStatus.displayName)",
            "Preferred audio: \(diagnostics.preferredAudioMode.displayName)",
            "Health: \(diagnostics.health.status.displayName)",
            "Next step: \(diagnostics.health.recommendedNextStep)",
            "",
            "Files in this bundle are sanitized on a best-effort basis."
        ]

        if diagnostics.audioDevices.isEmpty == false {
            lines.append("")
            lines.append("Audio devices:")
            for device in diagnostics.audioDevices {
                lines.append("- \(device.name) input=\(device.isInput) output=\(device.isOutput) channels=\(device.channels)")
            }
        }

        return redact(lines.joined(separator: "\n"))
    }

    private func redact(_ value: String) -> String {
        var redacted = value
            .replacingOccurrences(of: homePath, with: "~")
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")

        let replacements = [
            (#"(?im)^([^#\n]*(token|secret|password|api[_-]?key)[^=\n]*=).*$"#, "$1 [redacted]"),
            (#"(?im)("([^"]*(token|secret|password|api[_-]?key)[^"]*)"\s*:\s*")[^"]*""#, "$1[redacted]\"")
        ]

        for (pattern, replacement) in replacements {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return redacted
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
