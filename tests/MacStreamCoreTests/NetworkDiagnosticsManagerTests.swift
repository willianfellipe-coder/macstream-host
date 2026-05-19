// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class NetworkDiagnosticsManagerTests: XCTestCase {
    func testNetworkDiagnosticsCombinesAddressesTailscaleAndPorts() async {
        // UDP video/audio/control ports bind on demand when a client starts a
        // session, so they're allowed to be `.warning` while the engine is
        // simply idle. As long as the essential TCP ports (HTTPS/HTTP/Web UI)
        // are listening and a local address exists, the network surface is
        // healthy.
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
        XCTAssertEqual(result.aggregateStatus, .pass)
    }

    func testNetworkDiagnosticsWarnsWhenEssentialTcpPortIsNotListening() async {
        let manager = DefaultNetworkDiagnosticsManager(
            addressProvider: FakeNetworkAddressProvider(addresses: ["192.168.1.20"]),
            portChecker: FakeNetworkPortChecker(statuses: [
                47984: .warning,
                47998: .pass
            ]),
            tailscaleProvider: FakeTailscaleAddressProvider(address: nil),
            sunshinePorts: [
                SunshinePort(name: "HTTPS/nvhttp", protocolKind: .tcp, port: 47984),
                SunshinePort(name: "Video", protocolKind: .udp, port: 47998)
            ]
        )

        let result = await manager.runDiagnostics()

        XCTAssertEqual(result.aggregateStatus, .warning)
    }

    // MARK: - TailscaleCLIAddressProvider

    /// macOS Tailscale.app installs a 68-byte shim at /usr/local/bin/tailscale
    /// that prints an error message to STDOUT (not stderr) AND returns
    /// exit code 0 when the GUI helper can't be reached. Before this
    /// fix, the provider would treat that string as the Tailscale IP
    /// AND every dashboard refresh would re-trigger the shim, causing
    /// the Tailscale GUI to spam a "CLI failed to start" banner.
    func testTailscaleProviderRejectsShimErrorOutput() async {
        let provider = TailscaleCLIAddressProvider(
            binaryResolver: FakeCommandBinaryResolver(path: "/usr/local/bin/tailscale"),
            runner: FakeNetworkCommandRunner(
                exitCode: 0,
                standardOutput: "The Tailscale CLI failed to start: The operation couldn't be completed. (Tailscale.CLIError error 1.)"
            )
        )

        let result = await provider.tailscaleAddress()

        XCTAssertNil(result, "Shim error text must NOT be returned as an IP")
    }

    func testTailscaleProviderAcceptsValidIPv4() async {
        let provider = TailscaleCLIAddressProvider(
            binaryResolver: FakeCommandBinaryResolver(path: "/usr/local/bin/tailscale"),
            runner: FakeNetworkCommandRunner(exitCode: 0, standardOutput: "100.64.0.10\n")
        )

        let result = await provider.tailscaleAddress()

        XCTAssertEqual(result, "100.64.0.10")
    }

    func testTailscaleProviderCachesAndDoesNotSpamCLI() async {
        let runner = CountingCommandRunner(
            inner: FakeNetworkCommandRunner(exitCode: 0, standardOutput: "100.64.0.42\n")
        )
        let provider = TailscaleCLIAddressProvider(
            binaryResolver: FakeCommandBinaryResolver(path: "/usr/local/bin/tailscale"),
            runner: runner,
            dateProvider: { Date(timeIntervalSince1970: 0) } // frozen clock
        )

        for _ in 0..<10 {
            _ = await provider.tailscaleAddress()
        }

        XCTAssertEqual(
            runner.callCount,
            1,
            "10 quick reads must hit the CLI once — otherwise the Tailscale GUI gets spammed"
        )
    }

    func testTailscaleProviderRefreshesAfterCacheExpiry() async {
        let runner = CountingCommandRunner(
            inner: FakeNetworkCommandRunner(exitCode: 0, standardOutput: "100.64.0.99\n")
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let provider = TailscaleCLIAddressProvider(
            binaryResolver: FakeCommandBinaryResolver(path: "/usr/local/bin/tailscale"),
            runner: runner,
            dateProvider: { currentTime }
        )

        _ = await provider.tailscaleAddress()
        currentTime = Date(timeIntervalSince1970: 120) // 2 minutes later, past the 60s TTL
        _ = await provider.tailscaleAddress()

        XCTAssertEqual(runner.callCount, 2, "Cache must expire after TTL")
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

    func testRunDiagnosticsMarksPrimaryInterfaceWhenRouteIsKnown() async {
        let provider = FakeNetworkAddressProvider(
            addresses: ["192.168.68.125", "192.168.68.145"],
            details: [
                NetworkLocalAddress(address: "192.168.68.125", interfaceName: "en0", friendlyName: "Wi-Fi"),
                NetworkLocalAddress(address: "192.168.68.145", interfaceName: "en16", friendlyName: "USB Ethernet")
            ],
            primary: "en0"
        )
        let manager = DefaultNetworkDiagnosticsManager(
            addressProvider: provider,
            portChecker: FakeNetworkPortChecker(statuses: [:]),
            tailscaleProvider: FakeTailscaleAddressProvider(address: nil),
            sunshinePorts: []
        )

        let result = await manager.runDiagnostics()

        XCTAssertEqual(result.localAddressDetails.count, 2)
        // Primary entry should be first in the sorted projection.
        XCTAssertEqual(result.localAddressDetails.first?.interfaceName, "en0")
        XCTAssertTrue(result.localAddressDetails.first?.isPrimary ?? false)
        XCTAssertFalse(result.localAddressDetails.last?.isPrimary ?? true)
        // And the legacy `.localAddresses` projection follows the same order.
        XCTAssertEqual(result.localAddresses, ["192.168.68.125", "192.168.68.145"])
    }

    func testOverlappingSubnetsAreDetectedFromAddressList() {
        let result = NetworkDiagnosticResult(
            localAddresses: ["192.168.68.125", "192.168.68.145"],
            portChecks: []
        )
        XCTAssertTrue(result.hasOverlappingSubnets)

        let clean = NetworkDiagnosticResult(
            localAddresses: ["192.168.68.125", "10.0.0.5"],
            portChecks: []
        )
        XCTAssertFalse(clean.hasOverlappingSubnets)
    }
}

private struct FakeNetworkAddressProvider: NetworkAddressProviding {
    let addresses: [String]
    var details: [NetworkLocalAddress] = []
    var primary: String? = nil

    func localAddresses() -> [String] {
        addresses
    }

    func localAddressDetails() -> [NetworkLocalAddress] {
        if details.isEmpty {
            return addresses.map { NetworkLocalAddress(address: $0, interfaceName: "") }
        }
        return details
    }

    func primaryInterfaceName() -> String? { primary }
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

/// Wraps an inner CommandRunning and counts invocations. Used to assert
/// that the Tailscale CLI cache is actually preventing repeat shim
/// invocations (otherwise the Tailscale GUI gets spammed with error
/// banners every 5 seconds).
private final class CountingCommandRunner: CommandRunning {
    private let inner: CommandRunning
    private(set) var callCount = 0
    private let lock = NSLock()

    init(inner: CommandRunning) {
        self.inner = inner
    }

    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        lock.lock()
        callCount += 1
        lock.unlock()
        return await inner.run(executablePath: executablePath, arguments: arguments, timeout: timeout)
    }
}
