// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class DependencyInstallerManagerTests: XCTestCase {
    func testManifestPinsMacOSSunshineAndBlackHoleArtifacts() {
        let sunshine = DependencyManifest.sunshineArtifact(architecture: "arm64")
        let blackHole = DependencyManifest.blackHoleArtifact()

        XCTAssertEqual(sunshine?.version, "v2026.508.45922")
        XCTAssertEqual(sunshine?.installerKind, .macOSDMGApplication)
        XCTAssertEqual(sunshine?.sha256, "8b9819f2dafcfa430b00cc08b07aa61d0ad138998d68f369bfc210e07db3eb4b")
        XCTAssertEqual(blackHole.version, "0.6.1")
        XCTAssertEqual(blackHole.installerKind, .macOSPKG)
        XCTAssertEqual(blackHole.sha256, "c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988")
    }

    func testInstallManagedSunshineDownloadsVerifiesMountsAndCopiesApp() async throws {
        let root = try makeTemporaryDirectory()
        let runner = FakeDependencyCommandRunner()
        let manager = DefaultDependencyInstallerManager(
            settings: testSettings(root: root),
            artifacts: [testArtifact(.sunshine, kind: .macOSDMGApplication)],
            commandRunner: runner,
            downloader: StaticDependencyDownloader(contents: Data("payload".utf8))
        )

        let result = try await manager.installManagedSunshine()

        XCTAssertEqual(result.dependencyID, .sunshine)
        XCTAssertEqual(result.installedBinaryPath?.hasSuffix("Sunshine.app/Contents/MacOS/sunshine"), true)
        XCTAssertEqual(result.requiresUserCompletion, false)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.installedBinaryPath ?? ""))
        XCTAssertTrue(runner.commands.contains { $0.executablePath == "/usr/bin/hdiutil" && $0.arguments.first == "attach" })
        XCTAssertTrue(runner.commands.contains { $0.executablePath == "/usr/bin/hdiutil" && $0.arguments.first == "detach" })
    }

    func testInstallRejectsChecksumMismatch() async throws {
        let root = try makeTemporaryDirectory()
        let manager = DefaultDependencyInstallerManager(
            settings: testSettings(root: root),
            artifacts: [testArtifact(.sunshine, kind: .macOSDMGApplication, sha256: String(repeating: "0", count: 64))],
            commandRunner: FakeDependencyCommandRunner(),
            downloader: StaticDependencyDownloader(contents: Data("payload".utf8))
        )

        do {
            _ = try await manager.installManagedSunshine()
            XCTFail("Expected checksum mismatch")
        } catch let error as DependencyInstallerError {
            guard case .checksumMismatch = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testBlackHoleInstallDownloadsVerifiesAndOpensPackage() async throws {
        let root = try makeTemporaryDirectory()
        let runner = FakeDependencyCommandRunner()
        let manager = DefaultDependencyInstallerManager(
            settings: testSettings(root: root),
            artifacts: [testArtifact(.blackHole, kind: .macOSPKG)],
            commandRunner: runner,
            downloader: StaticDependencyDownloader(contents: Data("payload".utf8))
        )

        let result = try await manager.downloadAndOpenBlackHoleInstaller()

        XCTAssertEqual(result.dependencyID, .blackHole)
        XCTAssertEqual(result.requiresUserCompletion, true)
        XCTAssertTrue(runner.commands.contains { $0.executablePath == "/usr/bin/open" && $0.arguments.first?.hasSuffix(".pkg") == true })
    }

    private func testSettings(root: URL) -> MacStreamHostSettings {
        MacStreamHostSettings(
            configDirectoryPath: root.appendingPathComponent("config").path,
            logDirectoryPath: root.appendingPathComponent("logs").path,
            audioCaptureMode: .blackHole2ch
        )
    }

    private func testArtifact(
        _ id: ManagedDependencyID,
        kind: DependencyInstallerKind,
        sha256: String = "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5"
    ) -> DependencyArtifact {
        DependencyArtifact(
            id: id,
            displayName: id.displayName,
            version: "test",
            downloadURL: URL(string: "https://example.com/\(id.rawValue)")!,
            sourceURL: URL(string: "https://example.com/source/\(id.rawValue)")!,
            sha256: sha256,
            fileName: kind == .macOSPKG ? "\(id.rawValue).pkg" : "\(id.rawValue).dmg",
            installerKind: kind,
            requiresAdministrator: kind == .macOSPKG,
            requiresReboot: kind == .macOSPKG,
            isPrerelease: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostDependencyInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private struct StaticDependencyDownloader: DependencyArtifactDownloading {
    var contents: Data

    func download(from url: URL, to destinationURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: destinationURL, options: .atomic)
    }
}

private final class FakeDependencyCommandRunner: CommandRunning {
    struct Command {
        var executablePath: String
        var arguments: [String]
    }

    private(set) var commands: [Command] = []

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        commands.append(Command(executablePath: executablePath, arguments: arguments))

        if executablePath == "/usr/bin/hdiutil", arguments.first == "attach" {
            let mountURL = URL(fileURLWithPath: arguments[3], isDirectory: true)
            let binaryURL = mountURL
                .appendingPathComponent("Sunshine.app/Contents/MacOS", isDirectory: true)
                .appendingPathComponent("sunshine")
            do {
                try FileManager.default.createDirectory(
                    at: binaryURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "test".write(to: binaryURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
            } catch {
                return CommandResult(exitCode: 1, standardError: error.localizedDescription)
            }
        }

        return CommandResult(exitCode: 0)
    }
}
