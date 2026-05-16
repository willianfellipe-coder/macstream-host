// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

public enum PrivilegedInstallerError: Error, LocalizedError {
    case packageMissing(URL)
    case authorizationCreateFailed(OSStatus)
    case authorizationCopyRightsFailed(OSStatus)
    case executeWithPrivilegesFailed(OSStatus)
    case installerExitCode(Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .packageMissing(let url):
            return "Pacote BlackHole não encontrado em \(url.path)."
        case .authorizationCreateFailed(let status):
            return "Não foi possível criar a autorização para instalar o driver (OSStatus \(status))."
        case .authorizationCopyRightsFailed(let status):
            return "Você cancelou ou negou a autorização para instalar o driver (OSStatus \(status))."
        case .executeWithPrivilegesFailed(let status):
            return "AuthorizationExecuteWithPrivileges falhou (OSStatus \(status))."
        case .installerExitCode(let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.isEmpty ? "" : " — " + String(trimmed.prefix(280))
            return "installer retornou código \(code)\(preview)"
        }
    }
}

/// Runs `/usr/sbin/installer -pkg <path> -target /` as root via the
/// `AuthorizationExecuteWithPrivileges` API. macOS shows the standard system
/// admin password prompt; no Installer.app window appears, and the user only
/// types their password once for the whole install.
///
/// `AuthorizationExecuteWithPrivileges` is officially deprecated (since
/// macOS 10.7) in favor of `SMJobBless` / privileged helper tools that
/// require Apple Developer ID for proper sandboxing. We don't have a
/// Developer ID in this open-source project and `SMJobBless` won't load a
/// privileged helper signed ad-hoc, so this API remains the only realistic
/// path for a once-and-done driver install. The function still works on
/// macOS 26.5 (Tahoe), with the same UX as before — a single password
/// prompt presented by SecurityAgent.
public class PrivilegedInstaller {
    private let installerPath: String

    public init(installerPath: String = "/usr/sbin/installer") {
        self.installerPath = installerPath
    }

    /// Installs the given .pkg with admin privileges. Blocks the calling
    /// thread until installer finishes. Returns installer's combined stdout/
    /// stderr so the caller can show it in logs.
    open func installPackage(at packageURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            throw PrivilegedInstallerError.packageMissing(packageURL)
        }

        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard createStatus == errAuthorizationSuccess, let auth = authRef else {
            throw PrivilegedInstallerError.authorizationCreateFailed(createStatus)
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        // Ask for the right to spawn /usr/sbin/installer; macOS prompts.
        var rightName = kAuthorizationRightExecute.withCString { $0 }
        var item = AuthorizationItem(
            name: rightName,
            valueLength: 0,
            value: nil,
            flags: 0
        )
        let copyStatus = withUnsafeMutablePointer(to: &item) { itemPointer -> OSStatus in
            var rights = AuthorizationRights(count: 1, items: itemPointer)
            let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
            return AuthorizationCopyRights(auth, &rights, nil, flags, nil)
        }
        _ = rightName // keep the C-string buffer alive until AuthorizationCopyRights returns
        guard copyStatus == errAuthorizationSuccess else {
            throw PrivilegedInstallerError.authorizationCopyRightsFailed(copyStatus)
        }

        // Build argv: installer -pkg <path> -target /
        let arguments: [String] = ["-pkg", packageURL.path, "-target", "/"]
        var cArgs: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { if let p = $0 { free(p) } } }

        var pipe: UnsafeMutablePointer<FILE>?
        let runStatus = installerPath.withCString { (cInstallerPath) -> OSStatus in
            cArgs.withUnsafeMutableBufferPointer { buffer -> OSStatus in
                guard let basePointer = buffer.baseAddress else {
                    return errAuthorizationInternal
                }
                return _executeWithPrivilegesShim(
                    auth,
                    cInstallerPath,
                    basePointer,
                    &pipe
                )
            }
        }
        guard runStatus == errAuthorizationSuccess else {
            throw PrivilegedInstallerError.executeWithPrivilegesFailed(runStatus)
        }

        // Drain stdout from the pipe, then wait for installer to exit.
        var output = ""
        if let pipe {
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while fgets(buffer, 4096, pipe) != nil {
                output += String(cString: buffer)
            }
            fclose(pipe)
        }

        // AuthorizationExecuteWithPrivileges spawns the tool detached; we
        // can't waitpid on its PID directly. The pipe close above blocks
        // until installer's stdout is closed, which happens when it exits.
        // installer prints "installer: The install was successful." on
        // success and a non-empty error on failure, so parse output:
        let lowercased = output.lowercased()
        let succeeded = lowercased.contains("the install was successful")
            || lowercased.contains("installation was successful")
        if !succeeded {
            throw PrivilegedInstallerError.installerExitCode(1, output: output)
        }
        return output
    }
}

// MARK: - Bridging shim around AuthorizationExecuteWithPrivileges

// AuthorizationExecuteWithPrivileges is deprecated in the public SDK and the
// Swift overlay refuses to import it without a deprecation diagnostic. The
// shim below uses @_silgen_name to call the underlying symbol directly so
// the call site stays warning-free even when CSecurity later marks the
// declaration unavailable.
@_silgen_name("AuthorizationExecuteWithPrivileges")
private func _AuthorizationExecuteWithPrivileges(
    _ authorization: AuthorizationRef,
    _ pathToTool: UnsafePointer<CChar>,
    _ options: AuthorizationFlags,
    _ arguments: UnsafePointer<UnsafeMutablePointer<CChar>?>,
    _ communicationsPipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
) -> OSStatus

private func _executeWithPrivilegesShim(
    _ authorization: AuthorizationRef,
    _ pathToTool: UnsafePointer<CChar>,
    _ arguments: UnsafePointer<UnsafeMutablePointer<CChar>?>,
    _ communicationsPipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
) -> OSStatus {
    return _AuthorizationExecuteWithPrivileges(
        authorization,
        pathToTool,
        [],
        arguments,
        communicationsPipe
    )
}
