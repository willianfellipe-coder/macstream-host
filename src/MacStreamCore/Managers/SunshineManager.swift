// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import AppKit
import Darwin
#endif

public enum SunshineManagerError: Error, LocalizedError {
    case notInstalled
    case missingConfiguration(String)
    case externalProcessAlreadyRunning
    case noOwnedProcess
    case ownershipMismatch(Int32)
    case launchFailed(String)
    case terminationFailed(Int32)
    case openWebUIFailed

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Sunshine binary was not found."
        case .missingConfiguration(let path):
            return "Sunshine config does not exist at \(path). Run configure before start."
        case .externalProcessAlreadyRunning:
            return "A Sunshine process is already running outside MacStream Host ownership. Refusing to control it."
        case .noOwnedProcess:
            return "No Sunshine process owned by MacStream Host is recorded."
        case .ownershipMismatch(let pid):
            return "Recorded PID \(pid) does not match MacStream Host ownership metadata."
        case .launchFailed(let message):
            return "Failed to launch Sunshine: \(message)"
        case .terminationFailed(let pid):
            return "Failed to stop owned Sunshine process \(pid)."
        case .openWebUIFailed:
            return "Failed to open the Sunshine Web UI."
        }
    }
}

public protocol SunshineBinaryResolving {
    func resolveBinary() -> URL?
}

public protocol SunshineProcessInspecting {
    func isSunshineRunning() async -> Bool
}

public protocol SunshineWebUIProbing {
    func isReachable() async -> Bool
}

public protocol URLOpening {
    func open(_ url: URL) -> Bool
}

public struct SunshineOwnedProcess: Codable, Equatable {
    public var processID: Int32
    public var binaryPath: String
    public var configPath: String
    public var startedAt: Date

    public init(processID: Int32, binaryPath: String, configPath: String, startedAt: Date = Date()) {
        self.processID = processID
        self.binaryPath = binaryPath
        self.configPath = configPath
        self.startedAt = startedAt
    }
}

public protocol SunshineProcessLaunching {
    func launch(binaryURL: URL, configURL: URL, logDirectoryURL: URL) throws -> SunshineOwnedProcess
}

public protocol SunshineProcessOwnershipStoring {
    func load() throws -> SunshineOwnedProcess?
    func save(_ process: SunshineOwnedProcess) throws
    func clear() throws
}

public protocol SunshineProcessSignaling {
    func isRunning(processID: Int32) async -> Bool
    func matchesOwnership(_ process: SunshineOwnedProcess) async -> Bool
    func terminate(processID: Int32, timeout: TimeInterval) async -> Bool
}

public final class DefaultSunshineManager: SunshineManaging {
    private let binaryResolver: SunshineBinaryResolving
    private let processInspector: SunshineProcessInspecting
    private let webUIProbe: SunshineWebUIProbing
    private let configurationManager: ConfigurationManaging
    private let ownershipStore: SunshineProcessOwnershipStoring
    private let processLauncher: SunshineProcessLaunching
    private let processSignaler: SunshineProcessSignaling
    private let urlOpener: URLOpening
    private let logDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        binaryResolver: SunshineBinaryResolving = DefaultSunshineBinaryResolver(),
        processInspector: SunshineProcessInspecting = PgrepSunshineProcessInspector(),
        webUIProbe: SunshineWebUIProbing = LocalSunshineWebUIProbe(),
        configurationManager: ConfigurationManaging = DefaultConfigurationManager(),
        ownershipStore: SunshineProcessOwnershipStoring = FileSunshineProcessOwnershipStore(),
        processLauncher: SunshineProcessLaunching = ProcessSunshineLauncher(),
        processSignaler: SunshineProcessSignaling = SystemSunshineProcessSignaler(),
        urlOpener: URLOpening = SystemURLOpener(),
        logDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacStreamHost"),
        fileManager: FileManager = .default
    ) {
        self.binaryResolver = binaryResolver
        self.processInspector = processInspector
        self.webUIProbe = webUIProbe
        self.configurationManager = configurationManager
        self.ownershipStore = ownershipStore
        self.processLauncher = processLauncher
        self.processSignaler = processSignaler
        self.urlOpener = urlOpener
        self.logDirectoryURL = logDirectoryURL
        self.fileManager = fileManager
    }

    public func isInstalled() async -> Bool {
        binaryResolver.resolveBinary() != nil
    }

    public func status() async -> SunshineStatus {
        let binaryURL = binaryResolver.resolveBinary()
        if let ownedProcess = try? ownershipStore.load(),
           await processSignaler.isRunning(processID: ownedProcess.processID),
           await processSignaler.matchesOwnership(ownedProcess) {
            let isWebUIReachable = await webUIProbe.isReachable()
            return SunshineStatus(
                state: .running,
                version: nil,
                webUIReachable: isWebUIReachable,
                configurationPath: ownedProcess.configPath,
                binaryPath: ownedProcess.binaryPath,
                ownedProcessID: ownedProcess.processID
            )
        }

        let isRunning = await processInspector.isSunshineRunning()
        let isWebUIReachable = isRunning ? await webUIProbe.isReachable() : false

        if binaryURL == nil {
            return SunshineStatus(
                state: .notInstalled,
                webUIReachable: isWebUIReachable,
                binaryPath: nil
            )
        }

        return SunshineStatus(
            state: isRunning ? .running : .stopped,
            version: nil,
            webUIReachable: isWebUIReachable,
            configurationPath: configurationManager.sunshineConfigURL.path,
            binaryPath: binaryURL?.path
        )
    }

    public func start() async throws {
        guard let binaryURL = binaryResolver.resolveBinary() else {
            throw SunshineManagerError.notInstalled
        }

        guard fileManager.fileExists(atPath: configurationManager.sunshineConfigURL.path) else {
            throw SunshineManagerError.missingConfiguration(configurationManager.sunshineConfigURL.path)
        }

        if let ownedProcess = try ownershipStore.load() {
            if await processSignaler.isRunning(processID: ownedProcess.processID),
               await processSignaler.matchesOwnership(ownedProcess) {
                return
            }

            try ownershipStore.clear()
        }

        guard await processInspector.isSunshineRunning() == false else {
            throw SunshineManagerError.externalProcessAlreadyRunning
        }

        do {
            try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
            let process = try processLauncher.launch(
                binaryURL: binaryURL,
                configURL: configurationManager.sunshineConfigURL,
                logDirectoryURL: logDirectoryURL
            )
            try ownershipStore.save(process)
        } catch let error as SunshineManagerError {
            throw error
        } catch {
            throw SunshineManagerError.launchFailed(error.localizedDescription)
        }
    }

    public func stop() async throws {
        guard let ownedProcess = try ownershipStore.load() else {
            throw SunshineManagerError.noOwnedProcess
        }

        guard await processSignaler.isRunning(processID: ownedProcess.processID) else {
            try ownershipStore.clear()
            return
        }

        guard await processSignaler.matchesOwnership(ownedProcess) else {
            throw SunshineManagerError.ownershipMismatch(ownedProcess.processID)
        }

        guard await processSignaler.terminate(processID: ownedProcess.processID, timeout: 5) else {
            throw SunshineManagerError.terminationFailed(ownedProcess.processID)
        }

        try ownershipStore.clear()
    }

    public func restart() async throws {
        do {
            try await stop()
        } catch SunshineManagerError.noOwnedProcess {
            // Starting fresh is safe when there is no owned process.
        }

        try await start()
    }

    public func openWebUI() async throws {
        guard urlOpener.open(URL(string: "https://localhost:47990")!) else {
            throw SunshineManagerError.openWebUIFailed
        }
    }
}

public final class SystemURLOpener: URLOpening {
    public init() {}

    public func open(_ url: URL) -> Bool {
        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }
}

public final class ProcessSunshineLauncher: SunshineProcessLaunching {
    private let dateProvider: () -> Date
    private let fileManager: FileManager

    public init(dateProvider: @escaping () -> Date = Date.init, fileManager: FileManager = .default) {
        self.dateProvider = dateProvider
        self.fileManager = fileManager
    }

    public func launch(binaryURL: URL, configURL: URL, logDirectoryURL: URL) throws -> SunshineOwnedProcess {
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        try? DefaultLogManager(logDirectoryURL: logDirectoryURL, fileManager: fileManager).rotateLogs(maxBytes: 5 * 1024 * 1024, backupCount: 3)

        let stdoutURL = logDirectoryURL.appendingPathComponent("sunshine.out.log")
        let stderrURL = logDirectoryURL.appendingPathComponent("sunshine.err.log")
        ensureFileExists(stdoutURL)
        ensureFileExists(stderrURL)

        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        _ = try? stdout.seekToEnd()
        _ = try? stderr.seekToEnd()
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [configURL.path]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        return SunshineOwnedProcess(
            processID: process.processIdentifier,
            binaryPath: binaryURL.path,
            configPath: configURL.path,
            startedAt: dateProvider()
        )
    }

    private func ensureFileExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
    }
}

public final class FileSunshineProcessOwnershipStore: SunshineProcessOwnershipStoring {
    private let metadataURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        metadataURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacStreamHost/run/sunshine-owned-process.json"),
        fileManager: FileManager = .default
    ) {
        self.metadataURL = metadataURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> SunshineOwnedProcess? {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: metadataURL)
        return try decoder.decode(SunshineOwnedProcess.self, from: data)
    }

    public func save(_ process: SunshineOwnedProcess) throws {
        let directory = metadataURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(process)
        try data.write(to: metadataURL, options: .atomic)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return
        }

        try fileManager.removeItem(at: metadataURL)
    }
}

public final class SystemSunshineProcessSignaler: SunshineProcessSignaling {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func isRunning(processID: Int32) async -> Bool {
        #if os(macOS)
        if kill(processID, 0) == 0 {
            return true
        }
        return errno == EPERM
        #else
        return false
        #endif
    }

    public func matchesOwnership(_ process: SunshineOwnedProcess) async -> Bool {
        let result = await runner.run(
            executablePath: "/bin/ps",
            arguments: ["-p", "\(process.processID)", "-o", "command="],
            timeout: 2
        )

        guard result.exitCode == 0 else {
            return false
        }

        let command = result.standardOutput
        return command.contains(process.configPath)
            && (command.contains(process.binaryPath) || command.contains("sunshine"))
    }

    public func terminate(processID: Int32, timeout: TimeInterval) async -> Bool {
        #if os(macOS)
        guard kill(processID, SIGTERM) == 0 else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !(await isRunning(processID: processID)) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return !(await isRunning(processID: processID))
        #else
        return false
        #endif
    }
}

public final class DefaultSunshineBinaryResolver: SunshineBinaryResolving {
    private let candidatePaths: [String]
    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        candidatePaths: [String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.candidatePaths = candidatePaths ?? Self.defaultCandidatePaths()
        self.environment = environment
        self.fileManager = fileManager
    }

    public func resolveBinary() -> URL? {
        for path in pathsFromEnvironment() + candidatePaths {
            let expandedPath = (path as NSString).expandingTildeInPath

            if fileManager.isExecutableFile(atPath: expandedPath) {
                return URL(fileURLWithPath: expandedPath)
            }
        }

        return nil
    }

    private func pathsFromEnvironment() -> [String] {
        guard let path = environment["PATH"] else {
            return []
        }

        return path
            .split(separator: ":")
            .map { String($0) }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("sunshine").path }
    }

    private static func defaultCandidatePaths() -> [String] {
        var paths = [
            "/opt/homebrew/bin/sunshine",
            "/usr/local/bin/sunshine",
            "/Applications/Sunshine.app/Contents/MacOS/sunshine",
            "~/Applications/Sunshine.app/Contents/MacOS/sunshine",
            "/Applications/MacStream Host.app/Contents/Resources/sunshine/bin/sunshine"
        ]

        if let resourcePath = Bundle.main.resourceURL?
            .appendingPathComponent("sunshine/bin/sunshine")
            .path {
            paths.insert(resourcePath, at: 0)
        }

        return paths
    }
}

public final class PgrepSunshineProcessInspector: SunshineProcessInspecting {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func isSunshineRunning() async -> Bool {
        let result = await runner.run(
            executablePath: "/usr/bin/pgrep",
            arguments: ["-x", "sunshine"],
            timeout: 2
        )

        return result.exitCode == 0
    }
}

public final class LocalSunshineWebUIProbe: NSObject, SunshineWebUIProbing, URLSessionDelegate {
    private let url: URL
    private let timeout: TimeInterval

    public init(url: URL = URL(string: "https://localhost:47990")!, timeout: TimeInterval = 2) {
        self.url = url
        self.timeout = timeout
    }

    public func isReachable() async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200..<500).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              isLocalHost(challenge.protectionSpace.host),
              let trust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        return (.useCredential, URLCredential(trust: trust))
    }

    private func isLocalHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

public struct CommandResult: Equatable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CommandRunning {
    func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult
}

public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(exitCode: 127, standardError: error.localizedDescription))
                return
            }

            let deadline = DispatchTime.now() + timeout
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

            continuation.resume(
                returning: CommandResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
                    standardError: String(data: stderrData, encoding: .utf8) ?? ""
                )
            )
        }
    }
}
