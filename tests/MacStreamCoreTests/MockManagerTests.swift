// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class MockManagerTests: XCTestCase {
    func testMockSunshineStartStopLifecycle() async throws {
        let manager = MockSunshineManager()

        try await manager.start()
        var status = await manager.status()
        XCTAssertEqual(status.state, .running)
        XCTAssertTrue(status.webUIReachable)

        try await manager.stop()
        status = await manager.status()
        XCTAssertEqual(status.state, .stopped)
        XCTAssertFalse(status.webUIReachable)
    }

    func testMockConfigurationManagerRendersAppsJSON() {
        let manager = MockConfigurationManager()
        let apps = manager.renderDefaultAppsJSON()

        XCTAssertTrue(apps.contains("\"name\": \"Desktop\""))
    }

    func testPairingGuideHasOrderedSteps() {
        let guide = StaticMoonlightPairingGuide()
        let steps = guide.pairingSteps()

        XCTAssertEqual(steps.first?.id, 1)
        XCTAssertGreaterThanOrEqual(steps.count, 4)
    }
}
