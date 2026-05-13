// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import IOKit.pwr_mgt
#endif

public enum PowerAssertionError: Error, LocalizedError {
    case unsupportedPlatform
    case creationFailed(Int32)
    case releaseFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Power assertions are only available on macOS."
        case .creationFailed(let code):
            return "Failed to create macOS power assertion: \(code)."
        case .releaseFailed(let code):
            return "Failed to release macOS power assertion: \(code)."
        }
    }
}

public protocol PowerAssertionProviding {
    func createAssertion(named name: String, keepDisplayAwake: Bool) throws -> UInt32
    func releaseAssertion(id: UInt32) throws
}

public final class SystemPowerAssertionProvider: PowerAssertionProviding {
    public init() {}

    public func createAssertion(named name: String, keepDisplayAwake: Bool) throws -> UInt32 {
        #if os(macOS)
        var assertionID = IOPMAssertionID(0)
        let assertionType = keepDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypeNoIdleSleep
        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.creationFailed(result)
        }

        return assertionID
        #else
        throw PowerAssertionError.unsupportedPlatform
        #endif
    }

    public func releaseAssertion(id: UInt32) throws {
        #if os(macOS)
        let result = IOPMAssertionRelease(IOPMAssertionID(id))
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.releaseFailed(result)
        }
        #else
        throw PowerAssertionError.unsupportedPlatform
        #endif
    }
}

public final class DefaultPowerAssertionManager: PowerAssertionManaging {
    private let provider: PowerAssertionProviding
    private var activeAssertionID: UInt32?
    private var activePolicy: PowerPolicy

    public init(
        provider: PowerAssertionProviding = SystemPowerAssertionProvider(),
        initialPolicy: PowerPolicy = .defaults
    ) {
        self.provider = provider
        self.activePolicy = initialPolicy
    }

    public func currentStatus() async -> PowerAssertionStatus {
        guard let activeAssertionID else {
            return PowerAssertionStatus(
                isActive: false,
                policy: activePolicy,
                detail: "MacStream nao esta mantendo o Mac acordado agora."
            )
        }

        return PowerAssertionStatus(
            isActive: true,
            policy: activePolicy,
            assertionID: activeAssertionID,
            detail: activePolicy.keepDisplayAwake
                ? "MacStream esta impedindo sleep do sistema e do display."
                : "MacStream esta impedindo sleep do sistema durante o modo remoto."
        )
    }

    public func acquire(policy: PowerPolicy) async throws -> PowerAssertionStatus {
        activePolicy = policy

        if policy.preventSystemSleep == false && policy.keepDisplayAwake == false {
            return try await release()
        }

        if activeAssertionID == nil {
            activeAssertionID = try provider.createAssertion(
                named: "MacStream Remote Work Mode",
                keepDisplayAwake: policy.keepDisplayAwake
            )
        }

        return await currentStatus()
    }

    public func release() async throws -> PowerAssertionStatus {
        if let activeAssertionID {
            try provider.releaseAssertion(id: activeAssertionID)
            self.activeAssertionID = nil
        }

        return await currentStatus()
    }
}
