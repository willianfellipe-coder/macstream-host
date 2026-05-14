// SPDX-License-Identifier: GPL-3.0-or-later

import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#endif

public enum PermissionManagerError: Error, LocalizedError {
    case settingsURLUnavailable(MacPermission)
    case settingsOpenFailed(MacPermission)

    public var errorDescription: String? {
        switch self {
        case .settingsURLUnavailable(let permission):
            return "No Settings URL is configured for \(permission.displayName)."
        case .settingsOpenFailed(let permission):
            return "Failed to open Settings for \(permission.displayName)."
        }
    }
}

public protocol PermissionStatusProviding {
    func status(for permission: MacPermission) -> PermissionStatus
}

public protocol PermissionPrompting {
    func requestPermission(_ permission: MacPermission) async -> Bool
}

public protocol PermissionSettingsOpening {
    func openSettings(for permission: MacPermission) throws
}

public final class DefaultPermissionManager: PermissionManaging {
    private let statusProvider: PermissionStatusProviding
    private let prompter: PermissionPrompting
    private let settingsOpener: PermissionSettingsOpening

    public init(
        statusProvider: PermissionStatusProviding = SystemPermissionStatusProvider(),
        prompter: PermissionPrompting = SystemPermissionPrompter(),
        settingsOpener: PermissionSettingsOpening = SystemSettingsPermissionOpener()
    ) {
        self.statusProvider = statusProvider
        self.prompter = prompter
        self.settingsOpener = settingsOpener
    }

    public func currentStatus() async -> MacOSPermissionsStatus {
        MacOSPermissionsStatus(
            checks: MacPermission.allCases.map { permission in
                let status = statusProvider.status(for: permission)
                return PermissionCheck(
                    id: permission,
                    status: status,
                    detail: detail(for: permission, status: status)
                )
            }
        )
    }

    public func requestPermissions(_ permissions: [MacPermission]) async -> [PermissionRequestResult] {
        var results: [PermissionRequestResult] = []

        for permission in permissions {
            let before = statusProvider.status(for: permission)
            let shouldPrompt = before != .granted
            let promptSucceeded = shouldPrompt ? await prompter.requestPermission(permission) : true
            let after = statusProvider.status(for: permission)
            results.append(
                PermissionRequestResult(
                    id: permission,
                    statusBefore: before,
                    statusAfter: after,
                    promptAttempted: shouldPrompt,
                    detail: requestDetail(
                        for: permission,
                        statusBefore: before,
                        statusAfter: after,
                        promptSucceeded: promptSucceeded
                    )
                )
            )
        }

        return results
    }

    public func openSettings(for permission: MacPermission) async throws {
        try settingsOpener.openSettings(for: permission)
    }

    private func requestDetail(
        for permission: MacPermission,
        statusBefore: PermissionStatus,
        statusAfter: PermissionStatus,
        promptSucceeded: Bool
    ) -> String {
        if statusAfter == .granted {
            return "\(permission.displayName) concedida."
        }

        if permission == .localNetwork {
            return "Rede local precisa ser validada por teste de conexão; macOS não expõe prompt/status direto confiável."
        }

        if statusBefore == .denied || statusAfter == .denied {
            return "\(permission.displayName) foi negada; abra Ajustes do Sistema para permitir manualmente."
        }

        if promptSucceeded == false {
            return "\(permission.displayName) não foi concedida pelo prompt do macOS; abra Ajustes do Sistema."
        }

        return "\(permission.displayName) ainda precisa de validação nos Ajustes do Sistema."
    }

    private func detail(for permission: MacPermission, status: PermissionStatus) -> String {
        switch permission {
        case .screenRecording:
            switch status {
            case .granted:
                return "Gravação de tela aparenta estar concedida para este processo."
            case .requiresValidation:
                return "macOS não expõe distinção completa entre ausente e negada; validar nos Ajustes ou com teste prático do Sunshine."
            default:
                return "Necessária para capturar a tela do Mac."
            }
        case .microphone:
            switch status {
            case .granted:
                return "Microfone concedido para rotas de áudio que dependem de captura."
            case .denied:
                return "Microfone negado; abrir Ajustes antes de usar rotas de áudio que dependam dessa permissão."
            case .notDetermined:
                return "Microfone ainda não foi solicitado por este app."
            default:
                return "Validar se a rota de áudio escolhida exige permissão de microfone."
            }
        case .localNetwork:
            return "macOS não oferece uma leitura direta confiável; validar por descoberta Moonlight ou teste de conexão local."
        case .accessibility:
            switch status {
            case .granted:
                // Caveat: AXIsProcessTrusted reports the PARENT process. The
                // helper engine binary (`MacStreamEngine`) is a sibling Mach-O
                // inside the bundle and macOS treats it as a separate
                // accessibility subject. Mouse forwarding from Moonlight tends
                // to work via the parent grant, but KEYBOARD events injected
                // by the engine require the engine to be in the list too.
                return "Acessibilidade concedida ao MacStream Host. Para teclado via Moonlight, adicione também '/Applications/MacStream Host.app/Contents/MacOS/MacStreamEngine' na lista de Acessibilidade."
            default:
                return "Acessibilidade obrigatória para o Moonlight controlar teclado e mouse do Mac. Abra Ajustes do Sistema e ative o MacStream Host."
            }
        }
    }
}

public final class SystemPermissionPrompter: PermissionPrompting {
    public init() {}

    public func requestPermission(_ permission: MacPermission) async -> Bool {
        switch permission {
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        case .microphone:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        case .localNetwork:
            return false
        }
    }
}

public final class SystemPermissionStatusProvider: PermissionStatusProviding {
    public init() {}

    public func status(for permission: MacPermission) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return screenRecordingStatus()
        case .microphone:
            return microphoneStatus()
        case .localNetwork:
            return .requiresValidation
        case .accessibility:
            return accessibilityStatus()
        }
    }

    private func screenRecordingStatus() -> PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .requiresValidation
    }

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    private func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .requiresValidation
    }
}

public final class SystemSettingsPermissionOpener: PermissionSettingsOpening {
    public init() {}

    public func openSettings(for permission: MacPermission) throws {
        guard let url = settingsURL(for: permission) else {
            throw PermissionManagerError.settingsURLUnavailable(permission)
        }

        #if os(macOS)
        guard NSWorkspace.shared.open(url) else {
            throw PermissionManagerError.settingsOpenFailed(permission)
        }
        #else
        throw PermissionManagerError.settingsOpenFailed(permission)
        #endif
    }

    private func settingsURL(for permission: MacPermission) -> URL? {
        let pane: String

        switch permission {
        case .screenRecording:
            pane = "Privacy_ScreenCapture"
        case .microphone:
            pane = "Privacy_Microphone"
        case .localNetwork:
            pane = "Privacy_LocalNetwork"
        case .accessibility:
            pane = "Privacy_Accessibility"
        }

        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}
