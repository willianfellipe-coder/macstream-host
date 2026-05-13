// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class NetworkDiagnosticsManagerTests: XCTestCase {
    func testNetworkDiagnosticsCombinesAddressesTailscaleAndPorts() async {
        let manager = DefaultNetworkDiagnosticsManager(
            addressProvider: FakeNetworkAddressProvider(addresses: ["192.168.1.20"]),
            portChecker: FakeNetworkPortChecker(statuses: [
                47990: .pass,
                47998: .warning
            ]),
            tailscaleProvider: FakeTailscaleAddressProvider(address: "100.64.0.10"),
            sunshinePorts: [
                SunshinePort(name: "Web UI", protocolKind: .tcp, port: 47990),
                SunshinePort(name: "Video", protocolKind: .udp, port: 47998)
            ]
        )

        let result = await manager.runDiagnostics()

        XCTAssertEqual(result.localAddresses, ["192.168.1.20"])
        XCTAssertEqual(result.tailscaleAddress, "100.64.0.10")
        XCTAssertEqual(result.portChecks.count, 2)
        XCTAssertEqual(result.portChecks.first?.status, .pass)
        XCTAssertEqual(result.aggregateStatus, .warning)
    }

    func testNetworkDiagnosticsWarnsWhenNoLocalAddressExists() async {
        let manager = DefaultNetworkDiagnosticsManager(
            addressProvider: FakeNetworkAddressProvider(addresses: []),
            portChecker: FakeNetworkPortChecker(statuses: [47990: .pass]),
            tailscaleProvider: FakeTailscaleAddressProvider(address: nil),
            sunshinePorts: [
                SunshinePort(name: "Web UI", protocolKind: .tcp, port: 47990)
            ]
        )

        let result = await manager.runDiagnostics()

        XCTAssertEqual(result.aggregateStatus, .warning)
        XCTAssertFalse(result.isReadyForLocalPairing)
    }

    func testLsofPortCheckerMapsExitCodes() async {
        let listeningChecker = LsofNetworkPortChecker(runner: FakeNetworkCommandRunner(exitCode: 0))
        let closedChecker = LsofNetworkPortChecker(runner: FakeNetworkCommandRunner(exitCode: 1))
        let unknownChecker = LsofNetworkPortChecker(runner: FakeNetworkCommandRunner(exitCode: 2))
        let port = SunshinePort(name: "Web UI", protocolKind: .tcp, port: 47990)
        let listeningStatus = await listeningChecker.status(for: port)
        let closedStatus = await closedChecker.status(for: port)
        let unknownStatus = await unknownChecker.status(for: port)

        XCTAssertEqual(listeningStatus, .pass)
        XCTAssertEqual(closedStatus, .warning)
        XCTAssertEqual(unknownStatus, .unknown)
    }

    func testTailscaleProviderParsesFirstAddress() async {
        let resolver = FakeCommandBinaryResolver(path: "/opt/homebrew/bin/tailscale")
        let runner = FakeNetworkCommandRunner(exitCode: 0, standardOutput: "100.64.0.10\n100.64.0.11\n")
        let provider = TailscaleCLIAddressProvider(binaryResolver: resolver, runner: runner)

        let address = await provider.tailscaleAddress()

        XCTAssertEqual(address, "100.64.0.10")
    }

    func testTailscaleProviderReturnsNilWhenBinaryIsMissing() async {
        let provider = TailscaleCLIAddressProvider(
            binaryResolver: FakeCommandBinaryResolver(path: nil),
            runner: FakeNetworkCommandRunner(exitCode: 0, standardOutput: "100.64.0.10\n")
        )

        let address = await provider.tailscaleAddress()

        XCTAssertNil(address)
    }
}

private struct FakeNetworkAddressProvider: NetworkAddressProviding {
    let addresses: [String]

    func localAddresses() -> [String] {
        addresses
    }
}

private struct FakeNetworkPortChecker: NetworkPortChecking {
    let statuses: [Int: CheckStatus]

    func status(for port: SunshinePort) async -> CheckStatus {
        statuses[port.port] ?? .unknown
    }
}

private struct FakeTailscaleAddressProvider: TailscaleAddressProviding {
    let address: String?

    func tailscaleAddress() async -> String? {
        address
    }
}

private struct FakeCommandBinaryResolver: CommandBinaryResolving {
    let path: String?

    func resolve(command: String) -> String? {
        path
    }
}

private struct FakeNetworkCommandRunner: CommandRunning {
    let exitCode: Int32
    var standardOutput = ""

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        CommandResult(exitCode: exitCode, standardOutput: standardOutput)
    }
}
