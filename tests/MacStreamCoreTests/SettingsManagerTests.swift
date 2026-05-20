// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SettingsManagerTests: XCTestCase {
    func testLoadReturnsDefaultsWhenSettingsFileIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let manager = FileSettingsManager(settingsURL: directory.appendingPathComponent("settings.json"))

        let settings = try manager.load()

        XCTAssertEqual(settings.audioCaptureMode, .nativeSystemAudio)
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

    func testLoadingLegacySettingsWithoutDirectoryFieldsFallsBackToDefaults() throws {
        let directory = try makeTemporaryDirectory()
        let settingsURL = directory.appendingPathComponent("settings.json")
        let legacyJSON = """
        {
          "sunshineBinaryPath": "/opt/homebrew/bin/sunshine"
        }
        """
        try legacyJSON.write(to: settingsURL, atomically: true, encoding: .utf8)

        let manager = FileSettingsManager(settingsURL: settingsURL)
        let settings = try manager.load()
        let defaults = MacStreamHostSettings.defaults()

        XCTAssertEqual(settings.sunshineBinaryPath, "/opt/homebrew/bin/sunshine")
        XCTAssertEqual(settings.configDirectoryPath, defaults.configDirectoryPath)
        XCTAssertEqual(settings.logDirectoryPath, defaults.logDirectoryPath)
        XCTAssertEqual(settings.hostPrivacyPolicy.mode, .secureOverlay)
    }

    func testLoadingSettingsWithoutPrivacyModePreservesLegacyAppOverlayDefault() throws {
        let directory = try makeTemporaryDirectory()
        let settingsURL = directory.appendingPathComponent("settings.json")
        let priorJSON = """
        {
          "configDirectoryPath": "/tmp/macstream-config",
          "logDirectoryPath": "/tmp/macstream-logs",
          "audioCaptureMode": "blackHole2ch",
          "hostPrivacyPolicy": {
            "offerLockOnSessionStart": true,
            "allowManualLock": true
          }
        }
        """
        try priorJSON.write(to: settingsURL, atomically: true, encoding: .utf8)

        let manager = FileSettingsManager(settingsURL: settingsURL)
        let settings = try manager.load()

        XCTAssertEqual(settings.hostPrivacyPolicy.mode, .appOverlay)
        XCTAssertTrue(settings.hostPrivacyPolicy.allowManualLock)
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
