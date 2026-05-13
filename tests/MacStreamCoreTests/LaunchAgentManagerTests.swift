// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

#if os(macOS)
import Darwin
#endif

final class LaunchAgentManagerTests: XCTestCase {
    func testRenderPlistProducesValidLaunchAgent() throws {
        let manager = makeManager()

        let contents = try manager.renderPlist()
        let validation = manager.validatePlist(contents)
        let plist = try XCTUnwrap(parsePlist(contents))

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(plist["Label"] as? String, "com.macstream.host.sunshine")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/local/bin/sunshine", "/tmp/sunshine.conf"])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
    }

    func testValidateRejectsMissingProgramArguments() {
        let manager = makeManager()
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
          <dict>
            <key>Label</key>
            <string>com.macstream.host.sunshine</string>
          </dict>
        </plist>
        """

        let validation = manager.validatePlist(contents)

        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("ProgramArguments must be an array of strings."))
    }

    func testStatusReportsInstalledForValidInstalledPlist() async throws {
        let directory = try makeTemporaryDirectory()
        let installedURL = directory.appendingPathComponent("com.macstream.host.sunshine.plist")
        let runner = RecordingLaunchctlRunner()
        runner.result = CommandResult(exitCode: 3)
        let manager = makeManager(installedPlistURL: installedURL, runner: runner)
        try manager.renderPlist().write(to: installedURL, atomically: true, encoding: .utf8)

        let status = await manager.status()

        XCTAssertEqual(status, .installed)
    }

    func testStatusReportsFailedForInvalidInstalledPlist() async throws {
        let directory = try makeTemporaryDirectory()
        let installedURL = directory.appendingPathComponent("com.macstream.host.sunshine.plist")
        let manager = makeManager(installedPlistURL: installedURL)
        try "not a plist".write(to: installedURL, atomically: true, encoding: .utf8)

        let status = await manager.status()

        XCTAssertEqual(status, .failed)
    }

    func testWriteDraftCreatesSkipsAndBacksUp() throws {
        let directory = try makeTemporaryDirectory()
        let draftURL = directory.appendingPathComponent("draft.plist")
        let manager = makeManager(
            draftPlistURL: draftURL,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )

        let created = try manager.writeDraftLaunchAgent(overwrite: false)
        let skipped = try manager.writeDraftLaunchAgent(overwrite: false)
        let replaced = try manager.writeDraftLaunchAgent(overwrite: true)

        XCTAssertEqual(created.action, .created)
        XCTAssertEqual(skipped.action, .skippedExisting)
        XCTAssertEqual(replaced.action, .backedUpAndReplaced)
        XCTAssertEqual(replaced.backupURL?.lastPathComponent, "draft.plist.backup-19700101-000000")
    }

    func testInstallWritesLaunchAgentWhenPreconditionsPass() async throws {
        let directory = try makeTemporaryDirectory()
        let binaryURL = directory.appendingPathComponent("sunshine")
        let configURL = directory.appendingPathComponent("sunshine.conf")
        let installedURL = directory.appendingPathComponent("installed.plist")
        FileManager.default.createFile(atPath: binaryURL.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        try "sunshine_name = MacStream Host".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = makeManager(
            sunshineBinaryPath: binaryURL.path,
            sunshineConfigPath: configURL.path,
            installedPlistURL: installedURL,
            logDirectoryPath: directory.appendingPathComponent("logs").path
        )

        try await manager.installLaunchAgent()

        XCTAssertTrue(FileManager.default.fileExists(atPath: installedURL.path))
    }

    func testInstallRejectsMissingBinary() async throws {
        let directory = try makeTemporaryDirectory()
        let configURL = directory.appendingPathComponent("sunshine.conf")
        try "sunshine_name = MacStream Host".write(to: configURL, atomically: true, encoding: .utf8)
        let manager = makeManager(
            sunshineBinaryPath: directory.appendingPathComponent("missing-sunshine").path,
            sunshineConfigPath: configURL.path,
            logDirectoryPath: directory.appendingPathComponent("logs").path
        )

        do {
            try await manager.installLaunchAgent()
            XCTFail("install should reject missing binary")
        } catch LaunchAgentManagerError.missingSunshineBinary {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadAndUnloadUseLaunchctlRunner() async throws {
        let directory = try makeTemporaryDirectory()
        let binaryURL = directory.appendingPathComponent("sunshine")
        let configURL = directory.appendingPathComponent("sunshine.conf")
        let installedURL = directory.appendingPathComponent("installed.plist")
        let runner = RecordingLaunchctlRunner()
        FileManager.default.createFile(atPath: binaryURL.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        try "sunshine_name = MacStream Host".write(to: configURL, atomically: true, encoding: .utf8)
        let manager = makeManager(
            sunshineBinaryPath: binaryURL.path,
            sunshineConfigPath: configURL.path,
            installedPlistURL: installedURL,
            logDirectoryPath: directory.appendingPathComponent("logs").path,
            runner: runner,
            uidProvider: { 501 }
        )

        try await manager.load()
        try await manager.unload()

        XCTAssertEqual(runner.calls.map(\.arguments.first), ["bootstrap", "bootout"])
        XCTAssertEqual(runner.calls.first?.arguments, ["bootstrap", "gui/501", installedURL.path])
    }

    func testLoadIsNoOpWhenLaunchAgentIsAlreadyLoaded() async throws {
        let directory = try makeTemporaryDirectory()
        let installedURL = directory.appendingPathComponent("installed.plist")
        let runner = RecordingLaunchctlRunner()
        runner.result = CommandResult(exitCode: 0)
        let manager = makeManager(installedPlistURL: installedURL, runner: runner)
        try manager.renderPlist().write(to: installedURL, atomically: true, encoding: .utf8)

        try await manager.load()

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.arguments.first, "print")
    }

    private func makeManager(
        sunshineBinaryPath: String = "/usr/local/bin/sunshine",
        sunshineConfigPath: String = "/tmp/sunshine.conf",
        installedPlistURL: URL? = nil,
        draftPlistURL: URL? = nil,
        logDirectoryPath: String = "/tmp/MacStreamHostLogs",
        dateProvider: @escaping () -> Date = Date.init,
        runner: CommandRunning = RecordingLaunchctlRunner(),
        uidProvider: @escaping () -> uid_t = { 501 }
    ) -> DefaultLaunchAgentManager {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostLaunchAgentDefaults", isDirectory: true)

        return DefaultLaunchAgentManager(
            definition: LaunchAgentDefinition(
                sunshineBinaryPath: sunshineBinaryPath,
                sunshineConfigPath: sunshineConfigPath,
                logDirectoryPath: logDirectoryPath
            ),
            installedPlistURL: installedPlistURL ?? tempDirectory.appendingPathComponent("installed.plist"),
            draftPlistURL: draftPlistURL ?? tempDirectory.appendingPathComponent("draft.plist"),
            dateProvider: dateProvider,
            runner: runner,
            uidProvider: uidProvider
        )
    }

    private func parsePlist(_ contents: String) throws -> [String: Any]? {
        let data = try XCTUnwrap(contents.data(using: .utf8))
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostLaunchAgentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private final class RecordingLaunchctlRunner: CommandRunning {
    struct Call {
        var executablePath: String
        var arguments: [String]
    }

    private(set) var calls: [Call] = []
    var result = CommandResult(exitCode: 0)

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        calls.append(Call(executablePath: executablePath, arguments: arguments))
        return result
    }
}
