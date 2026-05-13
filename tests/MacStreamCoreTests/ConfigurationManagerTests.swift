// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class ConfigurationManagerTests: XCTestCase {
    func testWriteDefaultFilesCreatesDirectoryAndFiles() throws {
        let directory = try makeTemporaryDirectory()
        let manager = DefaultConfigurationManager(
            configDirectory: directory,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )

        let results = try manager.writeDefaultFiles(overwrite: false, audioSink: "BlackHole 2ch")

        XCTAssertEqual(results.map(\.action), [.created, .created])
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.sunshineConfigURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.appsJSONURL.path))

        let sunshineConfig = try String(contentsOf: manager.sunshineConfigURL, encoding: .utf8)
        XCTAssertTrue(sunshineConfig.contains("audio_sink = BlackHole 2ch"))

        let appsData = try Data(contentsOf: manager.appsJSONURL)
        let appsJSON = try JSONSerialization.jsonObject(with: appsData) as? [String: Any]
        XCTAssertNotNil(appsJSON?["apps"])
    }

    func testWriteWithoutOverwriteSkipsExistingFile() throws {
        let directory = try makeTemporaryDirectory()
        let manager = DefaultConfigurationManager(configDirectory: directory)
        try manager.ensureDirectories()
        try "custom = true\n".write(to: manager.sunshineConfigURL, atomically: true, encoding: .utf8)

        let result = try manager.writeDefaultConfig(overwrite: false, audioSink: "BlackHole 2ch")

        XCTAssertEqual(result.action, .skippedExisting)
        XCTAssertNil(result.backupURL)
        let contents = try String(contentsOf: manager.sunshineConfigURL, encoding: .utf8)
        XCTAssertEqual(contents, "custom = true\n")
    }

    func testOverwriteBacksUpExistingFileBeforeReplacing() throws {
        let directory = try makeTemporaryDirectory()
        let manager = DefaultConfigurationManager(
            configDirectory: directory,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )
        try manager.ensureDirectories()
        try "custom = true\n".write(to: manager.sunshineConfigURL, atomically: true, encoding: .utf8)

        let result = try manager.writeDefaultConfig(overwrite: true, audioSink: nil)

        XCTAssertEqual(result.action, .backedUpAndReplaced)
        let backupURL = try XCTUnwrap(result.backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(backupURL.lastPathComponent, "sunshine.conf.backup-19700101-000000")

        let backupContents = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertEqual(backupContents, "custom = true\n")

        let newContents = try String(contentsOf: manager.sunshineConfigURL, encoding: .utf8)
        XCTAssertTrue(newContents.contains("sunshine_name = MacStream Host"))
        XCTAssertTrue(newContents.contains("audio_sink = "))
    }

    func testBackupExistingConfigBacksUpBothKnownFiles() throws {
        let directory = try makeTemporaryDirectory()
        let manager = DefaultConfigurationManager(
            configDirectory: directory,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )
        try manager.ensureDirectories()
        try "old config\n".write(to: manager.sunshineConfigURL, atomically: true, encoding: .utf8)
        try "{\"apps\":[]}\n".write(to: manager.appsJSONURL, atomically: true, encoding: .utf8)

        let backups = try manager.backupExistingConfig()

        XCTAssertEqual(backups.count, 2)
        XCTAssertTrue(backups.contains(where: { $0.lastPathComponent == "sunshine.conf.backup-19700101-000000" }))
        XCTAssertTrue(backups.contains(where: { $0.lastPathComponent == "apps.json.backup-19700101-000000" }))
    }

    func testArchiveConfigurationDirectoryMovesConfigDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let manager = DefaultConfigurationManager(
            configDirectory: directory,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )
        _ = try manager.writeDefaultFiles(overwrite: false, audioSink: "BlackHole 2ch")

        let archiveURL = try manager.archiveConfigurationDirectory()
        if let archiveURL {
            addTeardownBlock {
                try? FileManager.default.removeItem(at: archiveURL)
            }
        }

        XCTAssertEqual(archiveURL?.lastPathComponent, "\(directory.lastPathComponent).reset-19700101-000000")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL?.path ?? ""))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
