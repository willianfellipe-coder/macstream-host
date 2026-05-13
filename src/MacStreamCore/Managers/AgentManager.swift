// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public final class DefaultAgentExecutableResolver {
    private let fileManager: FileManager
    private let bundle: Bundle
    private let currentDirectoryPath: String

    public init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.currentDirectoryPath = currentDirectoryPath
    }

    public func resolveExecutable() -> URL? {
        let candidates = [
            bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("macstream-agent"),
            bundle.bundleURL.appendingPathComponent("Contents/MacOS/macstream-agent"),
            URL(fileURLWithPath: currentDirectoryPath).appendingPathComponent(".build/debug/macstream-agent"),
            URL(fileURLWithPath: currentDirectoryPath).appendingPathComponent(".build/release/macstream-agent")
        ].compactMap { $0 }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

public final class DefaultAgentManager: AgentManaging {
    public let statusURL: URL
    public let commandURL: URL

    private let launchAgentManager: LaunchAgentManaging
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let heartbeatTimeout: TimeInterval
    private let dateProvider: () -> Date

    public init(
        launchAgentManager: LaunchAgentManaging,
        statusURL: URL,
        commandURL: URL,
        fileManager: FileManager = .default,
        heartbeatTimeout: TimeInterval = 12,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.launchAgentManager = launchAgentManager
        self.statusURL = statusURL
        self.commandURL = commandURL
        self.fileManager = fileManager
        self.heartbeatTimeout = heartbeatTimeout
        self.dateProvider = dateProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func status() async -> MacStreamAgentStatus {
        let launchStatus = await launchAgentManager.status()
        let report = try? readLastReport()
        let heartbeat = report?.agentStatus.lastHeartbeat
        let isFresh = heartbeat.map { dateProvider().timeIntervalSince($0) <= heartbeatTimeout } ?? false

        return MacStreamAgentStatus(
            launchAgentStatus: launchStatus,
            isRunning: launchStatus == .loaded && isFresh,
            version: report?.agentStatus.version ?? AppBuildInfo.current.version,
            processID: report?.agentStatus.processID,
            lastHeartbeat: heartbeat,
            statePath: statusURL.path,
            detail: isFresh
                ? "Agente residente do MacStream ativo."
                : agentDetail(for: launchStatus)
        )
    }

    public func install() async throws {
        try? await launchAgentManager.unload()
        try await launchAgentManager.installLaunchAgent()
    }

    public func load() async throws {
        try await launchAgentManager.load()
    }

    public func unload() async throws {
        try await launchAgentManager.unload()
    }

    public func writeCommand(_ command: MacStreamAgentCommand) throws {
        try fileManager.createDirectory(at: commandURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(command)
        try data.write(to: commandURL, options: .atomic)
    }

    public func readLastReport() throws -> RemoteWorkSessionReport? {
        guard fileManager.fileExists(atPath: statusURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: statusURL)
        return try decoder.decode(RemoteWorkSessionReport.self, from: data)
    }

    public func writeReport(_ report: RemoteWorkSessionReport) throws {
        try fileManager.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(report)
        try data.write(to: statusURL, options: .atomic)
    }

    private func agentDetail(for status: LaunchAgentStatus) -> String {
        switch status {
        case .loaded:
            return "LaunchAgent carregado, aguardando heartbeat do agente."
        case .installed:
            return "Agente instalado, mas ainda nao carregado."
        case .notInstalled:
            return "Agente residente ainda nao instalado."
        case .failed:
            return "LaunchAgent do MacStream falhou na validacao."
        case .unknown:
            return "Status do agente residente desconhecido."
        }
    }
}
