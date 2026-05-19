// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Wraps `LAContext` so the secure lock overlay can offer Touch ID / macOS
/// user password as an alternative to the in-app password. Hidden behind a
/// protocol so tests can mock the result without touching real biometrics.
public protocol LocalAuthenticationServicing: Sendable {
    /// True when at least one form of device-owner auth is available
    /// (Touch ID enrolled, or the user has a password set). False on
    /// machines with no user password at all.
    func isAvailable() -> Bool

    /// Triggers the macOS auth dialog (Touch ID prompt with password
    /// fallback). Throws on system error; returns false when the user
    /// cancels or fails. Reason is shown to the user inside the dialog.
    func authenticate(reason: String) async throws -> Bool
}

public enum LocalAuthenticationError: Error, LocalizedError {
    case unavailable
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Touch ID / senha do macOS não está disponível neste Mac."
        case .cancelled:
            return "Autenticação cancelada."
        case .failed(let message):
            return "Falha na autenticação: \(message)"
        }
    }
}

#if canImport(LocalAuthentication)

/// Production implementation backed by `LAContext`. `LAContext` is not
/// Sendable, so we create a fresh context per call and bridge the
/// callback-based `evaluatePolicy` to async via a continuation. The
/// service itself is Sendable because it holds no mutable state.
public final class DefaultLocalAuthenticationService: LocalAuthenticationServicing, @unchecked Sendable {
    public init() {}

    public func isAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication = biometrics with password fallback.
        // Returns true on any Mac that has a user password set, even
        // without Touch ID enrollment.
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        return canEvaluate
    }

    public func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var preflightError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &preflightError) else {
            throw LocalAuthenticationError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluationError in
                if success {
                    continuation.resume(returning: true)
                    return
                }
                if let laError = evaluationError as? LAError {
                    switch laError.code {
                    case .userCancel, .systemCancel, .appCancel:
                        continuation.resume(returning: false)
                    default:
                        continuation.resume(throwing: LocalAuthenticationError.failed(laError.localizedDescription))
                    }
                } else if let evaluationError {
                    continuation.resume(throwing: LocalAuthenticationError.failed(evaluationError.localizedDescription))
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

#else

/// Non-macOS stub so the package still compiles on platforms without
/// LocalAuthentication. Always reports unavailable.
public final class DefaultLocalAuthenticationService: LocalAuthenticationServicing {
    public init() {}
    public func isAvailable() -> Bool { false }
    public func authenticate(reason: String) async throws -> Bool {
        throw LocalAuthenticationError.unavailable
    }
}

#endif

/// In-memory mock used by tests so XCTest doesn't trigger Touch ID
/// prompts or the macOS auth dialog.
public final class MockLocalAuthenticationService: LocalAuthenticationServicing, @unchecked Sendable {
    public var available: Bool
    public var nextResult: Result<Bool, LocalAuthenticationError>
    public private(set) var authenticateCallCount: Int = 0
    public private(set) var lastReason: String?

    public init(available: Bool = true, nextResult: Result<Bool, LocalAuthenticationError> = .success(true)) {
        self.available = available
        self.nextResult = nextResult
    }

    public func isAvailable() -> Bool { available }

    public func authenticate(reason: String) async throws -> Bool {
        authenticateCallCount += 1
        lastReason = reason
        switch nextResult {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
