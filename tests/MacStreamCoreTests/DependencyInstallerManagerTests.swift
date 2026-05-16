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

    func testEmbeddedBlackHoleInstallerURLReturnsNilWhenPkgMissing() async throws {
        let root = try makeTemporaryDirectory()
        let manager = DefaultDependencyInstallerManager(
            settings: testSettings(root: root),
            artifacts: [testArtifact(.blackHole, kind: .macOSPKG)],
            commandRunner: FakeDependencyCommandRunner(),
            downloader: StaticDependencyDownloader(contents: Data()),
            embeddedBlackHoleLookup: { nil }
        )
        XCTAssertNil(manager.embeddedBlackHoleInstallerURL())
    }

    func testInstallEmbeddedBlackHoleShortCircuitsWhenDriverAlreadyPresent() async throws {
        let root = try makeTemporaryDirectory()
        // Pretend the driver is already installed by pointing the manager at
        // a path that exists. AuthorizationExecuteWithPrivileges should NOT
        // be called.
        let fakeDriverDir = root.appendingPathComponent("BlackHole2ch.driver", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeDriverDir, withIntermediateDirectories: true)
        let installer = SpyPrivilegedInstaller()

        let manager = DefaultDependencyInstallerManager(
            settings: testSettings(root: root),
            artifacts: [testArtifact(.blackHole, kind: .macOSPKG)],
            commandRunner: FakeDependencyCommandRunner(),
            downloader: StaticDependencyDownloader(contents: Data()),
            privilegedInstallerFactory: { installer },
            embeddedBlackHoleLookup: { nil },
            blackHoleDriverPath: fakeDriverDir.path
        )

        let result = try await manager.installEmbeddedBlackHole()

        XCTAssertEqual(result.requiresUserCompletion, false)
        XCTAssertEqual(result.installedPath, fakeDriverDir.path)
        XCTAssertEqual(installer.invocations.count, 0,
                       "Should not invoke installer when driver is already present")
    }

    func testInstallEmbeddedBlackHoleFallsBackToDownloadFlowWhenNoEmbeddedPkg() async throws {
        let root = try makeTemporaryDirectory()
        let runner = FakeDependencyCommandRunner()
        // Use the same "payload" content the default testArtifact sha256 was
        // computed against so the checksum check in downloadAndVerify passes.
        let manager = DefaultDependencyInstallerManager(
            settings: testSettings(root: root),
            artifacts: [testArtifact(.blackHole, kind: .macOSPKG)],
            commandRunner: runner,
            downloader: StaticDependencyDownloader(contents: Data("payload".utf8)),
            embeddedBlackHoleLookup: { nil },
            blackHoleDriverPath: root.appendingPathComponent("nonexistent.driver").path
        )

        let result = try await manager.installEmbeddedBlackHole()

        // The fallback path is downloadAndOpenBlackHoleInstaller which uses
        // /usr/bin/open on the downloaded .pkg.
        XCTAssertEqual(result.requiresUserCompletion, true)
        XCTAssertTrue(runner.commands.contains { $0.executablePath == "/usr/bin/open" })
    }
}

private final class SpyPrivilegedInstaller: PrivilegedInstaller {
    struct Invocation {
        let packageURL: URL
    }
    private(set) var invocations: [Invocation] = []

    override func installPackage(at packageURL: URL) throws -> String {
        invocations.append(Invocation(packageURL: packageURL))
        return "(mock) Successfully installed"
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
