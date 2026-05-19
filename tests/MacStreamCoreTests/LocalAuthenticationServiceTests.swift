// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class LocalAuthenticationServiceTests: XCTestCase {
    func testMockReportsAvailabilityFlag() {
        let off = MockLocalAuthenticationService(available: false)
        XCTAssertFalse(off.isAvailable())

        let on = MockLocalAuthenticationService(available: true)
        XCTAssertTrue(on.isAvailable())
    }

    func testMockAuthenticateReturnsScriptedSuccess() async throws {
        let service = MockLocalAuthenticationService(available: true, nextResult: .success(true))

        let ok = try await service.authenticate(reason: "unit test")

        XCTAssertTrue(ok)
        XCTAssertEqual(service.authenticateCallCount, 1)
        XCTAssertEqual(service.lastReason, "unit test")
    }

    func testMockAuthenticateReturnsScriptedFailure() async throws {
        let service = MockLocalAuthenticationService(available: true, nextResult: .success(false))

        let ok = try await service.authenticate(reason: "cancelled by user")

        XCTAssertFalse(ok)
    }

    func testMockAuthenticateThrowsScriptedError() async {
        let service = MockLocalAuthenticationService(
            available: true,
            nextResult: .failure(.failed("biometry hardware off"))
        )

        do {
            _ = try await service.authenticate(reason: "should throw")
            XCTFail("Expected throw")
        } catch let error as LocalAuthenticationError {
            switch error {
            case .failed(let msg): XCTAssertEqual(msg, "biometry hardware off")
            default: XCTFail("Wrong case: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
