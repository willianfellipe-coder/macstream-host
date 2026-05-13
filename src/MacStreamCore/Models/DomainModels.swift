// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum CheckStatus: String, Codable, Equatable, CaseIterable {
    case pass
    case warning
    case fail
    case unknown

    public var isPassing: Bool {
        self == .pass
    }

    public var isBlocking: Bool {
        self == .fail
    }

    public var displayName: String {
        switch self {
        case .pass: return "OK"
        case .warning: return "Atenção"
        case .fail: return "Falha"
        case .unknown: return "Desconhecido"
        }
    }
}

public enum SetupItemID: String, Codable, Hashable, CaseIterable {
    case macOSVersion
    case permissions
    case sunshineInstalled
    case blackHoleInstalled
    case audioConfiguration
    case networkPorts
    case moonlightPairing
}

public struct SetupChecklistItem: Identifiable, Codable, Equatable {
    public let id: SetupItemID
    public var title: String
    public var status: CheckStatus
    public var detail: String

    public init(id: SetupItemID, title: String, status: CheckStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public enum SunshineServiceState: String, Codable, Equatable, CaseIterable {
    case notInstalled
    case stopped
    case starting
    case running
    case degraded
    case failed
    case unknown

    public var isOperational: Bool {
        self == .running || self == .degraded
    }

    public var displayName: String {
        switch self {
        case .notInstalled: return "Não instalado"
        case .stopped: return "Parado"
        case .starting: return "Iniciando"
        case .running: return "Rodando"
        case .degraded: return "Degradado"
        case .failed: return "Falhou"
        case .unknown: return "Desconhecido"
        }
    }

    public var checkStatus: CheckStatus {
        switch self {
        case .running: return .pass
        case .degraded, .stopped, .starting: return .warning
        case .notInstalled, .failed: return .fail
        case .unknown: return .unknown
        }
    }
}

public struct SunshineStatus: Codable, Equatable {
    public var state: SunshineServiceState
    public var version: String?
    public var webUIReachable: Bool
    public var configurationPath: String?
    public var binaryPath: String?
    public var ownedProcessID: Int32?

    public init(
        state: SunshineServiceState,
        version: String? = nil,
        webUIReachable: Bool = false,
        configurationPath: String? = nil,
        binaryPath: String? = nil,
        ownedProcessID: Int32? = nil
    ) {
        self.state = state
        self.version = version
        self.webUIReachable = webUIReachable
        self.configurationPath = configurationPath
        self.binaryPath = binaryPath
        self.ownedProcessID = ownedProcessID
    }
}

public enum BlackHoleInstallationStatus: String, Codable, Equatable, CaseIterable {
    case installed
    case missing
    case incompatible
    case unknown

    public var isUsable: Bool {
        self == .installed
    }

    public var displayName: String {
        switch self {
        case .installed: return "Instalado"
        case .missing: return "Não encontrado"
        case .incompatible: return "Incompatível"
        case .unknown: return "Desconhecido"
        }
    }

    public var checkStatus: CheckStatus {
        switch self {
        case .installed: return .pass
        case .missing, .incompatible: return .warning
        case .unknown: return .unknown
        }
    }
}

public enum MacPermission: String, Codable, Hashable, CaseIterable {
    case screenRecording
    case microphone
    case localNetwork
    case accessibility

    public var displayName: String {
        switch self {
        case .screenRecording: return "Gravação de tela"
        case .microphone: return "Microfone"
        case .localNetwork: return "Rede local"
        case .accessibility: return "Acessibilidade"
        }
    }

    public var isCriticalForMVP: Bool {
        switch self {
        case .screenRecording, .microphone, .localNetwork:
            return true
        case .accessibility:
            return false
        }
    }
}

public enum PermissionStatus: String, Codable, Equatable, CaseIterable {
    case granted
    case denied
    case notDetermined
    case requiresValidation
    case unknown

    public var isSatisfied: Bool {
        self == .granted
    }

    public var checkStatus: CheckStatus {
        switch self {
        case .granted: return .pass
        case .requiresValidation, .notDetermined: return .warning
        case .denied: return .fail
        case .unknown: return .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .granted: return "Concedida"
        case .denied: return "Negada"
        case .notDetermined: return "Não solicitada"
        case .requiresValidation: return "Validar manualmente"
        case .unknown: return "Desconhecida"
        }
    }
}

public struct PermissionCheck: Identifiable, Codable, Equatable {
    public var id: MacPermission
    public var status: PermissionStatus
    public var detail: String

    public init(id: MacPermission, status: PermissionStatus, detail: String) {
        self.id = id
        self.status = status
        self.detail = detail
    }
}

public struct MacOSPermissionsStatus: Codable, Equatable {
    public var checks: [PermissionCheck]

    public init(checks: [PermissionCheck]) {
        self.checks = checks
    }

    public var criticalPermissionsSatisfied: Bool {
        checks
            .filter { $0.id.isCriticalForMVP }
            .allSatisfy { $0.status.isSatisfied }
    }

    public var aggregateStatus: CheckStatus {
        let criticalChecks = checks.filter { $0.id.isCriticalForMVP }

        if criticalChecks.contains(where: { $0.status.checkStatus == .fail }) {
            return .fail
        }

        if checks.contains(where: { $0.status.checkStatus == .warning || $0.status.checkStatus == .fail }) {
            return .warning
        }

        if checks.allSatisfy({ $0.status.checkStatus == .pass }) {
            return .pass
        }

        return .unknown
    }
}

public enum AudioDeviceStatus: String, Codable, Equatable, CaseIterable {
    case available
    case unavailable
    case misconfigured
    case unknown
}

public struct AudioDevice: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var channels: Int
    public var sampleRate: Double?
    public var isInput: Bool
    public var isOutput: Bool
    public var status: AudioDeviceStatus

    public init(
        id: String,
        name: String,
        channels: Int,
        sampleRate: Double? = nil,
        isInput: Bool,
        isOutput: Bool,
        status: AudioDeviceStatus
    ) {
        self.id = id
        self.name = name
        self.channels = channels
        self.sampleRate = sampleRate
        self.isInput = isInput
        self.isOutput = isOutput
        self.status = status
    }
}

public enum AudioCaptureMode: String, Codable, Equatable, Hashable, CaseIterable {
    case nativeSystemAudio
    case blackHole2ch
    case manualDevice
    case unknown

    public var displayName: String {
        switch self {
        case .nativeSystemAudio: return "Captura nativa do macOS"
        case .blackHole2ch: return "BlackHole 2ch"
        case .manualDevice: return "Dispositivo manual"
        case .unknown: return "Desconhecido"
        }
    }
}

public struct MacStreamHostSettings: Codable, Equatable {
    public var sunshineBinaryPath: String?
    public var configDirectoryPath: String
    public var logDirectoryPath: String
    public var audioCaptureMode: AudioCaptureMode

    public init(
        sunshineBinaryPath: String? = nil,
        configDirectoryPath: String,
        logDirectoryPath: String,
        audioCaptureMode: AudioCaptureMode = .blackHole2ch
    ) {
        self.sunshineBinaryPath = sunshineBinaryPath
        self.configDirectoryPath = configDirectoryPath
        self.logDirectoryPath = logDirectoryPath
        self.audioCaptureMode = audioCaptureMode
    }

    public static func defaults(fileManager: FileManager = .default) -> MacStreamHostSettings {
        let home = fileManager.homeDirectoryForCurrentUser
        return MacStreamHostSettings(
            sunshineBinaryPath: nil,
            configDirectoryPath: home
                .appendingPathComponent("Library/Application Support/MacStreamHost/sunshine")
                .path,
            logDirectoryPath: home
                .appendingPathComponent("Library/Logs/MacStreamHost")
                .path,
            audioCaptureMode: .blackHole2ch
        )
    }

    public var configDirectoryURL: URL {
        URL(fileURLWithPath: (configDirectoryPath as NSString).expandingTildeInPath)
    }

    public var sunshineConfigURL: URL {
        configDirectoryURL.appendingPathComponent("sunshine.conf")
    }

    public var appsJSONURL: URL {
        configDirectoryURL.appendingPathComponent("apps.json")
    }

    public var logDirectoryURL: URL {
        URL(fileURLWithPath: (logDirectoryPath as NSString).expandingTildeInPath)
    }

    public var audioSink: String? {
        switch audioCaptureMode {
        case .blackHole2ch:
            return "BlackHole 2ch"
        case .nativeSystemAudio, .manualDevice, .unknown:
            return nil
        }
    }

    public func normalized() -> MacStreamHostSettings {
        MacStreamHostSettings(
            sunshineBinaryPath: sunshineBinaryPath?.isEmpty == true ? nil : sunshineBinaryPath,
            configDirectoryPath: (configDirectoryPath as NSString).expandingTildeInPath,
            logDirectoryPath: (logDirectoryPath as NSString).expandingTildeInPath,
            audioCaptureMode: audioCaptureMode == .unknown ? .blackHole2ch : audioCaptureMode
        )
    }
}

public enum NetworkProtocolKind: String, Codable, Equatable, CaseIterable {
    case tcp
    case udp
}

public struct NetworkPortCheck: Identifiable, Codable, Equatable {
    public var id: String { "\(protocolKind.rawValue)-\(port)-\(name)" }
    public var name: String
    public var protocolKind: NetworkProtocolKind
    public var port: Int
    public var status: CheckStatus
    public var detail: String

    public init(
        name: String,
        protocolKind: NetworkProtocolKind,
        port: Int,
        status: CheckStatus,
        detail: String
    ) {
        self.name = name
        self.protocolKind = protocolKind
        self.port = port
        self.status = status
        self.detail = detail
    }
}

public struct NetworkDiagnosticResult: Codable, Equatable {
    public var localAddresses: [String]
    public var tailscaleAddress: String?
    public var portChecks: [NetworkPortCheck]
    public var firewallStatus: CheckStatus

    public init(
        localAddresses: [String],
        tailscaleAddress: String? = nil,
        portChecks: [NetworkPortCheck],
        firewallStatus: CheckStatus = .unknown
    ) {
        self.localAddresses = localAddresses
        self.tailscaleAddress = tailscaleAddress
        self.portChecks = portChecks
        self.firewallStatus = firewallStatus
    }

    public var isReadyForLocalPairing: Bool {
        !localAddresses.isEmpty && !portChecks.contains(where: { $0.status == .fail })
    }

    public var aggregateStatus: CheckStatus {
        if portChecks.contains(where: { $0.status == .fail }) {
            return .fail
        }

        if localAddresses.isEmpty || portChecks.contains(where: { $0.status == .warning }) {
            return .warning
        }

        return .pass
    }
}

public enum LaunchAgentStatus: String, Codable, Equatable, CaseIterable {
    case notInstalled
    case installed
    case loaded
    case failed
    case unknown

    public var displayName: String {
        switch self {
        case .notInstalled: return "Não instalado"
        case .installed: return "Instalado"
        case .loaded: return "Carregado"
        case .failed: return "Falhou"
        case .unknown: return "Desconhecido"
        }
    }

    public var checkStatus: CheckStatus {
        switch self {
        case .loaded: return .pass
        case .installed, .notInstalled: return .warning
        case .failed: return .fail
        case .unknown: return .unknown
        }
    }
}

public struct LaunchAgentDefinition: Codable, Equatable {
    public var label: String
    public var sunshineBinaryPath: String
    public var sunshineConfigPath: String
    public var logDirectoryPath: String
    public var runAtLoad: Bool
    public var keepAlive: Bool

    public init(
        label: String = "com.macstream.host.sunshine",
        sunshineBinaryPath: String,
        sunshineConfigPath: String,
        logDirectoryPath: String,
        runAtLoad: Bool = true,
        keepAlive: Bool = true
    ) {
        self.label = label
        self.sunshineBinaryPath = sunshineBinaryPath
        self.sunshineConfigPath = sunshineConfigPath
        self.logDirectoryPath = logDirectoryPath
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
    }

    public var standardOutPath: String {
        URL(fileURLWithPath: logDirectoryPath).appendingPathComponent("sunshine.out.log").path
    }

    public var standardErrorPath: String {
        URL(fileURLWithPath: logDirectoryPath).appendingPathComponent("sunshine.err.log").path
    }

    public var propertyList: [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [
                sunshineBinaryPath,
                sunshineConfigPath
            ],
            "RunAtLoad": runAtLoad,
            "KeepAlive": keepAlive,
            "StandardOutPath": standardOutPath,
            "StandardErrorPath": standardErrorPath
        ]
    }
}

public struct LaunchAgentValidationResult: Codable, Equatable {
    public var isValid: Bool
    public var errors: [String]
    public var warnings: [String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

public struct LogEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var subsystem: String
    public var message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        subsystem: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.message = message
    }
}

public struct PairingStep: Identifiable, Codable, Equatable {
    public var id: Int
    public var title: String
    public var detail: String

    public init(id: Int, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public enum HealthCheckID: String, Codable, Hashable, CaseIterable {
    case macOSVersion
    case architecture
    case sunshine
    case sunshineRuntime
    case webUI
    case blackHole
    case permissions
    case audio
    case network
    case launchAgent
}

public struct HealthCheck: Identifiable, Codable, Equatable {
    public var id: HealthCheckID
    public var title: String
    public var status: CheckStatus
    public var detail: String

    public init(id: HealthCheckID, title: String, status: CheckStatus, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public enum HealthCheckResultStatus: String, Codable, Equatable, CaseIterable {
    case pass
    case degraded
    case failing
    case unknown

    public var displayName: String {
        switch self {
        case .pass: return "Saudável"
        case .degraded: return "Degradado"
        case .failing: return "Falhando"
        case .unknown: return "Desconhecido"
        }
    }
}

public struct HealthCheckResult: Codable, Equatable {
    public var status: HealthCheckResultStatus
    public var checks: [HealthCheck]
    public var generatedAt: Date
    public var recommendedNextStep: String

    public init(
        checks: [HealthCheck],
        generatedAt: Date = Date(),
        recommendedNextStep: String? = nil
    ) {
        self.checks = checks
        self.generatedAt = generatedAt
        self.status = Self.aggregateStatus(for: checks)
        self.recommendedNextStep = recommendedNextStep ?? Self.defaultNextStep(for: checks)
    }

    private static func aggregateStatus(for checks: [HealthCheck]) -> HealthCheckResultStatus {
        guard !checks.isEmpty else {
            return .unknown
        }

        if checks.contains(where: { $0.status == .fail }) {
            return .failing
        }

        if checks.contains(where: { $0.status == .warning || $0.status == .unknown }) {
            return .degraded
        }

        return .pass
    }

    private static func defaultNextStep(for checks: [HealthCheck]) -> String {
        if let failingCheck = checks.first(where: { $0.status == .fail }) {
            return failingCheck.detail
        }

        if let warningCheck = checks.first(where: { $0.status == .warning || $0.status == .unknown }) {
            return warningCheck.detail
        }

        return "Pareie um cliente Moonlight e valide vídeo, áudio e entrada."
    }
}

public enum StreamingCodec: String, Codable, Equatable, CaseIterable {
    case h264
    case hevc
    case automatic
}

public enum StreamingQualityProfile: String, Codable, Equatable, CaseIterable {
    case balancedIPad
    case highQualityLocal
    case lowLatency
    case remoteVPN
    case custom

    public var displayName: String {
        switch self {
        case .balancedIPad: return "iPad equilibrado"
        case .highQualityLocal: return "Alta qualidade local"
        case .lowLatency: return "Baixa latência"
        case .remoteVPN: return "Remoto/VPN"
        case .custom: return "Personalizado"
        }
    }

    public var recommendedConfiguration: RecommendedStreamingConfiguration {
        switch self {
        case .balancedIPad:
            return RecommendedStreamingConfiguration(profile: self, width: 1920, height: 1200, framesPerSecond: 60, bitrateMbps: 35, codec: .hevc, audioMode: .nativeSystemAudio)
        case .highQualityLocal:
            return RecommendedStreamingConfiguration(profile: self, width: 2560, height: 1600, framesPerSecond: 60, bitrateMbps: 80, codec: .hevc, audioMode: .nativeSystemAudio)
        case .lowLatency:
            return RecommendedStreamingConfiguration(profile: self, width: 1920, height: 1080, framesPerSecond: 60, bitrateMbps: 25, codec: .automatic, audioMode: .nativeSystemAudio)
        case .remoteVPN:
            return RecommendedStreamingConfiguration(profile: self, width: 1920, height: 1080, framesPerSecond: 60, bitrateMbps: 18, codec: .hevc, audioMode: .nativeSystemAudio)
        case .custom:
            return RecommendedStreamingConfiguration(profile: self, width: 1920, height: 1080, framesPerSecond: 60, bitrateMbps: 30, codec: .automatic, audioMode: .unknown)
        }
    }
}

public struct RecommendedStreamingConfiguration: Codable, Equatable {
    public var profile: StreamingQualityProfile
    public var width: Int
    public var height: Int
    public var framesPerSecond: Int
    public var bitrateMbps: Int
    public var codec: StreamingCodec
    public var audioMode: AudioCaptureMode

    public init(
        profile: StreamingQualityProfile,
        width: Int,
        height: Int,
        framesPerSecond: Int,
        bitrateMbps: Int,
        codec: StreamingCodec,
        audioMode: AudioCaptureMode
    ) {
        self.profile = profile
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.bitrateMbps = bitrateMbps
        self.codec = codec
        self.audioMode = audioMode
    }
}

public struct ConfigurationValidationResult: Codable, Equatable {
    public var isValid: Bool
    public var errors: [String]
    public var warnings: [String]
    public var parsedValues: [String: String]

    public init(
        isValid: Bool,
        errors: [String] = [],
        warnings: [String] = [],
        parsedValues: [String: String] = [:]
    ) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.parsedValues = parsedValues
    }
}

public enum ConfigurationFileAction: String, Codable, Equatable, CaseIterable {
    case created
    case skippedExisting
    case backedUpAndReplaced
}

public struct ConfigurationFileWriteResult: Codable, Equatable {
    public var url: URL
    public var action: ConfigurationFileAction
    public var backupURL: URL?

    public init(url: URL, action: ConfigurationFileAction, backupURL: URL? = nil) {
        self.url = url
        self.action = action
        self.backupURL = backupURL
    }
}

public struct SoftResetResult: Codable, Equatable {
    public var actions: [String]
    public var archivedConfigDirectory: URL?

    public init(actions: [String], archivedConfigDirectory: URL? = nil) {
        self.actions = actions
        self.archivedConfigDirectory = archivedConfigDirectory
    }
}

public struct DashboardSnapshot: Codable, Equatable {
    public var sunshineStatus: SunshineStatus
    public var blackHoleStatus: BlackHoleInstallationStatus
    public var permissionsStatus: MacOSPermissionsStatus
    public var networkStatus: NetworkDiagnosticResult
    public var recommendedNextStep: String

    public init(
        sunshineStatus: SunshineStatus,
        blackHoleStatus: BlackHoleInstallationStatus,
        permissionsStatus: MacOSPermissionsStatus,
        networkStatus: NetworkDiagnosticResult,
        recommendedNextStep: String
    ) {
        self.sunshineStatus = sunshineStatus
        self.blackHoleStatus = blackHoleStatus
        self.permissionsStatus = permissionsStatus
        self.networkStatus = networkStatus
        self.recommendedNextStep = recommendedNextStep
    }

    public static let initial = DashboardSnapshot(
        sunshineStatus: SunshineStatus(state: .unknown),
        blackHoleStatus: .unknown,
        permissionsStatus: MacOSPermissionsStatus(checks: []),
        networkStatus: NetworkDiagnosticResult(localAddresses: [], portChecks: []),
        recommendedNextStep: "Execute o diagnóstico inicial."
    )
}

public struct SupportBundleResult: Codable, Equatable {
    public var directoryPath: String
    public var files: [String]

    public init(directoryPath: String, files: [String]) {
        self.directoryPath = directoryPath
        self.files = files
    }
}
