// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import Darwin
#endif

public protocol NetworkAddressProviding {
    func localAddresses() -> [String]
}

public protocol NetworkPortChecking {
    func status(for port: SunshinePort) async -> CheckStatus
}

public protocol TailscaleAddressProviding {
    func tailscaleAddress() async -> String?
}

public struct SunshinePort: Codable, Equatable, Hashable {
    public var name: String
    public var protocolKind: NetworkProtocolKind
    public var port: Int

    public init(name: String, protocolKind: NetworkProtocolKind, port: Int) {
        self.name = name
        self.protocolKind = protocolKind
        self.port = port
    }

    public static let defaultPorts: [SunshinePort] = [
        SunshinePort(name: "HTTPS/nvhttp", protocolKind: .tcp, port: 47984),
        SunshinePort(name: "HTTP", protocolKind: .tcp, port: 47989),
        SunshinePort(name: "Web UI", protocolKind: .tcp, port: 47990),
        SunshinePort(name: "RTSP", protocolKind: .tcp, port: 48010),
        SunshinePort(name: "Video", protocolKind: .udp, port: 47998),
        SunshinePort(name: "Control", protocolKind: .udp, port: 47999),
        SunshinePort(name: "Audio", protocolKind: .udp, port: 48000),
        SunshinePort(name: "Microphone", protocolKind: .udp, port: 48002)
    ]
}

public final class DefaultNetworkDiagnosticsManager: NetworkDiagnosticsManaging {
    private let addressProvider: NetworkAddressProviding
    private let portChecker: NetworkPortChecking
    private let tailscaleProvider: TailscaleAddressProviding
    private let sunshinePorts: [SunshinePort]

    public init(
        addressProvider: NetworkAddressProviding = POSIXNetworkAddressProvider(),
        portChecker: NetworkPortChecking = LsofNetworkPortChecker(),
        tailscaleProvider: TailscaleAddressProviding = TailscaleCLIAddressProvider(),
        sunshinePorts: [SunshinePort] = SunshinePort.defaultPorts
    ) {
        self.addressProvider = addressProvider
        self.portChecker = portChecker
        self.tailscaleProvider = tailscaleProvider
        self.sunshinePorts = sunshinePorts
    }

    public func runDiagnostics() async -> NetworkDiagnosticResult {
        let localAddresses = addressProvider.localAddresses()
        let tailscaleAddress = await tailscaleProvider.tailscaleAddress()
        var portChecks: [NetworkPortCheck] = []

        for port in sunshinePorts {
            let status = await portChecker.status(for: port)
            portChecks.append(
                NetworkPortCheck(
                    name: port.name,
                    protocolKind: port.protocolKind,
                    port: port.port,
                    status: status,
                    detail: detail(for: port, status: status)
                )
            )
        }

        return NetworkDiagnosticResult(
            localAddresses: localAddresses,
            tailscaleAddress: tailscaleAddress,
            portChecks: portChecks,
            firewallStatus: .unknown
        )
    }

    private func detail(for port: SunshinePort, status: CheckStatus) -> String {
        switch (port.protocolKind, status) {
        case (.tcp, .pass):
            return "Porta TCP ouvindo localmente."
        case (.tcp, .warning):
            return "Porta TCP não está ouvindo agora; isso é esperado se Sunshine estiver parado."
        case (.udp, .pass):
            return "Porta UDP em uso localmente."
        case (.udp, .warning):
            return "Porta UDP não apareceu em uso; validar durante streaming."
        case (_, .fail):
            return "Não foi possível verificar esta porta."
        case (_, .unknown):
            return "Estado da porta desconhecido."
        }
    }
}

public final class POSIXNetworkAddressProvider: NetworkAddressProviding {
    public init() {}

    public func localAddresses() -> [String] {
        var addresses: [String] = []
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfacePointer) == 0, let firstInterface = interfacePointer else {
            return []
        }

        defer { freeifaddrs(interfacePointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }

            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0,
                  let address = interface.ifa_addr else {
                continue
            }

            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                continue
            }

            if let ipAddress = stringAddress(from: address), shouldInclude(ipAddress) {
                addresses.append(ipAddress)
            }
        }

        return Array(Set(addresses)).sorted()
    }

    private func stringAddress(from address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )

        guard result == 0 else {
            return nil
        }

        return String(cString: host)
    }

    private func shouldInclude(_ address: String) -> Bool {
        if address.hasPrefix("127.") || address == "::1" {
            return false
        }

        if address.hasPrefix("169.254.") || address.lowercased().hasPrefix("fe80:") {
            return false
        }

        return true
    }
}

public final class LsofNetworkPortChecker: NetworkPortChecking {
    private let runner: CommandRunning
    private let lsofPath: String

    public init(runner: CommandRunning = ProcessCommandRunner(), lsofPath: String = "/usr/sbin/lsof") {
        self.runner = runner
        self.lsofPath = lsofPath
    }

    public func status(for port: SunshinePort) async -> CheckStatus {
        let arguments: [String]

        switch port.protocolKind {
        case .tcp:
            arguments = ["-nP", "-iTCP:\(port.port)", "-sTCP:LISTEN"]
        case .udp:
            arguments = ["-nP", "-iUDP:\(port.port)"]
        }

        let result = await runner.run(executablePath: lsofPath, arguments: arguments, timeout: 2)

        if result.exitCode == 0 {
            return .pass
        }

        if result.exitCode == 1 {
            return .warning
        }

        return .unknown
    }
}

public final class TailscaleCLIAddressProvider: TailscaleAddressProviding {
    private let binaryResolver: CommandBinaryResolving
    private let runner: CommandRunning

    public init(
        binaryResolver: CommandBinaryResolving = DefaultCommandBinaryResolver(),
        runner: CommandRunning = ProcessCommandRunner()
    ) {
        self.binaryResolver = binaryResolver
        self.runner = runner
    }

    public func tailscaleAddress() async -> String? {
        guard let tailscalePath = binaryResolver.resolve(command: "tailscale") else {
            return nil
        }

        let result = await runner.run(executablePath: tailscalePath, arguments: ["ip", "-4"], timeout: 2)
        guard result.exitCode == 0 else {
            return nil
        }

        return result.standardOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

public protocol CommandBinaryResolving {
    func resolve(command: String) -> String?
}

public final class DefaultCommandBinaryResolver: CommandBinaryResolving {
    private let environment: [String: String]
    private let fileManager: FileManager
    private let fallbackDirectories: [String]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        fallbackDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.fallbackDirectories = fallbackDirectories
    }

    public func resolve(command: String) -> String? {
        for directory in searchDirectories() {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(command).path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func searchDirectories() -> [String] {
        let pathDirectories = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        return Array(Set(pathDirectories + fallbackDirectories)).sorted()
    }
}
