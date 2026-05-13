// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SettingsManagerTests: XCTestCase {
    func testLoadReturnsDefaultsWhenSettingsFileIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let manager = FileSettingsManager(settingsURL: directory.appendingPathComponent("settings.json"))

        let settings = try manager.load()

        XCTAssertEqual(settings.audioCaptureMode, .blackHole2ch)
        XCTAssertTrue(settings.configDirectoryPath.contains("MacStreamHost"))
    }

    func testSaveAndLoadRoundTripsSettings() throws {
        let directory = try makeTemporaryDirectory()
        let manager = FileSettingsManager(settingsURL: directory.appendingPathComponent("settings.json"))
        let settings = MacStreamHostSettings(
            sunshineBinaryPath: "/tmp/sunshine",
            configDirectoryPath: "/tmp/config",
            logDirectoryPath: "/tmp/logs",
            audioCaptureMode: .nativeSystemAudio
        )

        try manager.save(settings)

        XCTAssertEqual(try manager.load(), settings)
    }

    func testSettingsSunshineResolverPrefersExecutableOverride() throws {
        let directory = try makeTemporaryDirectory()
        let binaryURL = directory.appendingPathComponent("sunshine")
        FileManager.default.createFile(atPath: binaryURL.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        let resolver = SettingsSunshineBinaryResolver(
            explicitPath: binaryURL.path,
            fallback: EmptySunshineBinaryResolver()
        )

        XCTAssertEqual(resolver.resolveBinary(), binaryURL)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private struct EmptySunshineBinaryResolver: SunshineBinaryResolving {
    func resolveBinary() -> URL? { nil }
}
