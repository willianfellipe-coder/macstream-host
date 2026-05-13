// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class StatusRuleTests: XCTestCase {
    func testSunshineOperationalStates() {
        XCTAssertTrue(SunshineServiceState.running.isOperational)
        XCTAssertTrue(SunshineServiceState.degraded.isOperational)
        XCTAssertFalse(SunshineServiceState.notInstalled.isOperational)
        XCTAssertEqual(SunshineServiceState.failed.checkStatus, .fail)
    }

    func testBlackHoleUsability() {
        XCTAssertTrue(BlackHoleInstallationStatus.installed.isUsable)
        XCTAssertFalse(BlackHoleInstallationStatus.missing.isUsable)
        XCTAssertEqual(BlackHoleInstallationStatus.missing.checkStatus, .warning)
    }

    func testCriticalPermissionsAggregate() {
        let permissions = MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
            PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
            PermissionCheck(id: .localNetwork, status: .granted, detail: "OK"),
            PermissionCheck(id: .accessibility, status: .denied, detail: "Optional")
        ])

        XCTAssertTrue(permissions.criticalPermissionsSatisfied)
        XCTAssertEqual(permissions.aggregateStatus, .warning)
    }
}
