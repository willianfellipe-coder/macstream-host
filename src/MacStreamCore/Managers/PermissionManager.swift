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

public protocol PermissionSettingsOpening {
    func openSettings(for permission: MacPermission) throws
}

public final class DefaultPermissionManager: PermissionManaging {
    private let statusProvider: PermissionStatusProviding
    private let settingsOpener: PermissionSettingsOpening

    public init(
        statusProvider: PermissionStatusProviding = SystemPermissionStatusProvider(),
        settingsOpener: PermissionSettingsOpening = SystemSettingsPermissionOpener()
    ) {
        self.statusProvider = statusProvider
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

    public func openSettings(for permission: MacPermission) async throws {
        try settingsOpener.openSettings(for: permission)
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
                return "Acessibilidade concedida."
            default:
                return "Acessibilidade é desejável para entrada em alguns apps, mas não bloqueia a fundação do MVP."
            }
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
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .requiresValidation
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
