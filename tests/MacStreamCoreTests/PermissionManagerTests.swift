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
            settingsOpener: FakePermissionSettingsOpener()
        )

        let status = await manager.currentStatus()

        XCTAssertEqual(status.checks.map(\.id), MacPermission.allCases)
        XCTAssertEqual(status.checks.first(where: { $0.id == .screenRecording })?.status, .granted)
        XCTAssertEqual(status.checks.first(where: { $0.id == .microphone })?.status, .denied)
        XCTAssertEqual(status.aggregateStatus, .fail)
    }

    func testPermissionManagerWarnsForLocalNetworkValidationOnly() async {
        let manager = DefaultPermissionManager(
            statusProvider: FakePermissionStatusProvider(statuses: [
                .screenRecording: .granted,
                .microphone: .granted,
                .localNetwork: .requiresValidation,
                .accessibility: .requiresValidation
            ]),
            settingsOpener: FakePermissionSettingsOpener()
        )

        let status = await manager.currentStatus()

        XCTAssertFalse(status.criticalPermissionsSatisfied)
        XCTAssertEqual(status.aggregateStatus, .warning)
    }

    func testOpenSettingsDelegatesToOpener() async throws {
        let opener = FakePermissionSettingsOpener()
        let manager = DefaultPermissionManager(
            statusProvider: FakePermissionStatusProvider(statuses: [:]),
            settingsOpener: opener
        )

        try await manager.openSettings(for: .microphone)

        XCTAssertEqual(opener.openedPermissions, [.microphone])
    }

    func testSystemProviderTreatsLocalNetworkAsRequiresValidation() {
        let provider = SystemPermissionStatusProvider()

        XCTAssertEqual(provider.status(for: .localNetwork), .requiresValidation)
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
