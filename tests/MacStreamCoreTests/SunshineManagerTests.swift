// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SunshineManagerTests: XCTestCase {
    func testStatusReportsRunningWhenBinaryAndProcessArePresent() async {
        let binaryURL = URL(fileURLWithPath: "/tmp/sunshine")
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: binaryURL),
            processInspector: FakeSunshineProcessInspector(isRunning: true),
            webUIProbe: FakeSunshineWebUIProbe(isReachable: true),
            configurationManager: try! Self.makeConfigurationManagerWithConfig(),
            ownershipStore: FakeSunshineOwnershipStore()
        )

        let status = await manager.status()

        XCTAssertEqual(status.state, SunshineServiceState.running)
        XCTAssertEqual(status.binaryPath, "/tmp/sunshine")
        XCTAssertTrue(status.webUIReachable)
        XCTAssertNil(status.version)
    }

    func testStatusReportsStoppedWhenBinaryExistsButProcessIsNotRunning() async {
        let probe = FakeSunshineWebUIProbe(isReachable: true)
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: false),
            webUIProbe: probe,
            configurationManager: try! Self.makeConfigurationManagerWithConfig(),
            ownershipStore: FakeSunshineOwnershipStore()
        )

        let status = await manager.status()

        XCTAssertEqual(status.state, SunshineServiceState.stopped)
        XCTAssertFalse(status.webUIReachable)
        XCTAssertEqual(probe.callCount, 0)
    }

    func testStatusReportsNotInstalledWhenBinaryIsMissing() async {
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: nil),
            processInspector: FakeSunshineProcessInspector(isRunning: false),
            webUIProbe: FakeSunshineWebUIProbe(isReachable: false),
            configurationManager: try! Self.makeConfigurationManagerWithConfig(),
            ownershipStore: FakeSunshineOwnershipStore()
        )

        let status = await manager.status()

        XCTAssertEqual(status.state, SunshineServiceState.notInstalled)
        XCTAssertNil(status.binaryPath)
    }

    func testResolverFindsExecutableFromPathEnvironment() throws {
        let directory = try makeTemporaryDirectory()
        let sunshineURL = directory.appendingPathComponent("sunshine")
        try "#!/bin/sh\nexit 0\n".write(to: sunshineURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sunshineURL.path)

        let resolver = DefaultSunshineBinaryResolver(
            candidatePaths: [],
            environment: ["PATH": directory.path],
            bundleResourceURL: nil
        )

        XCTAssertEqual(resolver.resolveBinary()?.path, sunshineURL.path)
    }

    func testResolverPrefersBundledSunshineOverPathAndCandidates() throws {
        let bundleResourceURL = try makeTemporaryDirectory()
        let bundledSunshine = bundleResourceURL.appendingPathComponent("sunshine/Sunshine.app/Contents/MacOS/Sunshine")
        try FileManager.default.createDirectory(at: bundledSunshine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeExecutableStub(at: bundledSunshine)

        let pathDirectory = try makeTemporaryDirectory()
        let pathSunshine = pathDirectory.appendingPathComponent("sunshine")
        try writeExecutableStub(at: pathSunshine)

        let candidateDirectory = try makeTemporaryDirectory()
        let candidateSunshine = candidateDirectory.appendingPathComponent("sunshine")
        try writeExecutableStub(at: candidateSunshine)

        let resolver = DefaultSunshineBinaryResolver(
            candidatePaths: [candidateSunshine.path],
            environment: ["PATH": pathDirectory.path],
            bundleResourceURL: bundleResourceURL
        )

        XCTAssertEqual(resolver.resolveBinary()?.path, bundledSunshine.path)
    }

    func testResolverFallsBackToCandidatesWhenBundleMissingAndBeforePath() throws {
        let bundleResourceURL = try makeTemporaryDirectory()

        let candidateDirectory = try makeTemporaryDirectory()
        let candidateSunshine = candidateDirectory.appendingPathComponent("sunshine")
        try writeExecutableStub(at: candidateSunshine)

        let pathDirectory = try makeTemporaryDirectory()
        let pathSunshine = pathDirectory.appendingPathComponent("sunshine")
        try writeExecutableStub(at: pathSunshine)

        let resolver = DefaultSunshineBinaryResolver(
            candidatePaths: [candidateSunshine.path],
            environment: ["PATH": pathDirectory.path],
            bundleResourceURL: bundleResourceURL
        )

        XCTAssertEqual(resolver.resolveBinary()?.path, candidateSunshine.path)
    }

    func testResolverAcceptsLegacyBundleBinLayout() throws {
        let bundleResourceURL = try makeTemporaryDirectory()
        let legacyBinary = bundleResourceURL.appendingPathComponent("sunshine/bin/sunshine")
        try FileManager.default.createDirectory(at: legacyBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeExecutableStub(at: legacyBinary)

        let resolver = DefaultSunshineBinaryResolver(
            candidatePaths: [],
            environment: [:],
            bundleResourceURL: bundleResourceURL
        )

        XCTAssertEqual(resolver.resolveBinary()?.path, legacyBinary.path)
    }

    private func writeExecutableStub(at url: URL) throws {
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testPgrepInspectorUsesExitCode() async {
        let runningInspector = PgrepSunshineProcessInspector(runner: FakeCommandRunner(exitCode: 0))
        let stoppedInspector = PgrepSunshineProcessInspector(runner: FakeCommandRunner(exitCode: 1))
        let running = await runningInspector.isSunshineRunning()
        let stopped = await stoppedInspector.isSunshineRunning()

        XCTAssertTrue(running)
        XCTAssertFalse(stopped)
    }

    func testStatusReportsOwnedProcessWhenOwnershipMatches() async throws {
        let ownedProcess = SunshineOwnedProcess(
            processID: 123,
            binaryPath: "/tmp/sunshine",
            configPath: "/tmp/sunshine.conf"
        )
        let store = FakeSunshineOwnershipStore(process: ownedProcess)
        let signaler = FakeSunshineProcessSignaler(isRunning: true, matchesOwnership: true)
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: false),
            webUIProbe: FakeSunshineWebUIProbe(isReachable: true),
            configurationManager: try Self.makeConfigurationManagerWithConfig(),
            ownershipStore: store,
            processSignaler: signaler
        )

        let status = await manager.status()

        XCTAssertEqual(status.state, SunshineServiceState.running)
        XCTAssertEqual(status.ownedProcessID, 123)
        XCTAssertEqual(status.configurationPath, "/tmp/sunshine.conf")
    }

    func testStartThrowsWhenConfigurationIsMissing() async throws {
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: false),
            configurationManager: Self.makeConfigurationManagerWithoutConfig(),
            ownershipStore: FakeSunshineOwnershipStore(),
            processLauncher: FakeSunshineProcessLauncher(),
            processSignaler: FakeSunshineProcessSignaler(isRunning: false, matchesOwnership: false)
        )

        do {
            try await manager.start()
            XCTFail("start should fail without config")
        } catch SunshineManagerError.missingConfiguration {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartRefusesExternalSunshineProcess() async throws {
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: true),
            configurationManager: try Self.makeConfigurationManagerWithConfig(),
            ownershipStore: FakeSunshineOwnershipStore(),
            processLauncher: FakeSunshineProcessLauncher(),
            processSignaler: FakeSunshineProcessSignaler(isRunning: false, matchesOwnership: false)
        )

        do {
            try await manager.start()
            XCTFail("start should refuse external Sunshine")
        } catch SunshineManagerError.externalProcessAlreadyRunning {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartLaunchesAndSavesOwnedProcess() async throws {
        let store = FakeSunshineOwnershipStore()
        let launcher = FakeSunshineProcessLauncher(processID: 456)
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: false),
            configurationManager: try Self.makeConfigurationManagerWithConfig(),
            ownershipStore: store,
            processLauncher: launcher,
            processSignaler: FakeSunshineProcessSignaler(isRunning: false, matchesOwnership: false),
            logDirectoryURL: try makeTemporaryDirectory()
        )

        try await manager.start()

        XCTAssertEqual(store.process?.processID, 456)
        XCTAssertEqual(launcher.launchCount, 1)
    }

    func testStopRefusesOwnershipMismatch() async throws {
        let store = FakeSunshineOwnershipStore(process: SunshineOwnedProcess(
            processID: 789,
            binaryPath: "/tmp/sunshine",
            configPath: "/tmp/sunshine.conf"
        ))
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: true),
            configurationManager: try Self.makeConfigurationManagerWithConfig(),
            ownershipStore: store,
            processSignaler: FakeSunshineProcessSignaler(isRunning: true, matchesOwnership: false)
        )

        do {
            try await manager.stop()
            XCTFail("stop should refuse mismatch")
        } catch SunshineManagerError.ownershipMismatch(789) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNotNil(store.process)
    }

    func testStopTerminatesOwnedProcessAndClearsStore() async throws {
        let store = FakeSunshineOwnershipStore(process: SunshineOwnedProcess(
            processID: 789,
            binaryPath: "/tmp/sunshine",
            configPath: "/tmp/sunshine.conf"
        ))
        let signaler = FakeSunshineProcessSignaler(isRunning: true, matchesOwnership: true)
        let manager = DefaultSunshineManager(
            binaryResolver: FakeSunshineBinaryResolver(binaryURL: URL(fileURLWithPath: "/tmp/sunshine")),
            processInspector: FakeSunshineProcessInspector(isRunning: true),
            configurationManager: try Self.makeConfigurationManagerWithConfig(),
            ownershipStore: store,
            processSignaler: signaler
        )

        try await manager.stop()

        XCTAssertNil(store.process)
        XCTAssertEqual(signaler.terminatedProcessIDs, [789])
    }

    private static func makeConfigurationManagerWithConfig() throws -> DefaultConfigurationManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostSunshineConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manager = DefaultConfigurationManager(configDirectory: directory)
        try "sunshine_name = MacStream Host\nstream_audio = enabled\nupnp = disabled\nport = 47989\n".write(
            to: manager.sunshineConfigURL,
            atomically: true,
            encoding: .utf8
        )
        return manager
    }

    private static func makeConfigurationManagerWithoutConfig() -> DefaultConfigurationManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostMissingSunshineConfigTests-\(UUID().uuidString)", isDirectory: true)
        return DefaultConfigurationManager(configDirectory: directory)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostSunshineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private struct FakeSunshineBinaryResolver: SunshineBinaryResolving {
    let binaryURL: URL?

    func resolveBinary() -> URL? {
        binaryURL
    }
}

private struct FakeSunshineProcessInspector: SunshineProcessInspecting {
    let isRunning: Bool

    func isSunshineRunning() async -> Bool {
        isRunning
    }
}

private final class FakeSunshineWebUIProbe: SunshineWebUIProbing {
    private let reachable: Bool
    private(set) var callCount = 0

    init(isReachable: Bool) {
        self.reachable = isReachable
    }

    func isReachable() async -> Bool {
        callCount += 1
        return reachable
    }
}

private struct FakeCommandRunner: CommandRunning {
    let exitCode: Int32

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        CommandResult(exitCode: exitCode)
    }
}

private final class FakeSunshineOwnershipStore: SunshineProcessOwnershipStoring {
    var process: SunshineOwnedProcess?

    init(process: SunshineOwnedProcess? = nil) {
        self.process = process
    }

    func load() throws -> SunshineOwnedProcess? {
        process
    }

    func save(_ process: SunshineOwnedProcess) throws {
        self.process = process
    }

    func clear() throws {
        process = nil
    }
}

private final class FakeSunshineProcessLauncher: SunshineProcessLaunching {
    private let processID: Int32
    private(set) var launchCount = 0

    init(processID: Int32 = 123) {
        self.processID = processID
    }

    func launch(binaryURL: URL, configURL: URL, logDirectoryURL: URL) throws -> SunshineOwnedProcess {
        launchCount += 1
        return SunshineOwnedProcess(
            processID: processID,
            binaryPath: binaryURL.path,
            configPath: configURL.path
        )
    }
}

private final class FakeSunshineProcessSignaler: SunshineProcessSignaling {
    private let running: Bool
    private let matches: Bool
    private(set) var terminatedProcessIDs: [Int32] = []

    init(isRunning: Bool, matchesOwnership: Bool) {
        self.running = isRunning
        self.matches = matchesOwnership
    }

    func isRunning(processID: Int32) async -> Bool {
        running
    }

    func matchesOwnership(_ process: SunshineOwnedProcess) async -> Bool {
        matches
    }

    func terminate(processID: Int32, timeout: TimeInterval) async -> Bool {
        terminatedProcessIDs.append(processID)
        return true
    }
}
