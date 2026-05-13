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

    public func rotateLogs(maxBytes: UInt64 = 5 * 1024 * 1024, backupCount: Int = 3) throws {
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)

        for fileName in ["sunshine.out.log", "sunshine.err.log", "macstream.log"] {
            try rotate(
                logURL: logDirectoryURL.appendingPathComponent(fileName),
                maxBytes: maxBytes,
                backupCount: backupCount
            )
        }
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

    private func rotate(logURL: URL, maxBytes: UInt64, backupCount: Int) throws {
        guard backupCount > 0,
              fileManager.fileExists(atPath: logURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value > maxBytes else {
            return
        }

        for index in stride(from: backupCount - 1, through: 1, by: -1) {
            let source = rotatedURL(for: logURL, index: index)
            let destination = rotatedURL(for: logURL, index: index + 1)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: destination)
            }
        }

        let firstBackup = rotatedURL(for: logURL, index: 1)
        if fileManager.fileExists(atPath: firstBackup.path) {
            try fileManager.removeItem(at: firstBackup)
        }

        try fileManager.moveItem(at: logURL, to: firstBackup)
        fileManager.createFile(atPath: logURL.path, contents: nil)
    }

    private func rotatedURL(for logURL: URL, index: Int) -> URL {
        logURL.deletingLastPathComponent().appendingPathComponent("\(logURL.lastPathComponent).\(index)")
    }

    private func mask(_ value: String) -> String {
        value
            .replacingOccurrences(of: homePath, with: "~")
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
