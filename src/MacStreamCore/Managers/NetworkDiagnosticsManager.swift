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
    /// IPv4 of the default gateway. Used by the peer-reachability
    /// detector to distinguish "isolated from peers" (gateway responds,
    /// peers don't) from "no link" (gateway silent too). Must be in
    /// the protocol body, not just the extension — otherwise concrete
    /// overrides are shadowed by the default implementation when
    /// dispatched through the protocol.
    func primaryGatewayIP() -> String?
}

public extension NetworkAddressProviding {
    func localAddressDetails() -> [NetworkLocalAddress] {
        localAddresses().map { NetworkLocalAddress(address: $0, interfaceName: "") }
    }
    func primaryInterfaceName() -> String? { nil }
    func primaryGatewayIP() -> String? { nil }
}

/// Reads the ARP table to determine which LAN peers the Mac has
/// successfully resolved at L2. A peer with a real MAC = the Mac sees
/// it; an "incomplete" entry = the Mac asked but got no reply. Used to
/// flag AP-isolation scenarios where only the gateway is reachable.
public protocol ARPInspecting {
    /// Returns the IP→MAC table observed locally. MAC == nil means the
    /// entry exists in the ARP cache but resolution failed
    /// (`incomplete` marker on macOS).
    func neighbors() -> [ARPNeighbor]
}

public struct ARPNeighbor: Equatable {
    public let address: String
    /// nil when the kernel reports `(incomplete)` — ARP request went
    /// out but no MAC came back.
    public let mac: String?

    public init(address: String, mac: String?) {
        self.address = address
        self.mac = mac
    }
}

/// Sends ICMP pings to confirm whether a given IP responds. Used to
/// probe the gateway as the discriminator between "isolated from peers"
/// and "no network at all".
public protocol HostReachabilityProbing {
    func ping(host: String, timeoutSeconds: Int) async -> Bool
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
    private let arpInspector: ARPInspecting
    private let reachabilityProbe: HostReachabilityProbing
    private let sunshinePorts: [SunshinePort]
    /// Two consecutive observations matching `.isolated` are required
    /// before surfacing the banner. Avoids flicker on a single bad ARP
    /// poll right after a router reboot or DHCP renew.
    private var lastObservedReachability: PeerReachability = .unknown

    public init(
        addressProvider: NetworkAddressProviding = POSIXNetworkAddressProvider(),
        portChecker: NetworkPortChecking = LsofNetworkPortChecker(),
        tailscaleProvider: TailscaleAddressProviding = TailscaleCLIAddressProvider(),
        arpInspector: ARPInspecting = POSIXARPInspector(),
        reachabilityProbe: HostReachabilityProbing = PingReachabilityProbe(),
        sunshinePorts: [SunshinePort] = SunshinePort.defaultPorts
    ) {
        self.addressProvider = addressProvider
        self.portChecker = portChecker
        self.tailscaleProvider = tailscaleProvider
        self.arpInspector = arpInspector
        self.reachabilityProbe = reachabilityProbe
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

        let peerReachability = await evaluatePeerReachability(localAddresses: localAddresses)

        return NetworkDiagnosticResult(
            localAddresses: localAddresses,
            localAddressDetails: details,
            tailscaleAddress: tailscaleAddress,
            portChecks: portChecks,
            firewallStatus: .unknown,
            peerReachability: peerReachability
        )
    }

    /// Decision tree for peer reachability:
    ///   1. List ARP neighbors. Exclude ourselves + the gateway.
    ///   2. If at least one neighbor has a real MAC → `.reachable`.
    ///   3. If all remaining entries are "incomplete" OR the list is
    ///      empty, ping the gateway:
    ///        - Gateway responds → `.isolated` (talking only to router)
    ///        - Gateway silent → `.noGateway` (link/DHCP problem)
    ///   4. Apply 2-sample debounce: a flag transition to `.isolated`
    ///      only sticks if the prior sample also said `.isolated`.
    private func evaluatePeerReachability(localAddresses: [String]) async -> PeerReachability {
        let gatewayIP = addressProvider.primaryGatewayIP()
        let ownAddresses = Set(localAddresses)
        let neighbors = arpInspector.neighbors().filter { neighbor in
            // Drop self + gateway from the peer candidate list — we
            // care only about whether OTHER devices respond.
            if ownAddresses.contains(neighbor.address) { return false }
            if let gw = gatewayIP, neighbor.address == gw { return false }
            return true
        }

        let hasResolvedPeer = neighbors.contains { $0.mac != nil }
        if hasResolvedPeer {
            lastObservedReachability = .reachable
            return .reachable
        }

        // No resolved peers. The gateway probe disambiguates "isolated
        // from peers" (talking only to the router) from "no link".
        let gatewayReachable: Bool
        if let gw = gatewayIP {
            gatewayReachable = await reachabilityProbe.ping(host: gw, timeoutSeconds: 1)
        } else {
            gatewayReachable = false
        }

        let candidate: PeerReachability = gatewayReachable ? .isolated : .noGateway

        // Debounce only `.isolated` — `.noGateway` is unambiguous and
        // surfaces immediately. For `.isolated`, require two consecutive
        // observations before flipping the banner so a single ARP miss
        // (e.g. right after DHCP renew) doesn't trigger a false alarm.
        if candidate == .isolated {
            let priorWasIsolated = (lastObservedReachability == .isolated)
            lastObservedReachability = .isolated
            return priorWasIsolated ? .isolated : .unknown
        }
        lastObservedReachability = candidate
        return candidate
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
        defaultRouteFields()["interface"]
    }

    public func primaryGatewayIP() -> String? {
        defaultRouteFields()["gateway"]
    }

    /// Parses `route -n get default` once and returns the
    /// key:value pairs we care about (interface + gateway).
    private func defaultRouteFields() -> [String: String] {
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return [:]
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for key in ["interface", "gateway"] {
                if trimmed.hasPrefix("\(key):") {
                    let parts = trimmed.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        fields[key] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return fields
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

/// Parses `arp -an` output to enumerate the IP→MAC table observed by
/// the macOS kernel. macOS prints lines like:
///   ? (192.168.68.1) at 24:2f:d0:71:dc:c0 on en0 ifscope [ethernet]
///   ? (192.168.68.106) at (incomplete) on en0 ifscope [ethernet]
/// We extract the IP and the MAC (or nil for "incomplete"). Read-only,
/// no side effects.
public final class POSIXARPInspector: ARPInspecting {
    public init() {}

    public func neighbors() -> [ARPNeighbor] {
        let task = Process()
        task.launchPath = "/usr/sbin/arp"
        task.arguments = ["-an"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return []
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [ARPNeighbor] = []
        for line in output.split(separator: "\n") {
            // Format: `? (IP) at MAC on iface ...` or `? (IP) at (incomplete) on iface`
            guard let ipStart = line.firstIndex(of: "("),
                  let ipEnd = line.firstIndex(of: ")"),
                  ipStart < ipEnd else {
                continue
            }
            let ip = String(line[line.index(after: ipStart)..<ipEnd])

            // Slice the "at <something>" portion.
            let afterIP = line[line.index(after: ipEnd)...]
            guard let atRange = afterIP.range(of: " at ") else { continue }
            let macPart = afterIP[atRange.upperBound...]
            let macToken = macPart.split(separator: " ").first.map(String.init) ?? ""

            let mac: String?
            if macToken == "(incomplete)" || macToken.isEmpty {
                mac = nil
            } else {
                mac = macToken
            }
            results.append(ARPNeighbor(address: ip, mac: mac))
        }
        return results
    }
}

/// Sends an ICMP echo request and reports success/failure. The macOS
/// `ping` binary is suid-root and works without sandbox tweaks. We
/// keep the timeout aggressive (1s default) so a 5-second dashboard
/// refresh cycle stays snappy when the gateway is down.
public final class PingReachabilityProbe: HostReachabilityProbing {
    public init() {}

    public func ping(host: String, timeoutSeconds: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/sbin/ping"
            task.arguments = ["-c", "1", "-W", "\(timeoutSeconds * 1000)", "-t", "\(timeoutSeconds)", host]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            task.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0)
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
