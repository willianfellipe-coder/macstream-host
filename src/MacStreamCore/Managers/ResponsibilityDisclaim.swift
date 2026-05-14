// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import Darwin

// MARK: - Private Apple API
//
// `responsibility_spawnattrs_setdisclaim` is exported by libsystem_secinit.dylib (part of
// libSystem, always linked). It tells TCC and other privacy subsystems to attribute the
// spawned child's permission checks to the *parent* process — the parent is the
// "responsible" process. This is exactly what Chromium, Electron, and Slack use for
// their helper executables so that the helper inherits the parent's TCC grants.
//
// The function is undocumented in the public Apple SDK but has been stable since macOS
// 10.14 (Mojave). Reference: https://chromium.googlesource.com/chromium/src/+/main/sandbox/mac/
@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>,
    _ disclaim: Int32
) -> Int32

// MARK: - Disclaimed spawn

public enum DisclaimedSpawnError: Error, LocalizedError {
    case posixSpawnAttrInitFailed(Int32)
    case disclaimFailed(Int32)
    case fileActionsInitFailed(Int32)
    case fileActionsAddFailed(Int32)
    case spawnFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .posixSpawnAttrInitFailed(let code):
            return "posix_spawnattr_init failed (\(code))"
        case .disclaimFailed(let code):
            return "responsibility_spawnattrs_setdisclaim failed (\(code))"
        case .fileActionsInitFailed(let code):
            return "posix_spawn_file_actions_init failed (\(code))"
        case .fileActionsAddFailed(let code):
            return "posix_spawn_file_actions_adddup2 failed (\(code))"
        case .spawnFailed(let code, let message):
            return "posix_spawn failed (\(code)): \(message)"
        }
    }
}

public struct DisclaimedSpawnConfig {
    public let executablePath: String
    public let arguments: [String]
    public let stdoutFD: Int32
    public let stderrFD: Int32
    public let environment: [String: String]

    public init(
        executablePath: String,
        arguments: [String],
        stdoutFD: Int32,
        stderrFD: Int32,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.stdoutFD = stdoutFD
        self.stderrFD = stderrFD
        self.environment = environment
    }
}

/// Spawn a child process that disclaims responsibility back to the parent.
///
/// The child's TCC permission checks (Screen Recording, Microphone, etc.) will be
/// attributed to the parent process's bundle. Granting permission to the parent app
/// in System Settings is enough for the child to use the protected APIs.
public func spawnDisclaimedChild(_ config: DisclaimedSpawnConfig) throws -> pid_t {
    var attrs: posix_spawnattr_t?
    let attrInit = posix_spawnattr_init(&attrs)
    guard attrInit == 0 else {
        throw DisclaimedSpawnError.posixSpawnAttrInitFailed(attrInit)
    }
    defer { posix_spawnattr_destroy(&attrs) }

    let disclaimResult = responsibility_spawnattrs_setdisclaim(&attrs, 1)
    guard disclaimResult == 0 else {
        throw DisclaimedSpawnError.disclaimFailed(disclaimResult)
    }

    var fileActions: posix_spawn_file_actions_t?
    let faInit = posix_spawn_file_actions_init(&fileActions)
    guard faInit == 0 else {
        throw DisclaimedSpawnError.fileActionsInitFailed(faInit)
    }
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    let stdoutDup = posix_spawn_file_actions_adddup2(&fileActions, config.stdoutFD, STDOUT_FILENO)
    guard stdoutDup == 0 else {
        throw DisclaimedSpawnError.fileActionsAddFailed(stdoutDup)
    }
    let stderrDup = posix_spawn_file_actions_adddup2(&fileActions, config.stderrFD, STDERR_FILENO)
    guard stderrDup == 0 else {
        throw DisclaimedSpawnError.fileActionsAddFailed(stderrDup)
    }

    let argStrings: [String] = [config.executablePath] + config.arguments
    var argv: [UnsafeMutablePointer<CChar>?] = argStrings.map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { if let ptr = $0 { free(ptr) } } }

    let envStrings: [String] = config.environment.map { "\($0.key)=\($0.value)" }
    var envp: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) }
    envp.append(nil)
    defer { envp.forEach { if let ptr = $0 { free(ptr) } } }

    var pid: pid_t = 0
    let spawnResult = posix_spawn(
        &pid,
        config.executablePath,
        &fileActions,
        &attrs,
        argv,
        envp
    )
    guard spawnResult == 0 else {
        let message = String(cString: strerror(spawnResult))
        throw DisclaimedSpawnError.spawnFailed(spawnResult, message)
    }

    return pid
}
#endif
