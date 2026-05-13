// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum HostPrivacyError: Error, LocalizedError {
    case manualLockDisabled
    case lockCommandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .manualLockDisabled:
            return "Host lock is disabled by the current privacy policy."
        case .lockCommandFailed(let message):
            return "Failed to request host lock: \(message)"
        }
    }
}

public final class DefaultHostPrivacyManager: HostPrivacyManaging {
    private let runner: CommandRunning
    private var status: HostPrivacyStatus

    public init(
        policy: HostPrivacyPolicy = .defaults,
        runner: CommandRunning = ProcessCommandRunner()
    ) {
        self.runner = runner
        self.status = HostPrivacyStatus(policy: policy)
    }

    public func currentStatus() async -> HostPrivacyStatus {
        status
    }

    public func apply(policy: HostPrivacyPolicy) async {
        status.policy = policy
    }

    public func lockHost() async throws -> HostPrivacyStatus {
        guard status.policy.allowManualLock else {
            status = HostPrivacyStatus(
                policy: status.policy,
                lastAction: .lockFailed,
                detail: "Bloqueio manual do host esta desativado."
            )
            throw HostPrivacyError.manualLockDisabled
        }

        status = HostPrivacyStatus(
            policy: status.policy,
            lastAction: .lockRequested,
            detail: "Solicitando bloqueio da tela do host."
        )

        let result = await runner.run(
            executablePath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            arguments: ["-suspend"],
            timeout: 5
        )

        guard result.exitCode == 0 else {
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            status = HostPrivacyStatus(
                policy: status.policy,
                lastAction: .lockFailed,
                detail: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            throw HostPrivacyError.lockCommandFailed(status.detail)
        }

        status = HostPrivacyStatus(
            policy: status.policy,
            lastAction: .lockSucceeded,
            detail: "Bloqueio de tela solicitado pelo MacStream."
        )
        return status
    }
}
