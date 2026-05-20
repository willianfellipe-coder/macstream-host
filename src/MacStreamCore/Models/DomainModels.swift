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

public enum HostOperationalState: String, Codable, Equatable, CaseIterable {
    case ready
    case blocked
    case needsPermission
    case needsDependency
    case running
    case externalConflict
    case unknown

    public var displayName: String {
        switch self {
        case .ready: return "Pronto"
        case .blocked: return "Bloqueado"
        case .needsPermission: return "Permissão pendente"
        case .needsDependency: return "Dependência pendente"
        case .running: return "Rodando"
        case .externalConflict: return "Conflito externo"
        case .unknown: return "Desconhecido"
        }
    }

    public var checkStatus: CheckStatus {
        switch self {
        case .ready, .running: return .pass
        case .needsPermission, .needsDependency, .unknown: return .warning
        case .blocked, .externalConflict: return .fail
        }
    }
}

public enum RemoteWorkModeState: String, Codable, Equatable, CaseIterable {
    case notReady
    case ready
    case starting
    case running
    case degraded
    case stopping
    case blocked

    public var displayName: String {
        switch self {
        case .notReady: return "Nao preparado"
        case .ready: return "Pronto"
        case .starting: return "Iniciando"
        case .running: return "Modo remoto ativo"
        case .degraded: return "Modo remoto degradado"
        case .stopping: return "Parando"
        case .blocked: return "Bloqueado"
        }
    }

    public var checkStatus: CheckStatus {
        switch self {
        case .ready, .running: return .pass
        case .notReady, .starting, .stopping, .degraded: return .warning
        case .blocked: return .fail
        }
    }

    /// True when the engine is actively or transitionally streaming. The
    /// privacy overlay uses this to decide whether the floating unlock panel
    /// should be suppressed (it leaks into the remote stream and intercepts
    /// forwarded input from the client).
    public var isStreamingActive: Bool {
        switch self {
        case .running, .degraded, .starting: return true
        case .notReady, .ready, .stopping, .blocked: return false
        }
    }
}

public enum ManagedEngineKind: String, Codable, Hashable, CaseIterable {
    case video
    case audio
    case network

    public var displayName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .network: return "Rede"
        }
    }
}

public struct ManagedEngineComponentStatus: Identifiable, Codable, Equatable {
    public var id: ManagedEngineKind
    public var status: CheckStatus
    public var detail: String

    public init(id: ManagedEngineKind, status: CheckStatus, detail: String) {
        self.id = id
        self.status = status
        self.detail = detail
    }
}

public struct ManagedEngineStatus: Codable, Equatable {
    public var components: [ManagedEngineComponentStatus]

    public init(components: [ManagedEngineComponentStatus]) {
        self.components = components
    }

    public var aggregateStatus: CheckStatus {
        if components.contains(where: { $0.status == .fail }) {
            return .fail
        }

        if components.contains(where: { $0.status == .warning || $0.status == .unknown }) {
            return .warning
        }

        return components.isEmpty ? .unknown : .pass
    }

    public static let initial = ManagedEngineStatus(components: [
        ManagedEngineComponentStatus(id: .video, status: .unknown, detail: "Engine de video ainda nao avaliada."),
        ManagedEngineComponentStatus(id: .audio, status: .unknown, detail: "Rota de audio ainda nao avaliada."),
        ManagedEngineComponentStatus(id: .network, status: .unknown, detail: "Rede ainda nao avaliada.")
    ])
}

public struct PowerPolicy: Codable, Equatable {
    public var preventSystemSleep: Bool
    public var keepDisplayAwake: Bool

    public init(preventSystemSleep: Bool = true, keepDisplayAwake: Bool = false) {
        self.preventSystemSleep = preventSystemSleep
        self.keepDisplayAwake = keepDisplayAwake
    }

    public static let defaults = PowerPolicy()
}

public struct PowerAssertionStatus: Codable, Equatable {
    public var isActive: Bool
    public var policy: PowerPolicy
    public var assertionID: UInt32?
    public var detail: String

    public init(
        isActive: Bool,
        policy: PowerPolicy = .defaults,
        assertionID: UInt32? = nil,
        detail: String
    ) {
        self.isActive = isActive
        self.policy = policy
        self.assertionID = assertionID
        self.detail = detail
    }

    public var checkStatus: CheckStatus {
        isActive ? .pass : .warning
    }

    public static let inactive = PowerAssertionStatus(
        isActive: false,
        detail: "MacStream nao esta mantendo o Mac acordado agora."
    )
}

public struct AppPasswordPolicy: Codable, Equatable {
    /// When true, dismissing the privacy overlay requires the user to type the
    /// app password configured in Settings (stored in the macOS Keychain).
    public var requireOnOverlayUnlock: Bool

    public init(requireOnOverlayUnlock: Bool = false) {
        self.requireOnOverlayUnlock = requireOnOverlayUnlock
    }

    private enum CodingKeys: String, CodingKey {
        case requireOnOverlayUnlock
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requireOnOverlayUnlock = try container.decodeIfPresent(Bool.self, forKey: .requireOnOverlayUnlock) ?? false
    }

    public static let defaults = AppPasswordPolicy()
}

public enum HostPrivacyMode: String, Codable, Equatable, CaseIterable {
    /// Cover the host screen with an in-app NSWindow. Safe — does not touch the
    /// macOS graphics session and cannot disrupt an active Moonlight stream.
    case appOverlay
    /// Invoke `CGSession -suspend`. May suspend the user's graphical session,
    /// which is unvalidated against Sunshine streaming and therefore experimental.
    case systemSuspend
    /// Asymmetric secure overlay: a true black NSWindow with mandatory
    /// password (app pwd or Touch ID/macOS pwd) on every non-streamed
    /// display, and brightness=0 on the streamed display so SCK never
    /// sees the overlay. Opt-in — requires at least one auth method
    /// configured (app password set OR LocalAuthentication available).
    case secureOverlay

    public var displayName: String {
        switch self {
        case .appOverlay: return "Overlay no app (seguro)"
        case .systemSuspend: return "Bloqueio do sistema (experimental)"
        case .secureOverlay: return "Bloqueio seguro com senha"
        }
    }
}

public struct HostPrivacyPolicy: Codable, Equatable {
    public var offerLockOnSessionStart: Bool
    public var allowManualLock: Bool
    public var mode: HostPrivacyMode
    /// Allow Touch ID / macOS user password (LocalAuthentication) as an
    /// unlock method when `mode == .secureOverlay`. Ignored for other modes.
    public var secureAllowMacOSAuthentication: Bool
    /// Legacy compatibility flag for older settings JSON. Secure lock now
    /// treats the MacStream app password as a mandatory fallback.
    public var secureAllowAppPassword: Bool
    /// Cap on consecutive wrong unlock attempts before the secure overlay
    /// enters a temporal lockout. Backoff is 30s × attempt, capped at 5min.
    public var secureMaxUnlockAttempts: Int

    public init(
        offerLockOnSessionStart: Bool = true,
        allowManualLock: Bool = true,
        mode: HostPrivacyMode = .secureOverlay,
        secureAllowMacOSAuthentication: Bool = true,
        secureAllowAppPassword: Bool = true,
        secureMaxUnlockAttempts: Int = 5
    ) {
        self.offerLockOnSessionStart = offerLockOnSessionStart
        self.allowManualLock = allowManualLock
        self.mode = mode
        self.secureAllowMacOSAuthentication = secureAllowMacOSAuthentication
        self.secureAllowAppPassword = secureAllowAppPassword
        self.secureMaxUnlockAttempts = secureMaxUnlockAttempts
    }

    private enum CodingKeys: String, CodingKey {
        case offerLockOnSessionStart
        case allowManualLock
        case mode
        case secureAllowMacOSAuthentication
        case secureAllowAppPassword
        case secureMaxUnlockAttempts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offerLockOnSessionStart = try container.decodeIfPresent(Bool.self, forKey: .offerLockOnSessionStart) ?? true
        allowManualLock = try container.decodeIfPresent(Bool.self, forKey: .allowManualLock) ?? true
        mode = try container.decodeIfPresent(HostPrivacyMode.self, forKey: .mode) ?? .appOverlay
        secureAllowMacOSAuthentication = try container.decodeIfPresent(Bool.self, forKey: .secureAllowMacOSAuthentication) ?? true
        secureAllowAppPassword = try container.decodeIfPresent(Bool.self, forKey: .secureAllowAppPassword) ?? true
        secureMaxUnlockAttempts = try container.decodeIfPresent(Int.self, forKey: .secureMaxUnlockAttempts) ?? 5
    }

    public static let defaults = HostPrivacyPolicy()
}

public enum SecureLockReadiness: Equatable {
    case ready
    case needsAppPassword
    case noSafeDisplayDuringCapture
    case lockedOut(secondsRemaining: Int)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var userMessage: String {
        switch self {
        case .ready:
            return "Bloqueio seguro pronto."
        case .needsAppPassword:
            return "Configure uma senha do MacStream antes de bloquear. Ela fica no Keychain e serve como fallback ao Touch ID / senha do macOS."
        case .noSafeDisplayDuringCapture:
            return "Bloqueio seguro precisa de uma tela não capturada pelo Moonlight. Conecte outro display ou encerre a sessão antes de bloquear."
        case .lockedOut(let secondsRemaining):
            return "Tentativas excedidas. Aguarde \(secondsRemaining) segundos antes de tentar novamente."
        }
    }
}

public enum HostPrivacyAction: String, Codable, Equatable, CaseIterable {
    case none
    case lockRequested
    case lockSucceeded
    case lockFailed
}

public struct HostPrivacyStatus: Codable, Equatable {
    public var policy: HostPrivacyPolicy
    public var lastAction: HostPrivacyAction
    public var detail: String

    public init(
        policy: HostPrivacyPolicy = .defaults,
        lastAction: HostPrivacyAction = .none,
        detail: String = "Privacidade do host pronta para uso."
    ) {
        self.policy = policy
        self.lastAction = lastAction
        self.detail = detail
    }

    public var checkStatus: CheckStatus {
        switch lastAction {
        // .none is the default state — user simply hasn't asked for a lock yet,
        // not a problem the dashboard needs to flag.
        case .none, .lockSucceeded: return .pass
        case .lockFailed: return .fail
        case .lockRequested: return .warning
        }
    }

    /// Short human label suitable for dashboard cards (avoids raw enum values
    /// like "none" leaking into the UI).
    public var displayLabel: String {
        switch lastAction {
        case .none: return "Pronta"
        case .lockRequested: return "Bloqueando…"
        case .lockSucceeded: return "Tela bloqueada"
        case .lockFailed: return "Falha no bloqueio"
        }
    }

    public static let initial = HostPrivacyStatus()
}

public enum DependencyID: String, Codable, Hashable, CaseIterable {
    case sunshine
    case blackHole
    case moonlight

    public var displayName: String {
        switch self {
        case .sunshine: return "Mecanismo de vídeo"
        case .blackHole: return "Roteamento de áudio"
        case .moonlight: return "Cliente Moonlight"
        }
    }

    public var technicalName: String {
        switch self {
        case .sunshine: return "Sunshine"
        case .blackHole: return "BlackHole 2ch"
        case .moonlight: return "Moonlight"
        }
    }
}

public struct DependencyStatus: Identifiable, Codable, Equatable {
    public var id: DependencyID
    public var status: CheckStatus
    public var detail: String
    public var detectedPath: String?
    public var detectedVersion: String?
    public var officialURL: URL?

    public init(
        id: DependencyID,
        status: CheckStatus,
        detail: String,
        detectedPath: String? = nil,
        detectedVersion: String? = nil,
        officialURL: URL? = nil
    ) {
        self.id = id
        self.status = status
        self.detail = detail
        self.detectedPath = detectedPath
        self.detectedVersion = detectedVersion
        self.officialURL = officialURL
    }
}

public enum ManagedDependencyID: String, Codable, Hashable, CaseIterable {
    case sunshine
    case blackHole

    public var displayName: String {
        switch self {
        case .sunshine: return "Mecanismo de vídeo"
        case .blackHole: return "Roteamento de áudio"
        }
    }

    public var technicalName: String {
        switch self {
        case .sunshine: return "Sunshine"
        case .blackHole: return "BlackHole 2ch"
        }
    }
}

public enum DependencyInstallerKind: String, Codable, Equatable {
    case macOSDMGApplication
    case macOSPKG
}

public struct DependencyArtifact: Identifiable, Codable, Equatable {
    public var id: ManagedDependencyID
    public var displayName: String
    public var version: String
    public var downloadURL: URL
    public var sourceURL: URL
    public var sha256: String
    public var fileName: String
    public var installerKind: DependencyInstallerKind
    public var requiresAdministrator: Bool
    public var requiresReboot: Bool
    public var isPrerelease: Bool

    public init(
        id: ManagedDependencyID,
        displayName: String,
        version: String,
        downloadURL: URL,
        sourceURL: URL,
        sha256: String,
        fileName: String,
        installerKind: DependencyInstallerKind,
        requiresAdministrator: Bool,
        requiresReboot: Bool,
        isPrerelease: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.downloadURL = downloadURL
        self.sourceURL = sourceURL
        self.sha256 = sha256
        self.fileName = fileName
        self.installerKind = installerKind
        self.requiresAdministrator = requiresAdministrator
        self.requiresReboot = requiresReboot
        self.isPrerelease = isPrerelease
    }
}

public enum DependencyInstallStage: String, Codable, Equatable {
    case idle
    case downloading
    case verifying
    case installing
    case waitingForUser
    case completed
    case failed

    public var displayName: String {
        switch self {
        case .idle: return "Aguardando"
        case .downloading: return "Baixando"
        case .verifying: return "Verificando"
        case .installing: return "Instalando"
        case .waitingForUser: return "Aguardando usuário"
        case .completed: return "Concluído"
        case .failed: return "Falhou"
        }
    }
}

public struct DependencyInstallProgress: Identifiable, Codable, Equatable {
    public var id: ManagedDependencyID
    public var stage: DependencyInstallStage
    public var detail: String

    public init(id: ManagedDependencyID, stage: DependencyInstallStage, detail: String) {
        self.id = id
        self.stage = stage
        self.detail = detail
    }
}

public struct DependencyInstallResult: Codable, Equatable {
    public var dependencyID: ManagedDependencyID
    public var artifact: DependencyArtifact
    public var downloadedPath: String
    public var installedPath: String?
    public var installedBinaryPath: String?
    public var requiresUserCompletion: Bool
    public var message: String

    public init(
        dependencyID: ManagedDependencyID,
        artifact: DependencyArtifact,
        downloadedPath: String,
        installedPath: String? = nil,
        installedBinaryPath: String? = nil,
        requiresUserCompletion: Bool,
        message: String
    ) {
        self.dependencyID = dependencyID
        self.artifact = artifact
        self.downloadedPath = downloadedPath
        self.installedPath = installedPath
        self.installedBinaryPath = installedBinaryPath
        self.requiresUserCompletion = requiresUserCompletion
        self.message = message
    }
}

public enum OnboardingStepID: String, Codable, Hashable, CaseIterable {
    case system
    case sunshine
    case blackHole
    case audio
    case permissions
    case configuration
    case startSunshine
    case webUI
    case moonlightPairing
    case diagnostics
}

public enum OnboardingStepState: String, Codable, Equatable, CaseIterable {
    case pending
    case active
    case passed
    case warning
    case failed

    public var checkStatus: CheckStatus {
        switch self {
        case .passed: return .pass
        case .warning, .active, .pending: return .warning
        case .failed: return .fail
        }
    }
}

public struct OnboardingStep: Identifiable, Codable, Equatable {
    public var id: OnboardingStepID
    public var title: String
    public var state: OnboardingStepState
    public var detail: String

    public init(id: OnboardingStepID, title: String, state: OnboardingStepState, detail: String) {
        self.id = id
        self.title = title
        self.state = state
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
        case .screenRecording, .microphone:
            return true
        case .localNetwork, .accessibility:
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

public struct PermissionRequestResult: Identifiable, Codable, Equatable {
    public var id: MacPermission
    public var statusBefore: PermissionStatus
    public var statusAfter: PermissionStatus
    public var promptAttempted: Bool
    public var detail: String

    public init(
        id: MacPermission,
        statusBefore: PermissionStatus,
        statusAfter: PermissionStatus,
        promptAttempted: Bool,
        detail: String
    ) {
        self.id = id
        self.statusBefore = statusBefore
        self.statusAfter = statusAfter
        self.promptAttempted = promptAttempted
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

        // Only critical permissions (Screen Recording, Microphone) drag the
        // aggregate down. Local Network is unmeasurable from inside the app
        // and Accessibility is optional — surfacing them as warnings just
        // because macOS can't confirm them from outside is misleading.
        if criticalChecks.contains(where: { $0.status.checkStatus == .warning }) {
            return .warning
        }

        if checks.isEmpty {
            return .unknown
        }

        return .pass
    }

    public var runtimeGuidanceStatus: CheckStatus {
        if checks.isEmpty {
            return .unknown
        }

        return checks.allSatisfy { $0.status.checkStatus == .pass } ? .pass : .warning
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

/// Result of toggling the system's default audio output device. Used by
/// the AudioView "Rotear áudio para o MacStream" button to drive a clear
/// success / no-op / failure message.
public enum AudioRoutingResult: Equatable {
    /// The system output device was changed. `previousDevice` is the
    /// device the user was listening on before the toggle so the UI can
    /// offer a "restore" action.
    case routed(previousDevice: AudioDevice?, newDevice: AudioDevice)
    /// The target device was already the default — nothing to do.
    case alreadyRouted(currentDevice: AudioDevice)
    /// The requested device isn't currently available on this Mac (e.g.
    /// BlackHole 2ch driver missing).
    case targetDeviceUnavailable
    /// CoreAudio refused the change — usually returns a non-zero OSStatus.
    case routingFailed(message: String)

    public var didChangeOutput: Bool {
        switch self {
        case .routed: return true
        default: return false
        }
    }
}

public struct MacStreamHostSettings: Codable, Equatable {
    public var sunshineBinaryPath: String?
    public var agentExecutablePath: String?
    public var configDirectoryPath: String
    public var logDirectoryPath: String
    public var audioCaptureMode: AudioCaptureMode
    public var powerPolicy: PowerPolicy
    public var hostPrivacyPolicy: HostPrivacyPolicy
    public var appPasswordPolicy: AppPasswordPolicy
    public var showMenuBarItem: Bool
    /// When true, the GUI app registers itself with macOS as a login item AND
    /// — whether launched at boot or by the user — starts as an accessory
    /// (no Dock icon, no main window shown). The menu bar item is the only
    /// entry point. The dashboard is opened on demand via the tray.
    public var startInBackground: Bool

    /// Low-latency tuning profile. When true, `sunshine.conf` is emitted
    /// with `fec_percentage = 0` (skip Forward Error Correction on the
    /// assumption that the stream runs over a local network with
    /// negligible packet loss), `min_threads = 4` (more parallel
    /// encoding threads → less queueing latency on the encoder), and
    /// `min_log_level = warning` (drop the per-frame info logs).
    /// Trade-off: on lossy networks (Wi-Fi spam, cellular, Tailscale
    /// over Internet) the absence of FEC means more retransmissions →
    /// stutter. The Settings UI surfaces this warning explicitly.
    public var lowLatencyMode: Bool

    public init(
        sunshineBinaryPath: String? = nil,
        agentExecutablePath: String? = nil,
        configDirectoryPath: String,
        logDirectoryPath: String,
        audioCaptureMode: AudioCaptureMode = .nativeSystemAudio,
        powerPolicy: PowerPolicy = .defaults,
        hostPrivacyPolicy: HostPrivacyPolicy = .defaults,
        appPasswordPolicy: AppPasswordPolicy = .defaults,
        showMenuBarItem: Bool = true,
        startInBackground: Bool = false,
        lowLatencyMode: Bool = false
    ) {
        self.sunshineBinaryPath = sunshineBinaryPath
        self.agentExecutablePath = agentExecutablePath
        self.configDirectoryPath = configDirectoryPath
        self.logDirectoryPath = logDirectoryPath
        self.audioCaptureMode = audioCaptureMode
        self.powerPolicy = powerPolicy
        self.hostPrivacyPolicy = hostPrivacyPolicy
        self.appPasswordPolicy = appPasswordPolicy
        self.showMenuBarItem = showMenuBarItem
        self.startInBackground = startInBackground
        self.lowLatencyMode = lowLatencyMode
    }

    private enum CodingKeys: String, CodingKey {
        case sunshineBinaryPath
        case agentExecutablePath
        case configDirectoryPath
        case logDirectoryPath
        case audioCaptureMode
        case powerPolicy
        case hostPrivacyPolicy
        case appPasswordPolicy
        case showMenuBarItem
        case startInBackground
        case lowLatencyMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MacStreamHostSettings.defaults()
        sunshineBinaryPath = try container.decodeIfPresent(String.self, forKey: .sunshineBinaryPath)
        agentExecutablePath = try container.decodeIfPresent(String.self, forKey: .agentExecutablePath)
        configDirectoryPath = try container.decodeIfPresent(String.self, forKey: .configDirectoryPath)
            ?? defaults.configDirectoryPath
        logDirectoryPath = try container.decodeIfPresent(String.self, forKey: .logDirectoryPath)
            ?? defaults.logDirectoryPath
        audioCaptureMode = try container.decodeIfPresent(AudioCaptureMode.self, forKey: .audioCaptureMode) ?? .nativeSystemAudio
        powerPolicy = try container.decodeIfPresent(PowerPolicy.self, forKey: .powerPolicy) ?? .defaults
        hostPrivacyPolicy = try container.decodeIfPresent(HostPrivacyPolicy.self, forKey: .hostPrivacyPolicy) ?? .defaults
        appPasswordPolicy = try container.decodeIfPresent(AppPasswordPolicy.self, forKey: .appPasswordPolicy) ?? .defaults
        showMenuBarItem = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? true
        startInBackground = try container.decodeIfPresent(Bool.self, forKey: .startInBackground) ?? false
        lowLatencyMode = try container.decodeIfPresent(Bool.self, forKey: .lowLatencyMode) ?? false
    }

    public static func defaults(fileManager: FileManager = .default) -> MacStreamHostSettings {
        let home = fileManager.homeDirectoryForCurrentUser
        return MacStreamHostSettings(
            sunshineBinaryPath: nil,
            agentExecutablePath: nil,
            configDirectoryPath: home
                .appendingPathComponent("Library/Application Support/MacStreamHost/sunshine")
                .path,
            logDirectoryPath: home
                .appendingPathComponent("Library/Logs/MacStreamHost")
                .path,
            audioCaptureMode: .nativeSystemAudio,
            powerPolicy: .defaults,
            hostPrivacyPolicy: .defaults
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

    public var agentStateDirectoryURL: URL {
        configDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("Agent", isDirectory: true)
    }

    public var agentStatusURL: URL {
        agentStateDirectoryURL.appendingPathComponent("status.json")
    }

    public var agentCommandURL: URL {
        agentStateDirectoryURL.appendingPathComponent("command.json")
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
            agentExecutablePath: agentExecutablePath?.isEmpty == true ? nil : agentExecutablePath,
            configDirectoryPath: (configDirectoryPath as NSString).expandingTildeInPath,
            logDirectoryPath: (logDirectoryPath as NSString).expandingTildeInPath,
            audioCaptureMode: audioCaptureMode == .unknown ? .nativeSystemAudio : audioCaptureMode,
            powerPolicy: powerPolicy,
            hostPrivacyPolicy: hostPrivacyPolicy,
            appPasswordPolicy: appPasswordPolicy,
            showMenuBarItem: showMenuBarItem,
            startInBackground: startInBackground,
            lowLatencyMode: lowLatencyMode
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

/// Rich descriptor for a local IP address — couples the IP to the
/// physical interface it lives on and to a user-visible label (e.g.
/// "Wi-Fi", "USB 10/100/1000 LAN"). Used by the dashboard so the user
/// can tell at a glance which IP the Moonlight client should target.
/// Crucial when the Mac has multiple interfaces sharing a subnet — a
/// USB-Ethernet adapter with no link still gets a DHCP lease and the
/// raw IP list alone can't distinguish it from the real Wi-Fi route.
public struct NetworkLocalAddress: Codable, Equatable {
    public var address: String
    public var interfaceName: String
    public var friendlyName: String?
    /// True when this is the interface backing the IPv4 default route.
    /// Dashboard highlights it as the recommended IP to type into
    /// Moonlight when discovery doesn't find the host automatically.
    public var isPrimary: Bool

    public init(
        address: String,
        interfaceName: String,
        friendlyName: String? = nil,
        isPrimary: Bool = false
    ) {
        self.address = address
        self.interfaceName = interfaceName
        self.friendlyName = friendlyName
        self.isPrimary = isPrimary
    }

    private enum CodingKeys: String, CodingKey {
        case address, interfaceName, friendlyName, isPrimary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        interfaceName = try container.decodeIfPresent(String.self, forKey: .interfaceName) ?? ""
        friendlyName = try container.decodeIfPresent(String.self, forKey: .friendlyName)
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }

    /// User-facing one-line description. Examples:
    ///   "192.168.68.125 (Wi-Fi) — recomendado"
    ///   "192.168.68.145 (USB 10/100/1000 LAN)"
    public var displayLine: String {
        var line = address
        if let friendlyName, !friendlyName.isEmpty {
            line += " (\(friendlyName))"
        } else if !interfaceName.isEmpty {
            line += " (\(interfaceName))"
        }
        if isPrimary {
            line += " — recomendado"
        }
        return line
    }
}

/// Whether the Mac can reach OTHER devices on the LAN (excluding the
/// default gateway). Surface in the dashboard so the user can tell
/// apart "MacStream broken" from "router broken / AP isolation". Today
/// the dashboard only listed local IPs without verifying that peers can
/// actually reach those IPs — a gap that cost hours of debugging when
/// the router quietly isolated clients.
public enum PeerReachability: String, Codable, Equatable {
    /// Not enough data yet, or no peers observed in the ARP table.
    case unknown
    /// At least one neighbor IP has a resolved MAC — bridge is healthy.
    case reachable
    /// Multiple ARP probes failed (entries are "incomplete") but the
    /// gateway responds. The Mac is alone on the LAN — classic AP
    /// isolation, stale ARP table, or VLAN misconfig.
    case isolated
    /// Even the gateway doesn't respond — the Wi-Fi/Ethernet link is
    /// dead. User should reconnect to the network.
    case noGateway
}

public struct NetworkDiagnosticResult: Codable, Equatable {
    public var localAddresses: [String]
    /// Same addresses as `localAddresses` but annotated with interface
    /// metadata. Empty when the underlying provider only delivers raw
    /// strings (legacy callers, tests). When populated, dashboard +
    /// menubar should prefer rendering this over the bare list.
    public var localAddressDetails: [NetworkLocalAddress]
    public var tailscaleAddress: String?
    public var portChecks: [NetworkPortCheck]
    public var firewallStatus: CheckStatus
    /// Peer reachability assessment — see `PeerReachability` for the
    /// rationale. Dashboard renders a banner when `.isolated` or
    /// `.noGateway` to point the user away from MacStream and at the
    /// real culprit (router config).
    public var peerReachability: PeerReachability

    public init(
        localAddresses: [String],
        localAddressDetails: [NetworkLocalAddress] = [],
        tailscaleAddress: String? = nil,
        portChecks: [NetworkPortCheck],
        firewallStatus: CheckStatus = .unknown,
        peerReachability: PeerReachability = .unknown
    ) {
        self.localAddresses = localAddresses
        self.localAddressDetails = localAddressDetails
        self.tailscaleAddress = tailscaleAddress
        self.portChecks = portChecks
        self.firewallStatus = firewallStatus
        self.peerReachability = peerReachability
    }

    private enum CodingKeys: String, CodingKey {
        case localAddresses, localAddressDetails, tailscaleAddress, portChecks, firewallStatus, peerReachability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localAddresses = try container.decode([String].self, forKey: .localAddresses)
        localAddressDetails = try container.decodeIfPresent([NetworkLocalAddress].self, forKey: .localAddressDetails) ?? []
        tailscaleAddress = try container.decodeIfPresent(String.self, forKey: .tailscaleAddress)
        portChecks = try container.decode([NetworkPortCheck].self, forKey: .portChecks)
        firewallStatus = try container.decodeIfPresent(CheckStatus.self, forKey: .firewallStatus) ?? .unknown
        peerReachability = try container.decodeIfPresent(PeerReachability.self, forKey: .peerReachability) ?? .unknown
    }

    /// True when two or more local addresses live in the same /24 — a
    /// common misconfiguration when a USB-Ethernet adapter and Wi-Fi both
    /// pick up a lease from the same router. Causes asymmetric routing
    /// and breaks Moonlight discovery.
    public var hasOverlappingSubnets: Bool {
        let prefixes = localAddresses.compactMap { ip -> String? in
            let parts = ip.split(separator: ".")
            guard parts.count == 4 else { return nil }
            return parts.prefix(3).joined(separator: ".")
        }
        return Set(prefixes).count < prefixes.count
    }

    public var isReadyForLocalPairing: Bool {
        !localAddresses.isEmpty && !portChecks.contains(where: { $0.status == .fail })
    }

    public var aggregateStatus: CheckStatus {
        if portChecks.contains(where: { $0.status == .fail }) {
            return .fail
        }

        if localAddresses.isEmpty {
            return .warning
        }

        // Essential pairing/control ports — these need to be listening while
        // the engine is up. RTSP and UDP video/audio/control/microphone ports
        // bind on demand when a client actually starts a stream, so them not
        // showing in `lsof` is informational, not a real warning.
        let essentialPorts: Set<Int> = [47984, 47989, 47990]
        let essentialChecks = portChecks.filter { essentialPorts.contains($0.port) }

        if essentialChecks.isEmpty == false,
           essentialChecks.contains(where: { $0.status == .warning || $0.status == .unknown }) {
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

public struct MacStreamAgentStatus: Codable, Equatable {
    public var launchAgentStatus: LaunchAgentStatus
    public var isRunning: Bool
    public var version: String?
    public var processID: Int32?
    public var lastHeartbeat: Date?
    public var statePath: String?
    public var detail: String

    public init(
        launchAgentStatus: LaunchAgentStatus,
        isRunning: Bool,
        version: String? = nil,
        processID: Int32? = nil,
        lastHeartbeat: Date? = nil,
        statePath: String? = nil,
        detail: String
    ) {
        self.launchAgentStatus = launchAgentStatus
        self.isRunning = isRunning
        self.version = version
        self.processID = processID
        self.lastHeartbeat = lastHeartbeat
        self.statePath = statePath
        self.detail = detail
    }

    public var checkStatus: CheckStatus {
        if isRunning {
            return .pass
        }

        return launchAgentStatus.checkStatus
    }

    public static let initial = MacStreamAgentStatus(
        launchAgentStatus: .notInstalled,
        isRunning: false,
        detail: "Agente residente ainda nao instalado."
    )
}

public struct LaunchAgentDefinition: Codable, Equatable {
    public var label: String
    public var executablePath: String
    public var arguments: [String]
    public var requiredFilePaths: [String]
    public var logDirectoryPath: String
    public var runAtLoad: Bool
    public var keepAlive: Bool

    public init(
        label: String = "com.macstream.host.agent",
        executablePath: String,
        arguments: [String] = ["run"],
        requiredFilePaths: [String] = [],
        logDirectoryPath: String,
        runAtLoad: Bool = true,
        keepAlive: Bool = true
    ) {
        self.label = label
        self.executablePath = executablePath
        self.arguments = arguments
        self.requiredFilePaths = requiredFilePaths
        self.logDirectoryPath = logDirectoryPath
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
    }

    public init(
        label: String = "com.macstream.host.sunshine",
        sunshineBinaryPath: String,
        sunshineConfigPath: String,
        logDirectoryPath: String,
        runAtLoad: Bool = true,
        keepAlive: Bool = true
    ) {
        self.init(
            label: label,
            executablePath: sunshineBinaryPath,
            arguments: [sunshineConfigPath],
            requiredFilePaths: [sunshineConfigPath],
            logDirectoryPath: logDirectoryPath,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive
        )
    }

    public var standardOutPath: String {
        URL(fileURLWithPath: logDirectoryPath).appendingPathComponent("\(label).out.log").path
    }

    public var standardErrorPath: String {
        URL(fileURLWithPath: logDirectoryPath).appendingPathComponent("\(label).err.log").path
    }

    public var propertyList: [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executablePath] + arguments,
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
    case macStreamAgent
    case remoteWorkMode
    case sunshine
    case sunshineRuntime
    case sunshineScreenRecording
    case sunshineAccessibility
    case webUI
    case blackHole
    case permissions
    case audio
    case network
    case launchAgent
    case power
    case hostPrivacy
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

public struct PreflightResult: Codable, Equatable {
    public var generatedAt: Date
    public var configurationWrites: [ConfigurationFileWriteResult]
    public var dashboard: DashboardSnapshot
    public var health: HealthCheckResult
    public var operationalState: HostOperationalState
    public var blockers: [String]
    public var nextStep: String
    public var startedSunshine: Bool

    public init(
        generatedAt: Date = Date(),
        configurationWrites: [ConfigurationFileWriteResult],
        dashboard: DashboardSnapshot,
        health: HealthCheckResult,
        operationalState: HostOperationalState,
        blockers: [String],
        nextStep: String,
        startedSunshine: Bool
    ) {
        self.generatedAt = generatedAt
        self.configurationWrites = configurationWrites
        self.dashboard = dashboard
        self.health = health
        self.operationalState = operationalState
        self.blockers = blockers
        self.nextStep = nextStep
        self.startedSunshine = startedSunshine
    }
}

public enum MacStreamAgentCommandKind: String, Codable, Equatable, CaseIterable {
    case startRemoteWork
    case stopRemoteWork
    case lockHost
    case shutdown
}

public struct MacStreamAgentCommand: Codable, Equatable {
    public var id: UUID
    public var kind: MacStreamAgentCommandKind
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: MacStreamAgentCommandKind, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }
}

public struct RemoteWorkSessionReport: Codable, Equatable {
    public var generatedAt: Date
    public var state: RemoteWorkModeState
    public var agentStatus: MacStreamAgentStatus
    public var engineStatus: ManagedEngineStatus
    public var powerStatus: PowerAssertionStatus
    public var hostPrivacyStatus: HostPrivacyStatus
    public var blockers: [String]
    public var warnings: [String]
    public var nextStep: String

    public init(
        generatedAt: Date = Date(),
        state: RemoteWorkModeState,
        agentStatus: MacStreamAgentStatus,
        engineStatus: ManagedEngineStatus,
        powerStatus: PowerAssertionStatus,
        hostPrivacyStatus: HostPrivacyStatus,
        blockers: [String] = [],
        warnings: [String] = [],
        nextStep: String
    ) {
        self.generatedAt = generatedAt
        self.state = state
        self.agentStatus = agentStatus
        self.engineStatus = engineStatus
        self.powerStatus = powerStatus
        self.hostPrivacyStatus = hostPrivacyStatus
        self.blockers = blockers
        self.warnings = warnings
        self.nextStep = nextStep
    }

    public static let initial = RemoteWorkSessionReport(
        state: .notReady,
        agentStatus: .initial,
        engineStatus: .initial,
        powerStatus: .inactive,
        hostPrivacyStatus: .initial,
        nextStep: "Prepare o MacStream antes de iniciar uma sessao remota."
    )
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
    public var archivePath: String?
    public var files: [String]

    public init(directoryPath: String, archivePath: String? = nil, files: [String]) {
        self.directoryPath = directoryPath
        self.archivePath = archivePath
        self.files = files
    }
}

public struct SupportBundleOptions: Codable, Equatable {
    public var parentDirectoryPath: String
    public var includeZip: Bool
    public var maxLogLines: Int

    public init(parentDirectoryPath: String, includeZip: Bool = false, maxLogLines: Int = 200) {
        self.parentDirectoryPath = parentDirectoryPath
        self.includeZip = includeZip
        self.maxLogLines = maxLogLines
    }

    public var parentDirectoryURL: URL {
        URL(fileURLWithPath: (parentDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }
}

public struct AppBuildInfo: Codable, Equatable {
    public var version: String
    public var build: String
    public var bundleIdentifier: String
    public var commit: String?
    public var buildDate: Date?

    public init(
        version: String = "0.1.0",
        build: String = "1",
        bundleIdentifier: String = "org.macstream.host",
        commit: String? = nil,
        buildDate: Date? = nil
    ) {
        self.version = version
        self.build = build
        self.bundleIdentifier = bundleIdentifier
        self.commit = commit
        self.buildDate = buildDate
    }

    public static var current: AppBuildInfo {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        return AppBuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "0.1.0-beta.1",
            build: info["CFBundleVersion"] as? String ?? "1",
            bundleIdentifier: bundle.bundleIdentifier ?? "org.macstream.host",
            commit: ProcessInfo.processInfo.environment["MACSTREAM_GIT_COMMIT"],
            buildDate: nil
        )
    }
}

public enum MoonlightChecklistItemID: String, Codable, Hashable, CaseIterable {
    case webUIOpened
    case pinEntered
    case desktopOpened
    case videoValidated
    case audioValidated

    public var title: String {
        switch self {
        case .webUIOpened: return "Web UI aberta"
        case .pinEntered: return "PIN inserido"
        case .desktopOpened: return "Desktop aberto"
        case .videoValidated: return "Vídeo validado"
        case .audioValidated: return "Áudio validado"
        }
    }
}
