// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import Darwin
import SystemConfiguration
#endif

public protocol NetworkAddressProviding {
    func localAddresses() -> [String]
    /// Rich enumeration that annotates each address with its interface
    /// name + a user-facing label (e.g. "Wi-Fi"). Default implementation
    /// derives this from the plain `localAddresses()` so existing test
    /// doubles compile without change.
    func localAddressDetails() -> [NetworkLocalAddress]
    /// BSD name of the interface backing the IPv4 default route, when
    /// available. The manager uses this to mark one address as
    /// "recomendado" in the UI.
    func primaryInterfaceName() -> String?
}

public extension NetworkAddressProviding {
    func localAddressDetails() -> [NetworkLocalAddress] {
        localAddresses().map { NetworkLocalAddress(address: $0, interfaceName: "") }
    }
    func primaryInterfaceName() -> String? { nil }
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
        var details = addressProvider.localAddressDetails()
        if let primary = addressProvider.primaryInterfaceName() {
            details = details.map { entry in
                var copy = entry
                copy.isPrimary = (entry.interfaceName == primary)
                return copy
            }
        }
        // The plain string list stays as the legacy projection — same
        // ordering as `details` so downstream consumers that still treat
        // `.first` as "the address" pick the primary when available.
        details.sort { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary && !rhs.isPrimary }
            return lhs.address < rhs.address
        }
        let localAddresses = details.map(\.address)
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
            localAddressDetails: details,
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
        localAddressDetails().map(\.address)
    }

    public func localAddressDetails() -> [NetworkLocalAddress] {
        var entries: [NetworkLocalAddress] = []
        var seen: Set<String> = []
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfacePointer) == 0, let firstInterface = interfacePointer else {
            return []
        }

        defer { freeifaddrs(interfacePointer) }

        let friendlyNames = friendlyInterfaceNames()
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

            guard let ipAddress = stringAddress(from: address), shouldInclude(ipAddress) else {
                continue
            }

            let bsdName = String(cString: interface.ifa_name)
            let key = "\(bsdName)|\(ipAddress)"
            if seen.contains(key) { continue }
            seen.insert(key)

            entries.append(
                NetworkLocalAddress(
                    address: ipAddress,
                    interfaceName: bsdName,
                    friendlyName: friendlyNames[bsdName]
                )
            )
        }

        entries.sort { lhs, rhs in
            if lhs.interfaceName != rhs.interfaceName { return lhs.interfaceName < rhs.interfaceName }
            return lhs.address < rhs.address
        }
        return entries
    }

    public func primaryInterfaceName() -> String? {
        // Parse `route -n get default` — the canonical macOS way to find
        // the interface backing the default IPv4 route. Used by the
        // dashboard to mark one entry as "recomendado".
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// BSD name → user-facing label (e.g. `en0` → "Wi-Fi"). Reads the
    /// macOS Network preferences via SystemConfiguration so the labels
    /// match what the user sees in System Settings → Network. Returns
    /// an empty map if SC is unavailable (non-macOS, sandboxed builds).
    private func friendlyInterfaceNames() -> [String: String] {
        #if os(macOS)
        guard let prefs = SCPreferencesCreate(nil, "MacStreamHost" as CFString, nil) else { return [:] }
        guard let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return [:] }
        var map: [String: String] = [:]
        for service in services {
            guard let iface = SCNetworkServiceGetInterface(service),
                  let bsdName = SCNetworkInterfaceGetBSDName(iface) as String? else {
                continue
            }
            if let userVisible = SCNetworkServiceGetName(service) as String?, !userVisible.isEmpty {
                map[bsdName] = userVisible
            } else if let typeName = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                map[bsdName] = typeName
            }
        }
        return map
        #else
        return [:]
        #endif
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
    private let dateProvider: () -> Date

    /// Tailscale.app on macOS installs a 68-byte shim at
    /// /usr/local/bin/tailscale that invokes a helper inside the GUI
    /// bundle. The helper:
    ///   (1) frequently prints an error to stdout instead of stderr
    ///   ("The Tailscale CLI failed to start: The operation couldn't
    ///   be completed. (Tailscale.CLIError error 1.)") AND still exits
    ///   with code 0; AND
    ///   (2) raises a user-visible Tailscale.app banner every time
    ///   the shim fails.
    /// Without caching, the dashboard's `startLiveMonitors` 5-second
    /// refresh would spam the Tailscale GUI with that banner. We
    /// remember the last successful (or null) probe for `cacheTTL` so
    /// real Tailscale state still propagates while the GUI gets only
    /// one probe per minute.
    private static let cacheTTL: TimeInterval = 60

    private actor Cache {
        var lastValue: String?
        var lastQueriedAt: Date?

        func read(now: Date, ttl: TimeInterval) -> (cached: Bool, value: String?) {
            if let lastQueriedAt, now.timeIntervalSince(lastQueriedAt) < ttl {
                return (true, lastValue)
            }
            return (false, nil)
        }

        func write(value: String?, at: Date) {
            lastValue = value
            lastQueriedAt = at
        }
    }

    private let cache = Cache()

    public init(
        binaryResolver: CommandBinaryResolving = DefaultCommandBinaryResolver(),
        runner: CommandRunning = ProcessCommandRunner(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.binaryResolver = binaryResolver
        self.runner = runner
        self.dateProvider = dateProvider
    }

    public func tailscaleAddress() async -> String? {
        let now = dateProvider()
        let cached = await cache.read(now: now, ttl: Self.cacheTTL)
        if cached.cached {
            return cached.value
        }

        guard let tailscalePath = binaryResolver.resolve(command: "tailscale") else {
            await cache.write(value: nil, at: now)
            return nil
        }

        let result = await runner.run(executablePath: tailscalePath, arguments: ["ip", "-4"], timeout: 2)
        guard result.exitCode == 0 else {
            await cache.write(value: nil, at: now)
            return nil
        }

        let address = Self.firstIPv4(in: result.standardOutput)
        await cache.write(value: address, at: now)
        return address
    }

    /// Pulls the first IPv4-shaped token out of the command output. The
    /// macOS Tailscale.app shim swallows hard errors and writes the
    /// message ("The Tailscale CLI failed to start: ...") to stdout
    /// while returning exit 0 — without this filter we would surface
    /// that message as if it were the user's Tailscale address.
    static func firstIPv4(in output: String) -> String? {
        let pattern = #"^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for raw in output.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if regex?.firstMatch(in: trimmed, range: range) != nil {
                return trimmed
            }
        }
        return nil
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
