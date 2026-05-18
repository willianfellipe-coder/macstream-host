// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import ServiceManagement
#endif

/// Registers (or unregisters) the MacStream Host app as a macOS login item
/// using `SMAppService.mainApp`. When registered, macOS auto-launches the
/// app on user login. The app inspects `MacStreamHostSettings.startInBackground`
/// and, when true, sets `NSApplicationActivationPolicy.accessory` so it
/// runs as a tray-only background process (no Dock icon, no main window).
///
/// This is the macOS 13+ modern API. Older Login Items via
/// `SMLoginItemSetEnabled` would also work but require a separate helper
/// bundle and are harder to debug. `SMAppService.mainApp` requires only
/// that the app is properly codesigned (any identity — the local
/// MacStream Local Dev cert is enough on the user's own machine).
public protocol LoginItemManaging {
    var isRegistered: Bool { get }
    func setRegistered(_ enabled: Bool) throws
}

public enum LoginItemError: Error, LocalizedError {
    case registerFailed(String)
    case unregisterFailed(String)
    case notSupportedOnThisPlatform

    public var errorDescription: String? {
        switch self {
        case .registerFailed(let message):
            return "Não foi possível registrar como Login Item: \(message)"
        case .unregisterFailed(let message):
            return "Não foi possível remover o Login Item: \(message)"
        case .notSupportedOnThisPlatform:
            return "Login Items só são suportados no macOS."
        }
    }
}

public final class DefaultLoginItemService: LoginItemManaging {
    public init() {}

    public var isRegistered: Bool {
        #if os(macOS)
        return SMAppService.mainApp.status == .enabled
        #else
        return false
        #endif
    }

    public func setRegistered(_ enabled: Bool) throws {
        #if os(macOS)
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return }
                try service.register()
            } else {
                if service.status == .notRegistered || service.status == .notFound { return }
                try service.unregister()
            }
        } catch {
            if enabled {
                throw LoginItemError.registerFailed(error.localizedDescription)
            } else {
                throw LoginItemError.unregisterFailed(error.localizedDescription)
            }
        }
        #else
        throw LoginItemError.notSupportedOnThisPlatform
        #endif
    }
}
