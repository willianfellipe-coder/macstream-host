// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class RemoteWorkSessionManagerTests: XCTestCase {
    func testStartInstallsAgentWritesStartCommandAndLoadsAgent() async throws {
        let agent = MockAgentManager()
        let configuration = MockConfigurationManager()
        let manager = makeManager(agent: agent, configuration: configuration)

        let report = try await manager.start(overwriteConfig: true)

        XCTAssertTrue(agent.didInstall)
        XCTAssertTrue(agent.didLoad)
        XCTAssertEqual(agent.commands.last?.kind, .startRemoteWork)
        XCTAssertEqual(report.state, .starting)
    }

    func testStopWritesStopCommandWithoutStoppingExternalProcessDirectly() async throws {
        let agent = MockAgentManager()
        let manager = makeManager(agent: agent)

        let report = try await manager.stop()

        XCTAssertEqual(agent.commands.last?.kind, .stopRemoteWork)
        XCTAssertEqual(report.state, .stopping)
    }

    func testStatusBlocksWhenExternalVideoEngineIsRunning() async {
        let agent = MockAgentManager()
        let sunshine = MockSunshineManager(currentStatus: SunshineStatus(state: .running, ownedProcessID: nil))
        let manager = makeManager(agent: agent, sunshine: sunshine)

        let report = await manager.status()

        XCTAssertEqual(report.state, .blocked)
        XCTAssertTrue(report.blockers.contains(where: { $0.localizedCaseInsensitiveContains("externo") }))
    }

    func testStatusDoesNotBlockBeforeStartForAppPermissionWarnings() async {
        let permissions = MockPermissionManager(permissionsStatus: MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .requiresValidation, detail: "App warning"),
            PermissionCheck(id: .microphone, status: .denied, detail: "App warning"),
            PermissionCheck(id: .localNetwork, status: .requiresValidation, detail: "Practical validation"),
            PermissionCheck(id: .accessibility, status: .requiresValidation, detail: "Optional")
        ]))
        let manager = makeManager(permissions: permissions)

        let report = await manager.status()

        XCTAssertNotEqual(report.state, .blocked)
        XCTAssertTrue(report.blockers.isEmpty)
    }

    func testStatusSanitizesLegacyPermissionBlockerFromRunningAgentReport() async {
        let agent = MockAgentManager(status: MacStreamAgentStatus(
            launchAgentStatus: .loaded,
            isRunning: true,
            lastHeartbeat: Date(),
            detail: "Running"
        ))
        agent.lastReport = RemoteWorkSessionReport(
            state: .blocked,
            agentStatus: agent.currentStatus,
            engineStatus: ManagedEngineStatus(components: [
                ManagedEngineComponentStatus(id: .video, status: .pass, detail: "OK"),
                ManagedEngineComponentStatus(id: .audio, status: .pass, detail: "OK"),
                ManagedEngineComponentStatus(id: .network, status: .pass, detail: "OK")
            ]),
            powerStatus: .inactive,
            hostPrivacyStatus: .initial,
            blockers: ["Permissoes criticas do macOS ainda precisam ser concedidas."],
            nextStep: "Permissoes criticas do macOS ainda precisam ser concedidas."
        )
        let manager = makeManager(agent: agent)

        let report = await manager.status()

        XCTAssertEqual(report.state, .running)
        XCTAssertTrue(report.blockers.isEmpty)
    }

    @MainActor
    func testAppStateRemoteWorkActionsPublishReport() async {
        let remoteWork = MockRemoteWorkSessionManager()
        let appState = makeTestAppState(remoteWork: remoteWork)

        await appState.prepareRemoteWorkMode()

        XCTAssertTrue(remoteWork.prepared)
        XCTAssertEqual(appState.remoteWorkSession.state, .ready)
    }

    @MainActor
    func testAppStateRefreshUsesRemoteWorkPowerStatusFromAgentReport() async {
        let remoteWork = MockRemoteWorkSessionManager()
        remoteWork.report = RemoteWorkSessionReport(
            state: .running,
            agentStatus: MacStreamAgentStatus(
                launchAgentStatus: .loaded,
                isRunning: true,
                detail: "Running."
            ),
            engineStatus: ManagedEngineStatus(components: [
                ManagedEngineComponentStatus(id: .video, status: .pass, detail: "Video OK."),
                ManagedEngineComponentStatus(id: .audio, status: .pass, detail: "Audio OK."),
                ManagedEngineComponentStatus(id: .network, status: .pass, detail: "Network OK.")
            ]),
            powerStatus: PowerAssertionStatus(isActive: true, assertionID: 42, detail: "Agent keep-awake active."),
            hostPrivacyStatus: .initial,
            nextStep: "Running."
        )
        let appState = makeTestAppState(remoteWork: remoteWork)

        await appState.refresh()

        XCTAssertTrue(appState.powerAssertionStatus.isActive)
        XCTAssertEqual(appState.powerAssertionStatus.detail, "Agent keep-awake active.")
    }

    private func makeManager(
        agent: MockAgentManager = MockAgentManager(),
        configuration: ConfigurationManaging = MockConfigurationManager(),
        sunshine: SunshineManaging = MockSunshineManager(currentStatus: SunshineStatus(state: .stopped)),
        blackHole: BlackHoleManaging = MockBlackHoleManager(status: .installed),
        permissions: PermissionManaging = MockPermissionManager(permissionsStatus: MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
            PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
            PermissionCheck(id: .localNetwork, status: .granted, detail: "OK")
        ])),
        settings: MacStreamHostSettings = .defaults()
    ) -> DefaultRemoteWorkSessionManager {
        let audio = MockAudioDeviceManager()
        let network = MockNetworkDiagnosticsManager()
        let engine = DefaultManagedEngineManager(
            sunshineManager: sunshine,
            audioDeviceManager: audio,
            networkDiagnosticsManager: network
        )

        return DefaultRemoteWorkSessionManager(
            agentManager: agent,
            configurationManager: configuration,
            sunshineManager: sunshine,
            blackHoleManager: blackHole,
            permissionManager: permissions,
            managedEngineManager: engine,
            powerAssertionManager: MockPowerAssertionManager(),
            hostPrivacyManager: MockHostPrivacyManager(),
            settingsProvider: { settings }
        )
    }
}
