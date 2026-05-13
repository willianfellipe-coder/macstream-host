// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class AgentManagerTests: XCTestCase {
    func testAgentStatusUsesFreshHeartbeatReport() async throws {
        let directory = try makeTemporaryDirectory()
        let launchAgent = MockLaunchAgentManager(status: .loaded)
        let manager = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: directory.appendingPathComponent("status.json"),
            commandURL: directory.appendingPathComponent("command.json"),
            dateProvider: { Date(timeIntervalSince1970: 100) }
        )
        let report = RemoteWorkSessionReport(
            generatedAt: Date(timeIntervalSince1970: 100),
            state: .running,
            agentStatus: MacStreamAgentStatus(
                launchAgentStatus: .loaded,
                isRunning: true,
                version: "test",
                processID: 123,
                lastHeartbeat: Date(timeIntervalSince1970: 95),
                detail: "running"
            ),
            engineStatus: .initial,
            powerStatus: .inactive,
            hostPrivacyStatus: .initial,
            nextStep: "ok"
        )
        try manager.writeReport(report)

        let status = await manager.status()

        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.processID, 123)
        XCTAssertEqual(status.version, "test")
    }

    func testWriteCommandPersistsCommandJSON() throws {
        let directory = try makeTemporaryDirectory()
        let manager = DefaultAgentManager(
            launchAgentManager: MockLaunchAgentManager(),
            statusURL: directory.appendingPathComponent("status.json"),
            commandURL: directory.appendingPathComponent("command.json")
        )
        let command = MacStreamAgentCommand(kind: .startRemoteWork)

        try manager.writeCommand(command)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(
            MacStreamAgentCommand.self,
            from: Data(contentsOf: manager.commandURL)
        )

        XCTAssertEqual(loaded.kind, .startRemoteWork)
    }

    func testInstallUnloadsExistingAgentBeforeWritingLaunchAgent() async throws {
        let launchAgent = MockLaunchAgentManager(status: .loaded)
        let manager = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: URL(fileURLWithPath: "/tmp/status.json"),
            commandURL: URL(fileURLWithPath: "/tmp/command.json")
        )

        try await manager.install()
        let status = await launchAgent.status()

        XCTAssertEqual(status, .installed)
    }

    func testRecoverIfStaleBouncesAgentWhenLoadedButHeartbeatIsStale() async throws {
        let directory = try makeTemporaryDirectory()
        let launchAgent = MockLaunchAgentManager(status: .loaded)
        let manager = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: directory.appendingPathComponent("status.json"),
            commandURL: directory.appendingPathComponent("command.json"),
            heartbeatTimeout: 12,
            dateProvider: { Date(timeIntervalSince1970: 1000) }
        )
        let staleReport = RemoteWorkSessionReport(
            generatedAt: Date(timeIntervalSince1970: 800),
            state: .running,
            agentStatus: MacStreamAgentStatus(
                launchAgentStatus: .loaded,
                isRunning: true,
                version: "test",
                processID: 999,
                lastHeartbeat: Date(timeIntervalSince1970: 800),
                detail: "stale"
            ),
            engineStatus: .initial,
            powerStatus: .inactive,
            hostPrivacyStatus: .initial,
            nextStep: "ok"
        )
        try manager.writeReport(staleReport)

        let recovered = try await manager.recoverIfStale()

        XCTAssertTrue(recovered)
        XCTAssertEqual(launchAgent.lifecycleCalls, ["unload", "load"])
    }

    func testRecoverIfStaleSkipsWhenAgentIsAlreadyFresh() async throws {
        let directory = try makeTemporaryDirectory()
        let launchAgent = MockLaunchAgentManager(status: .loaded)
        let manager = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: directory.appendingPathComponent("status.json"),
            commandURL: directory.appendingPathComponent("command.json"),
            heartbeatTimeout: 12,
            dateProvider: { Date(timeIntervalSince1970: 1000) }
        )
        let freshReport = RemoteWorkSessionReport(
            generatedAt: Date(timeIntervalSince1970: 999),
            state: .running,
            agentStatus: MacStreamAgentStatus(
                launchAgentStatus: .loaded,
                isRunning: true,
                version: "test",
                processID: 1,
                lastHeartbeat: Date(timeIntervalSince1970: 999),
                detail: "fresh"
            ),
            engineStatus: .initial,
            powerStatus: .inactive,
            hostPrivacyStatus: .initial,
            nextStep: "ok"
        )
        try manager.writeReport(freshReport)

        let recovered = try await manager.recoverIfStale()

        XCTAssertFalse(recovered)
        XCTAssertTrue(launchAgent.lifecycleCalls.isEmpty)
    }

    func testRecoverIfStaleSkipsWhenLaunchAgentNotLoaded() async throws {
        let directory = try makeTemporaryDirectory()
        let launchAgent = MockLaunchAgentManager(status: .installed)
        let manager = DefaultAgentManager(
            launchAgentManager: launchAgent,
            statusURL: directory.appendingPathComponent("status.json"),
            commandURL: directory.appendingPathComponent("command.json")
        )

        let recovered = try await manager.recoverIfStale()

        XCTAssertFalse(recovered)
        XCTAssertTrue(launchAgent.lifecycleCalls.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostAgentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
