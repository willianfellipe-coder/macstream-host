// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Keeps Sunshine's `sunshine_state.json` populated with a stable `uniqueid`
/// so Moonlight clients always see the same host across MacStream Host
/// reinstalls. Without this, Sunshine generates a fresh UUID on every first
/// boot — the iPad then keeps the previous paired entry around (shown with
/// the offline triangle) AND lists the freshly-advertised one (shown with
/// the padlock), producing the duplicate "MacStream Host" entries the user
/// reported.
///
/// The identity itself is persisted under MacStream Host's Application
/// Support directory and mirrored into Sunshine's runtime directory on
/// every engine boot. Sunshine accepts a partial `state.json` containing
/// only `root.uniqueid`; it fills in the username/password/salt fields on
/// the first Web UI write, and preserves our `uniqueid` across saves.
public protocol SunshineIdentityStoring {
    func ensureSunshineIdentity() throws -> SunshineIdentity
    func resetClientPairings() throws
}

public struct SunshineIdentity: Equatable {
    public let uniqueID: String
    public let storedAt: URL

    public init(uniqueID: String, storedAt: URL) {
        self.uniqueID = uniqueID
        self.storedAt = storedAt
    }
}

public final class DefaultSunshineIdentityStore: SunshineIdentityStoring {
    public let macStreamIdentityURL: URL
    public let sunshineStateURL: URL

    private let fileManager: FileManager
    private let uuidProvider: () -> String

    public init(
        macStreamIdentityURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacStreamHost/identity.json"),
        sunshineStateURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sunshine/sunshine_state.json"),
        fileManager: FileManager = .default,
        uuidProvider: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.macStreamIdentityURL = macStreamIdentityURL
        self.sunshineStateURL = sunshineStateURL
        self.fileManager = fileManager
        self.uuidProvider = uuidProvider
    }

    @discardableResult
    public func ensureSunshineIdentity() throws -> SunshineIdentity {
        let identity = try loadOrGenerateIdentity()
        try mirrorIntoSunshineStateIfNeeded(uniqueID: identity)
        return SunshineIdentity(uniqueID: identity, storedAt: macStreamIdentityURL)
    }

    /// Drops the `named_certs` collection from Sunshine's state so the next
    /// pairing starts clean while keeping the host's `uniqueid` intact. Used
    /// by the "Resetar pareamentos" action when the iPad keeps offering a
    /// stale entry.
    public func resetClientPairings() throws {
        guard fileManager.fileExists(atPath: sunshineStateURL.path) else { return }
        let data = try Data(contentsOf: sunshineStateURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var innerRoot = root["root"] as? [String: Any] else {
            return
        }
        innerRoot["named_certs"] = [] as [Any]
        root["root"] = innerRoot
        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updated.write(to: sunshineStateURL, options: .atomic)
    }

    // MARK: Internal

    private func loadOrGenerateIdentity() throws -> String {
        if let existing = try loadStoredIdentity() {
            return existing
        }

        try fileManager.createDirectory(
            at: macStreamIdentityURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fresh = uuidProvider()
        let payload: [String: Any] = ["sunshineUniqueID": fresh]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: macStreamIdentityURL, options: .atomic)
        return fresh
    }

    private func loadStoredIdentity() throws -> String? {
        guard fileManager.fileExists(atPath: macStreamIdentityURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: macStreamIdentityURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return root?["sunshineUniqueID"] as? String
    }

    private func mirrorIntoSunshineStateIfNeeded(uniqueID: String) throws {
        try fileManager.createDirectory(
            at: sunshineStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any]
        var innerRoot: [String: Any]
        if fileManager.fileExists(atPath: sunshineStateURL.path),
           let data = try? Data(contentsOf: sunshineStateURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
            innerRoot = (parsed["root"] as? [String: Any]) ?? [:]
            if let current = innerRoot["uniqueid"] as? String, current == uniqueID {
                return
            }
        } else {
            root = [:]
            innerRoot = [:]
        }

        innerRoot["uniqueid"] = uniqueID
        root["root"] = innerRoot
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: sunshineStateURL, options: .atomic)
    }
}
