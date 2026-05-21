// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class HealthCheckTests: XCTestCase {
    func testHealthCheckResultAggregatesFailures() {
        let result = HealthCheckResult(checks: [
            HealthCheck(id: .sunshine, title: "Sunshine", status: .pass, detail: "OK"),
            HealthCheck(id: .permissions, title: "Permissions", status: .fail, detail: "Missing")
        ])

        XCTAssertEqual(result.status, .failing)
        XCTAssertEqual(result.recommendedNextStep, "Missing")
    }

    func testHealthCheckResultAggregatesWarningsAsDegraded() {
        let result = HealthCheckResult(checks: [
            HealthCheck(id: .sunshine, title: "Sunshine", status: .pass, detail: "OK"),
            HealthCheck(id: .blackHole, title: "BlackHole", status: .warning, detail: "Optional fallback missing")
        ])

        XCTAssertEqual(result.status, .degraded)
        XCTAssertEqual(result.recommendedNextStep, "Optional fallback missing")
    }

    func testDefaultHealthCheckServiceProducesCoreChecks() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(permissionsStatus: MacOSPermissionsStatus(checks: [
                PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
                PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
                PermissionCheck(id: .localNetwork, status: .granted, detail: "OK"),
                PermissionCheck(id: .accessibility, status: .notDetermined, detail: "Optional")
            ])),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(result: NetworkDiagnosticResult(
                localAddresses: ["192.168.1.10"],
                portChecks: [
                    NetworkPortCheck(name: "Web UI", protocolKind: .tcp, port: 47990, status: .pass, detail: "Listening")
                ]
            )),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager()
        )

        let result = await service.runHealthCheck()

        XCTAssertTrue(result.checks.contains(where: { $0.id == .sunshine }))
        XCTAssertTrue(result.checks.contains(where: { $0.id == .sunshineRuntime }))
        XCTAssertTrue(result.checks.contains(where: { $0.id == .network }))
    }

    func testHealthCheckFailsWhenSunshineLogsScreenRecordingErrorAndIsNotRunning() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .stopped, webUIReachable: false)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager(entries: [
                LogEntry(subsystem: "Sunshine stdout", message: "Error: No screen capture permission!")
            ])
        )

        let result = await service.runHealthCheck()
        let screenCheck = result.checks.first { $0.id == .sunshineScreenRecording }

        XCTAssertEqual(screenCheck?.status, .fail)
        XCTAssertEqual(result.status, .failing)
    }

    func testHealthCheckFailsWhenSunshineCrashesWithDisplayNamesNilInsertion() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .stopped, webUIReachable: false)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager(entries: [
                LogEntry(
                    subsystem: "Sunshine stderr",
                    message: "*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object from objects[2]'"
                ),
                LogEntry(
                    subsystem: "Sunshine stderr",
                    message: "4   sunshine-2025.924.154138            0x00000001 +[AVVideo displayNames] + 252"
                )
            ])
        )

        let result = await service.runHealthCheck()
        let screenCheck = result.checks.first { $0.id == .sunshineScreenRecording }

        XCTAssertEqual(screenCheck?.status, .fail)
        XCTAssertTrue(screenCheck?.detail.contains("Gravação de Tela") == true)
    }

    func testHealthCheckSurfacesEncoderProbeFailureEvenWhenSunshineIsRunning() async {
        // macOS 14.5+/Sequoia: missing Screen Recording grant no longer crashes
        // Sunshine — it returns nil displays so the encoder probe fails while
        // the HTTP server stays alive. The user is stuck (Moonlight gets
        // "Failed to initialize video capture") but the engine reports
        // "running". The health banner must still fire.
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager(entries: [
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Sunshine version: 2026.508.45922 commit: deadbeef"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Trying encoder [videotoolbox]"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Encoder [videotoolbox] failed"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Encoder [software] failed"),
                LogEntry(subsystem: "Sunshine stdout", message: "Fatal: Unable to find display or encoder during startup.")
            ])
        )

        let result = await service.runHealthCheck()
        let screenCheck = result.checks.first { $0.id == .sunshineScreenRecording }

        XCTAssertEqual(screenCheck?.status, .fail)
        XCTAssertTrue(screenCheck?.detail.contains("Gravação de Tela") == true)
    }

    func testHealthCheckIgnoresStaleSunshineErrorsBeforeLatestStartup() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(permissionsStatus: MacOSPermissionsStatus(checks: [
                PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
                PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
                PermissionCheck(id: .localNetwork, status: .granted, detail: "OK")
            ])),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager(entries: [
                LogEntry(subsystem: "Sunshine stdout", message: "Error: No screen capture permission!"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Sunshine version: 2025.924.154138 commit: abc"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Found H.264 encoder: h264_videotoolbox [videotoolbox]"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Configuration UI available at [https://localhost:47990]")
            ])
        )

        let result = await service.runHealthCheck()
        let runtimeCheck = result.checks.first { $0.id == .sunshineRuntime }

        XCTAssertEqual(runtimeCheck?.status, .pass)
    }

    func testHealthCheckIgnoresStaleStderrCrashAfterSuccessfulStartup() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(permissionsStatus: MacOSPermissionsStatus(checks: [
                PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
                PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
                PermissionCheck(id: .localNetwork, status: .granted, detail: "OK")
            ])),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager(entries: [
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Sunshine version: 2026.516.143833 commit: abc"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Detected display: Built-in Retina Display (id: 1) connected: true"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Configuring selected display (1) to stream"),
                LogEntry(subsystem: "Sunshine stdout", message: "Info: Found H.264 encoder: h264_videotoolbox [videotoolbox]"),
                LogEntry(
                    subsystem: "Sunshine stderr",
                    message: "*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object from objects[2]'"
                ),
                LogEntry(
                    subsystem: "Sunshine stderr",
                    message: "4   Sunshine                            0x000000010268322c +[AVVideo displayNames] + 308"
                )
            ])
        )

        let result = await service.runHealthCheck()
        let runtimeCheck = result.checks.first { $0.id == .sunshineRuntime }
        let screenCheck = result.checks.first { $0.id == .sunshineScreenRecording }

        XCTAssertEqual(runtimeCheck?.status, .pass)
        XCTAssertNil(screenCheck)
    }

    func testHealthCheckDoesNotFailAudioWhenBlackHoleDriverIsInstalled() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(),
            audioDeviceManager: MockAudioDeviceManager(devices: [], routeStatus: .fail),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager()
        )

        let result = await service.runHealthCheck()
        let audioCheck = result.checks.first { $0.id == .audio }

        XCTAssertEqual(audioCheck?.status, .warning)
        XCTAssertNotEqual(result.status, .failing)
    }

    func testHealthCheckUsesRemoteWorkPowerStatusFromAgentReport() async {
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
            powerStatus: PowerAssertionStatus(isActive: true, assertionID: 99, detail: "Agent keep-awake active."),
            hostPrivacyStatus: .initial,
            nextStep: "Running."
        )

        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
            blackHoleManager: MockBlackHoleManager(status: .installed),
            permissionManager: MockPermissionManager(),
            audioDeviceManager: MockAudioDeviceManager(),
            networkDiagnosticsManager: MockNetworkDiagnosticsManager(),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            logManager: MockLogManager(),
            powerAssertionManager: MockPowerAssertionManager(),
            remoteWorkSessionManager: remoteWork
        )

        let result = await service.runHealthCheck()
        let powerCheck = result.checks.first { $0.id == .power }

        XCTAssertEqual(powerCheck?.status, .pass)
        XCTAssertEqual(powerCheck?.detail, "Agent keep-awake active.")
    }
}
