// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SunshineIdentityStoreTests: XCTestCase {
    func testEnsureCreatesIdentityAndSunshineStateWhenMissing() throws {
        let root = try makeTemporaryDirectory()
        let identityURL = root.appendingPathComponent("identity.json")
        let stateURL = root.appendingPathComponent("sunshine_state.json")

        let store = DefaultSunshineIdentityStore(
            macStreamIdentityURL: identityURL,
            sunshineStateURL: stateURL,
            uuidProvider: { "stable-uuid-1" }
        )

        let identity = try store.ensureSunshineIdentity()

        XCTAssertEqual(identity.uniqueID, "stable-uuid-1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: identityURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))

        let stateData = try Data(contentsOf: stateURL)
        let parsed = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let inner = parsed?["root"] as? [String: Any]
        XCTAssertEqual(inner?["uniqueid"] as? String, "stable-uuid-1")
    }

    func testEnsureReusesIdentityAcrossCalls() throws {
        let root = try makeTemporaryDirectory()
        let identityURL = root.appendingPathComponent("identity.json")
        let stateURL = root.appendingPathComponent("sunshine_state.json")

        var generated = ["first", "second"]
        let store = DefaultSunshineIdentityStore(
            macStreamIdentityURL: identityURL,
            sunshineStateURL: stateURL,
            uuidProvider: { generated.removeFirst() }
        )

        let initial = try store.ensureSunshineIdentity()
        let repeated = try store.ensureSunshineIdentity()

        XCTAssertEqual(initial.uniqueID, "first")
        XCTAssertEqual(repeated.uniqueID, "first")
    }

    func testEnsurePreservesExistingSunshineStateFields() throws {
        let root = try makeTemporaryDirectory()
        let identityURL = root.appendingPathComponent("identity.json")
        let stateURL = root.appendingPathComponent("sunshine_state.json")

        let existing: [String: Any] = [
            "root": [
                "username": "alice",
                "password": "hash",
                "salt": "saltvalue",
                "named_certs": [["name": "ipad", "cert": "PEM"]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: stateURL)

        let store = DefaultSunshineIdentityStore(
            macStreamIdentityURL: identityURL,
            sunshineStateURL: stateURL,
            uuidProvider: { "new-uuid" }
        )

        _ = try store.ensureSunshineIdentity()

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        let inner = parsed?["root"] as? [String: Any]
        XCTAssertEqual(inner?["uniqueid"] as? String, "new-uuid")
        XCTAssertEqual(inner?["username"] as? String, "alice")
        XCTAssertEqual(inner?["password"] as? String, "hash")
        let certs = inner?["named_certs"] as? [[String: String]]
        XCTAssertEqual(certs?.first?["name"], "ipad")
    }

    func testResetClientPairingsClearsNamedCertsAndKeepsUniqueID() throws {
        let root = try makeTemporaryDirectory()
        let identityURL = root.appendingPathComponent("identity.json")
        let stateURL = root.appendingPathComponent("sunshine_state.json")

        let existing: [String: Any] = [
            "root": [
                "uniqueid": "stable",
                "named_certs": [["name": "stale-ipad", "cert": "PEM"]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: stateURL)

        let store = DefaultSunshineIdentityStore(
            macStreamIdentityURL: identityURL,
            sunshineStateURL: stateURL,
            uuidProvider: { "ignored" }
        )

        try store.resetClientPairings()

        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        let inner = parsed?["root"] as? [String: Any]
        XCTAssertEqual(inner?["uniqueid"] as? String, "stable")
        let certs = inner?["named_certs"] as? [[String: String]]
        XCTAssertEqual(certs?.count, 0)
    }

    func testResetClientPairingsIsNoOpWhenStateMissing() throws {
        let root = try makeTemporaryDirectory()
        let store = DefaultSunshineIdentityStore(
            macStreamIdentityURL: root.appendingPathComponent("identity.json"),
            sunshineStateURL: root.appendingPathComponent("sunshine_state.json")
        )
        XCTAssertNoThrow(try store.resetClientPairings())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostSunshineIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
