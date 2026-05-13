// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SoftResetServiceTests: XCTestCase {
    func testSoftResetStopsOwnedProcessRemovesLaunchAgentAndArchivesConfig() async throws {
        let configuration = MockConfigurationManager()
        let service = DefaultSoftResetService(
            sunshineManager: MockSunshineManager(currentStatus: SunshineStatus(state: .running, ownedProcessID: 123)),
            launchAgentManager: MockLaunchAgentManager(status: .loaded),
            configurationManager: configuration
        )

        let result = try await service.reset()

        XCTAssertTrue(result.actions.contains("Stopped owned Sunshine process."))
        XCTAssertNotNil(result.archivedConfigDirectory)
        XCTAssertEqual(configuration.archivedConfigurationDirectory, result.archivedConfigDirectory)
    }
}
