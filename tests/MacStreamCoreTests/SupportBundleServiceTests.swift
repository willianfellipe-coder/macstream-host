// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SupportBundleServiceTests: XCTestCase {
    func testSupportBundleWritesSanitizedDiagnosticsLogsAndConfig() async throws {
        let root = try makeTemporaryDirectory()
        let configDirectory = root.appendingPathComponent("config", isDirectory: true)
        let logDirectory = root.appendingPathComponent("logs", isDirectory: true)
        let outputDirectory = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let configurationManager = DefaultConfigurationManager(configDirectory: configDirectory)
        try configurationManager.ensureDirectories()
        try """
        sunshine_name = Test
        api_token = should-not-leak
        audio_sink = BlackHole 2ch
        """.write(to: configurationManager.sunshineConfigURL, atomically: true, encoding: .utf8)

        try "log path \(root.path) password = secret\n".write(
            to: logDirectory.appendingPathComponent("macstream.log"),
            atomically: true,
            encoding: .utf8
        )

        let service = DefaultSupportBundleService(
            logManager: DefaultLogManager(logDirectoryURL: logDirectory, homePath: root.path),
            configurationManager: configurationManager,
            dateProvider: { Date(timeIntervalSince1970: 0) },
            homePath: root.path
        )

        let result = try await service.writeBundle(
            to: outputDirectory,
            diagnostics: DiagnosticsReport(
                generatedAt: Date(timeIntervalSince1970: 0),
                settings: MacStreamHostSettings(
                    configDirectoryPath: root.appendingPathComponent("config").path,
                    logDirectoryPath: root.appendingPathComponent("logs").path,
                    audioCaptureMode: .blackHole2ch
                ),
                dashboard: .initial,
                health: HealthCheckResult(checks: []),
                audioDevices: [],
                preferredAudioMode: .blackHole2ch,
                launchAgentStatus: .notInstalled
            )
        )

        XCTAssertEqual(result.files, ["diagnostics.json", "logs.txt", "summary.txt", "sunshine.conf.txt"])
        let bundleURL = URL(fileURLWithPath: result.directoryPath)
        let diagnostics = try String(contentsOf: bundleURL.appendingPathComponent("diagnostics.json"), encoding: .utf8)
        let logs = try String(contentsOf: bundleURL.appendingPathComponent("logs.txt"), encoding: .utf8)
        let config = try String(contentsOf: bundleURL.appendingPathComponent("sunshine.conf.txt"), encoding: .utf8)

        XCTAssertFalse(diagnostics.contains(root.path))
        XCTAssertFalse(logs.contains(root.path))
        XCTAssertFalse(config.contains("should-not-leak"))
        XCTAssertTrue(config.contains("[redacted]"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostSupportBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
