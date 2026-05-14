// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class PermissionManagerTests: XCTestCase {
    func testPermissionManagerBuildsChecksForAllPermissions() async {
        let manager = DefaultPermissionManager(
            statusProvider: FakePermissionStatusProvider(statuses: [
                .screenRecording: .granted,
                .microphone: .denied,
                .localNetwork: .requiresValidation,
                .accessibility: .granted
            ]),
            prompter: FakePermissionPrompter(),
            settingsOpener: FakePermissionSettingsOpener()
        )

        let status = await manager.currentStatus()

        XCTAssertEqual(status.checks.map(\.id), MacPermission.allCases)
        XCTAssertEqual(status.checks.first(where: { $0.id == .screenRecording })?.status, .granted)
        XCTAssertEqual(status.checks.first(where: { $0.id == .microphone })?.status, .denied)
        XCTAssertEqual(status.aggregateStatus, .fail)
    }

    func testPermissionManagerPassesWhenOnlyNonCriticalLackValidation() async {
        // Local Network and Accessibility are non-critical for the MVP, so the
        // aggregate reports .pass when the critical permissions (Screen
        // Recording, Microphone) are granted — the optional checks live on
        // their own rows in the UI, but they don't degrade the headline.
        let manager = DefaultPermissionManager(
            statusProvider: FakePermissionStatusProvider(statuses: [
                .screenRecording: .granted,
                .microphone: .granted,
                .localNetwork: .requiresValidation,
                .accessibility: .requiresValidation
            ]),
            prompter: FakePermissionPrompter(),
            settingsOpener: FakePermissionSettingsOpener()
        )

        let status = await manager.currentStatus()

        XCTAssertTrue(status.criticalPermissionsSatisfied)
        XCTAssertEqual(status.aggregateStatus, .pass)
        XCTAssertEqual(status.runtimeGuidanceStatus, .warning, "runtimeGuidanceStatus still reflects every check, so the Setup screen can show per-item state.")
    }

    func testOpenSettingsDelegatesToOpener() async throws {
        let opener = FakePermissionSettingsOpener()
        let manager = DefaultPermissionManager(
            statusProvider: FakePermissionStatusProvider(statuses: [:]),
            prompter: FakePermissionPrompter(),
            settingsOpener: opener
        )

        try await manager.openSettings(for: .microphone)

        XCTAssertEqual(opener.openedPermissions, [.microphone])
    }

    func testSystemProviderTreatsLocalNetworkAsRequiresValidation() {
        let provider = SystemPermissionStatusProvider()

        XCTAssertEqual(provider.status(for: .localNetwork), .requiresValidation)
    }

    func testRequestPermissionsDelegatesToPrompterAndReportsResults() async {
        let prompter = FakePermissionPrompter(grantedPermissions: [.microphone])
        let manager = DefaultPermissionManager(
            statusProvider: FakePermissionStatusProvider(statuses: [
                .screenRecording: .requiresValidation,
                .microphone: .notDetermined
            ]),
            prompter: prompter,
            settingsOpener: FakePermissionSettingsOpener()
        )

        let results = await manager.requestPermissions([.screenRecording, .microphone])

        XCTAssertEqual(prompter.requestedPermissions, [.screenRecording, .microphone])
        XCTAssertEqual(results.map(\.id), [.screenRecording, .microphone])
        XCTAssertTrue(results.allSatisfy(\.promptAttempted))
    }
}

private struct FakePermissionStatusProvider: PermissionStatusProviding {
    let statuses: [MacPermission: PermissionStatus]

    func status(for permission: MacPermission) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }
}

private final class FakePermissionSettingsOpener: PermissionSettingsOpening {
    private(set) var openedPermissions: [MacPermission] = []

    func openSettings(for permission: MacPermission) throws {
        openedPermissions.append(permission)
    }
}

private final class FakePermissionPrompter: PermissionPrompting {
    private let grantedPermissions: Set<MacPermission>
    private(set) var requestedPermissions: [MacPermission] = []

    init(grantedPermissions: Set<MacPermission> = []) {
        self.grantedPermissions = grantedPermissions
    }

    func requestPermission(_ permission: MacPermission) async -> Bool {
        requestedPermissions.append(permission)
        return grantedPermissions.contains(permission)
    }
}
