// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// Stores the MacStream Host app password in the macOS Keychain so it survives
/// app restarts and is encrypted at rest. The password is independent from the
/// user's macOS login password — it's specifically the one configured inside
/// Settings to gate the privacy-overlay unlock.
public protocol AppPasswordStoring {
    func isPasswordSet() -> Bool
    func setPassword(_ password: String) throws
    func clearPassword() throws
    func verify(_ candidate: String) -> Bool
}

public enum AppPasswordError: Error, LocalizedError {
    case empty
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "A senha não pode estar em branco."
        case .keychain(let status):
            return "Erro no Keychain (status \(status))."
        }
    }
}

public final class KeychainAppPasswordStore: AppPasswordStoring {
    private let service: String
    private let account: String

    public init(service: String = "org.macstream.host", account: String = "appPassword") {
        self.service = service
        self.account = account
    }

    public func isPasswordSet() -> Bool {
        readPasswordData() != nil
    }

    public func setPassword(_ password: String) throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AppPasswordError.empty }

        guard let data = trimmed.data(using: .utf8) else { throw AppPasswordError.empty }

        // Idempotent upsert: delete any existing item first so we don't fight
        // duplicate-entry errors on macOS.
        _ = SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppPasswordError.keychain(status) }
    }

    public func clearPassword() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppPasswordError.keychain(status)
        }
    }

    public func verify(_ candidate: String) -> Bool {
        guard let stored = readPasswordString() else { return false }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == stored
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readPasswordData() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private func readPasswordString() -> String? {
        guard let data = readPasswordData() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// In-memory store used in tests so XCTest doesn't touch the real Keychain.
public final class InMemoryAppPasswordStore: AppPasswordStoring {
    private var stored: String?

    public init(initial: String? = nil) {
        self.stored = initial
    }

    public func isPasswordSet() -> Bool { stored != nil }

    public func setPassword(_ password: String) throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw AppPasswordError.empty }
        stored = trimmed
    }

    public func clearPassword() throws {
        stored = nil
    }

    public func verify(_ candidate: String) -> Bool {
        guard let stored else { return false }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines) == stored
    }
}
