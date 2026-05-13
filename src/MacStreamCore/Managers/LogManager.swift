// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultLogManager: LogManaging {
    public let logDirectoryURL: URL

    private let fileManager: FileManager
    private let homePath: String

    public init(
        logDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacStreamHost"),
        fileManager: FileManager = .default,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.logDirectoryURL = logDirectoryURL
        self.fileManager = fileManager
        self.homePath = homePath
    }

    public func recentLogs(maxLines: Int) async -> [LogEntry] {
        let files = [
            ("Sunshine stdout", logDirectoryURL.appendingPathComponent("sunshine.out.log")),
            ("Sunshine stderr", logDirectoryURL.appendingPathComponent("sunshine.err.log")),
            ("MacStream Host", logDirectoryURL.appendingPathComponent("macstream.log"))
        ]

        return files.flatMap { subsystem, url in
            recentLines(from: url, maxLines: maxLines).map {
                LogEntry(subsystem: subsystem, message: mask($0))
            }
        }
        .suffix(maxLines)
    }

    public func exportDiagnosticsSummary() async -> String {
        let logs = await recentLogs(maxLines: 200)
        var lines = [
            "MacStream Host diagnostics",
            "Log directory: \(mask(logDirectoryURL.path))",
            ""
        ]

        if logs.isEmpty {
            lines.append("No logs found.")
        } else {
            for log in logs {
                lines.append("[\(log.subsystem)] \(log.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func recentLines(from url: URL, maxLines: Int) -> [String] {
        guard fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .suffix(maxLines)
            .map(String.init)
    }

    private func mask(_ value: String) -> String {
        value
            .replacingOccurrences(of: homePath, with: "~")
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
