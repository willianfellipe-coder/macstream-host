// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

/// Codable migration tests for HostPrivacyPolicy. The secure-lock work
/// added three new fields (allow Touch ID, allow app pwd, max attempts)
/// — make sure JSON encoded by older builds (without those fields) still
/// decodes cleanly with the defaults.
final class HostPrivacyPolicyCodableTests: XCTestCase {
    func testDecodeOldJSONPreservesSecureDefaults() throws {
        // JSON shape from the pre-secure-lock build — only the legacy
        // three fields. Defaults must fill in for the new ones.
        let legacy = """
        {
            "offerLockOnSessionStart": true,
            "allowManualLock": true,
            "mode": "appOverlay"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HostPrivacyPolicy.self, from: legacy)

        XCTAssertEqual(decoded.mode, .appOverlay)
        XCTAssertTrue(decoded.offerLockOnSessionStart)
        XCTAssertTrue(decoded.allowManualLock)
        XCTAssertTrue(decoded.secureAllowMacOSAuthentication)
        XCTAssertTrue(decoded.secureAllowAppPassword)
        XCTAssertEqual(decoded.secureMaxUnlockAttempts, 5)
    }

    func testRoundTripPreservesSecureFields() throws {
        let policy = HostPrivacyPolicy(
            offerLockOnSessionStart: false,
            allowManualLock: true,
            mode: .secureOverlay,
            secureAllowMacOSAuthentication: false,
            secureAllowAppPassword: true,
            secureMaxUnlockAttempts: 8
        )

        let encoded = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(HostPrivacyPolicy.self, from: encoded)

        XCTAssertEqual(decoded, policy)
    }

    func testNewSecureOverlayModeRoundTrips() throws {
        let policy = HostPrivacyPolicy(mode: .secureOverlay)

        let encoded = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(HostPrivacyPolicy.self, from: encoded)

        XCTAssertEqual(decoded.mode, .secureOverlay)
    }

    func testDefaultsUseSecureOverlayForNewInstalls() {
        // New installs should use secure lock by default. Legacy JSON
        // with an explicit appOverlay value is still covered above.
        let defaults = HostPrivacyPolicy.defaults
        XCTAssertEqual(defaults.mode, .secureOverlay)
        XCTAssertTrue(defaults.secureAllowMacOSAuthentication)
        XCTAssertTrue(defaults.secureAllowAppPassword)
        XCTAssertEqual(defaults.secureMaxUnlockAttempts, 5)
    }
}
