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

    func testPermissionsAggregateIgnoresNonCriticalNoise() {
        // Local Network can never be confirmed from inside the app, and
        // Accessibility is optional — neither should drag the aggregate down
        // when the critical permissions (Screen Recording, Microphone) are
        // satisfied.
        let permissions = MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
            PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
            PermissionCheck(id: .localNetwork, status: .requiresValidation, detail: "Validar"),
            PermissionCheck(id: .accessibility, status: .denied, detail: "Optional")
        ])

        XCTAssertTrue(permissions.criticalPermissionsSatisfied)
        XCTAssertEqual(permissions.aggregateStatus, .pass)
    }

    func testPermissionsAggregateWarnsWhenCriticalMissing() {
        let permissions = MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .notDetermined, detail: "Pending"),
            PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
            PermissionCheck(id: .localNetwork, status: .granted, detail: "OK"),
            PermissionCheck(id: .accessibility, status: .granted, detail: "OK")
        ])

        XCTAssertEqual(permissions.aggregateStatus, .warning)
    }

    func testHostPrivacyDefaultStateIsPassNotWarning() {
        let idle = HostPrivacyStatus()
        XCTAssertEqual(idle.lastAction, .none)
        // Idle privacy is a normal default — the dashboard must not flag it
        // with a warning icon. lockSucceeded/lockFailed/lockRequested carry
        // their own meaningful statuses.
        XCTAssertEqual(idle.checkStatus, .pass)
        XCTAssertEqual(idle.displayLabel, "Pronta")
    }

    func testHostPrivacyLockedStateShowsPassWithFriendlyLabel() {
        let locked = HostPrivacyStatus(lastAction: .lockSucceeded, detail: "Tela ocultada.")
        XCTAssertEqual(locked.checkStatus, .pass)
        XCTAssertEqual(locked.displayLabel, "Tela bloqueada")
    }

    func testRemoteWorkModeIsStreamingActive() {
        // States where a Moonlight session is in flight — the privacy overlay
        // suppresses its floating unlock panel and the stream-end watcher is
        // running. Touching this set without thinking will regress the host
        // lock behaviour (black strip in the remote feed, intercepted
        // touchpad).
        XCTAssertTrue(RemoteWorkModeState.running.isStreamingActive)
        XCTAssertTrue(RemoteWorkModeState.degraded.isStreamingActive)
        XCTAssertTrue(RemoteWorkModeState.starting.isStreamingActive)

        // States where no client could possibly be attached — the unlock
        // panel is safe to show and there is nothing to watch for.
        XCTAssertFalse(RemoteWorkModeState.notReady.isStreamingActive)
        XCTAssertFalse(RemoteWorkModeState.ready.isStreamingActive)
        XCTAssertFalse(RemoteWorkModeState.stopping.isStreamingActive)
        XCTAssertFalse(RemoteWorkModeState.blocked.isStreamingActive)
    }
}
