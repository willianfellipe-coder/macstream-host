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

    func testHealthCheckFailsWhenSunshineLogsScreenRecordingError() async {
        let service = DefaultHealthCheckService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, webUIReachable: true)),
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
        let runtimeCheck = result.checks.first { $0.id == .sunshineRuntime }

        XCTAssertEqual(runtimeCheck?.status, .fail)
        XCTAssertEqual(result.status, .failing)
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
}
