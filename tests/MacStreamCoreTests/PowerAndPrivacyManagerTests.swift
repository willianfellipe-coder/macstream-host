// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class PowerAndPrivacyManagerTests: XCTestCase {
    func testDefaultPowerPolicyKeepsDisplayAwakeForStreaming() {
        XCTAssertTrue(PowerPolicy.defaults.preventSystemSleep)
        XCTAssertTrue(PowerPolicy.defaults.keepDisplayAwake)
    }

    func testRemoteStreamingPolicyUpgradesLegacySystemOnlyPolicy() {
        let legacy = PowerPolicy(preventSystemSleep: true, keepDisplayAwake: false)

        XCTAssertEqual(
            legacy.remoteStreamingPolicy,
            PowerPolicy(preventSystemSleep: true, keepDisplayAwake: true)
        )
    }

    func testPowerAssertionManagerAcquiresAndReleasesProviderAssertion() async throws {
        let provider = FakePowerAssertionProvider()
        let manager = DefaultPowerAssertionManager(provider: provider)

        let acquired = try await manager.acquire(policy: PowerPolicy(preventSystemSleep: true, keepDisplayAwake: true))
        let released = try await manager.release()

        XCTAssertTrue(acquired.isActive)
        XCTAssertEqual(acquired.assertionID, 77)
        XCTAssertEqual(provider.createdNames, ["MacStream Remote Work Mode", "MacStream Remote Work Mode"])
        XCTAssertEqual(provider.createdKeepDisplayAwake, [false, true])
        XCTAssertEqual(provider.releasedIDs, [77, 78])
        XCTAssertFalse(released.isActive)
    }

    func testHostPrivacyManagerUsesRunnerForManualLock() async throws {
        let runner = RecordingCommandRunner(result: CommandResult(exitCode: 0))
        let manager = DefaultHostPrivacyManager(runner: runner)

        let status = try await manager.lockHost()

        XCTAssertEqual(status.lastAction, .lockSucceeded)
        XCTAssertEqual(runner.calls.first?.arguments, ["-suspend"])
    }

    func testHostPrivacyManagerRejectsDisabledManualLock() async {
        let manager = DefaultHostPrivacyManager(policy: HostPrivacyPolicy(offerLockOnSessionStart: true, allowManualLock: false))

        do {
            _ = try await manager.lockHost()
            XCTFail("lock should fail when manual lock is disabled")
        } catch HostPrivacyError.manualLockDisabled {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class FakePowerAssertionProvider: PowerAssertionProviding {
    var createdNames: [String] = []
    var createdKeepDisplayAwake: [Bool] = []
    var releasedIDs: [UInt32] = []
    private var nextID: UInt32 = 77

    func createAssertion(named name: String, keepDisplayAwake: Bool) throws -> UInt32 {
        createdNames.append(name)
        createdKeepDisplayAwake.append(keepDisplayAwake)
        defer { nextID += 1 }
        return nextID
    }

    func releaseAssertion(id: UInt32) throws {
        releasedIDs.append(id)
    }
}

private final class RecordingCommandRunner: CommandRunning {
    struct Call {
        var executablePath: String
        var arguments: [String]
    }

    let result: CommandResult
    private(set) var calls: [Call] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        calls.append(Call(executablePath: executablePath, arguments: arguments))
        return result
    }
}
