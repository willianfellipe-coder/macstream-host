// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

public protocol DependencyArtifactDownloading {
    func download(from url: URL, to destinationURL: URL) async throws
}

public final class URLSessionDependencyArtifactDownloader: DependencyArtifactDownloading {
    public init() {}

    public func download(from url: URL, to destinationURL: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw DependencyInstallerError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
}

public enum DependencyInstallerError: LocalizedError, Equatable {
    case unsupportedArchitecture(String)
    case missingArtifact(ManagedDependencyID)
    case checksumMismatch(expected: String, actual: String)
    case commandFailed(String)
    case applicationNotFound(String)
    case executableNotFound(String)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture(let architecture):
            return "Arquitetura não suportada para instalação gerenciada: \(architecture)."
        case .missingArtifact(let dependencyID):
            return "Artefato não configurado para \(dependencyID.displayName)."
        case .checksumMismatch(let expected, let actual):
            return "Checksum inválido. Esperado \(expected), recebido \(actual)."
        case .commandFailed(let message):
            return message
        case .applicationNotFound(let path):
            return "Sunshine.app não encontrado no volume montado em \(path)."
        case .executableNotFound(let path):
            return "Executável do Sunshine não encontrado em \(path)."
        case .downloadFailed(let message):
            return "Download falhou: \(message)"
        }
    }
}

public final class DefaultDependencyInstallerManager: DependencyInstalling {
    public let artifacts: [DependencyArtifact]

    private let settings: MacStreamHostSettings
    private let fileManager: FileManager
    private let commandRunner: CommandRunning
    private let downloader: DependencyArtifactDownloading
    private let dependenciesDirectory: URL
    private let privilegedInstallerFactory: () -> PrivilegedInstaller
    private let embeddedBlackHoleLookup: () -> URL?
    private let blackHoleDriverPath: String

    public init(
        settings: MacStreamHostSettings,
        artifacts: [DependencyArtifact] = DependencyManifest.defaultArtifacts(),
        fileManager: FileManager = .default,
        commandRunner: CommandRunning = ProcessCommandRunner(),
        downloader: DependencyArtifactDownloading = URLSessionDependencyArtifactDownloader(),
        privilegedInstallerFactory: @escaping () -> PrivilegedInstaller = { PrivilegedInstaller() },
        embeddedBlackHoleLookup: @escaping () -> URL? = {
            Bundle.main.url(
                forResource: "BlackHole2ch",
                withExtension: "pkg",
                subdirectory: "dependencies"
            )
        },
        blackHoleDriverPath: String = "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
    ) {
        self.settings = settings.normalized()
        self.artifacts = artifacts
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.downloader = downloader
        self.dependenciesDirectory = settings.normalized().configDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("Dependencies", isDirectory: true)
        self.privilegedInstallerFactory = privilegedInstallerFactory
        self.embeddedBlackHoleLookup = embeddedBlackHoleLookup
        self.blackHoleDriverPath = blackHoleDriverPath
    }

    public func artifact(for dependencyID: ManagedDependencyID) -> DependencyArtifact? {
        artifacts.first { $0.id == dependencyID }
    }

    public func installManagedSunshine() async throws -> DependencyInstallResult {
        let artifact = try requiredArtifact(.sunshine)
        let downloadedURL = try await downloadAndVerify(artifact)
        let appDirectory = dependenciesDirectory.appendingPathComponent("Sunshine", isDirectory: true)
        let destinationAppURL = appDirectory.appendingPathComponent("Sunshine.app", isDirectory: true)
        let mountURL = dependenciesDirectory
            .appendingPathComponent("Mounts", isDirectory: true)
            .appendingPathComponent("Sunshine-\(artifact.version)", isDirectory: true)

        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mountURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: mountURL.path) {
            try fileManager.removeItem(at: mountURL)
        }
        try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)

        let attachResult = await commandRunner.run(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["attach", downloadedURL.path, "-mountpoint", mountURL.path, "-nobrowse", "-quiet"],
            timeout: 90
        )

        guard attachResult.exitCode == 0 else {
            throw DependencyInstallerError.commandFailed(attachResult.standardError)
        }

        do {
            let sourceAppURL = try findApplication(named: "Sunshine.app", under: mountURL)

            if fileManager.fileExists(atPath: destinationAppURL.path) {
                try fileManager.removeItem(at: destinationAppURL)
            }
            try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)

            let binaryURL = try findSunshineExecutable(in: destinationAppURL)
            let result = DependencyInstallResult(
                dependencyID: .sunshine,
                artifact: artifact,
                downloadedPath: downloadedURL.path,
                installedPath: destinationAppURL.path,
                installedBinaryPath: binaryURL.path,
                requiresUserCompletion: false,
                message: "Sunshine \(artifact.version) instalado em modo gerenciado."
            )
            _ = await detachVolume(at: mountURL)
            return result
        } catch {
            _ = await detachVolume(at: mountURL)
            throw error
        }
    }

    public func downloadAndOpenBlackHoleInstaller() async throws -> DependencyInstallResult {
        let artifact = try requiredArtifact(.blackHole)
        let downloadedURL = try await downloadAndVerify(artifact)

        let openResult = await commandRunner.run(
            executablePath: "/usr/bin/open",
            arguments: [downloadedURL.path],
            timeout: 30
        )

        guard openResult.exitCode == 0 else {
            throw DependencyInstallerError.commandFailed(openResult.standardError)
        }

        return DependencyInstallResult(
            dependencyID: .blackHole,
            artifact: artifact,
            downloadedPath: downloadedURL.path,
            requiresUserCompletion: true,
            message: "Instalador do BlackHole aberto. Conclua a instalação no Installer.app e reinicie se solicitado."
        )
    }

    public func embeddedBlackHoleInstallerURL() -> URL? {
        guard let url = embeddedBlackHoleLookup() else { return nil }
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func installEmbeddedBlackHole() async throws -> DependencyInstallResult {
        let artifact = try requiredArtifact(.blackHole)

        // If the driver is already installed at the expected HAL plugin
        // path, skip the privileged install entirely. The CoreAudio device
        // shows up once the daemon notices the bundle.
        if fileManager.fileExists(atPath: blackHoleDriverPath) {
            return DependencyInstallResult(
                dependencyID: .blackHole,
                artifact: artifact,
                downloadedPath: blackHoleDriverPath,
                installedPath: blackHoleDriverPath,
                installedBinaryPath: nil,
                requiresUserCompletion: false,
                message: "Roteamento de áudio já está instalado em \(blackHoleDriverPath)."
            )
        }

        // No embedded .pkg means the app was built without
        // ./scripts/fetch_blackhole.sh having staged the artifact. Fall
        // back to the legacy download + Installer.app flow so the user
        // doesn't get stuck.
        guard let embeddedURL = embeddedBlackHoleInstallerURL() else {
            return try await downloadAndOpenBlackHoleInstaller()
        }

        let installer = privilegedInstallerFactory()
        do {
            _ = try installer.installPackage(at: embeddedURL)
        } catch {
            throw DependencyInstallerError.commandFailed(
                "Não foi possível instalar o roteamento de áudio embarcado: \(error.localizedDescription)"
            )
        }

        return DependencyInstallResult(
            dependencyID: .blackHole,
            artifact: artifact,
            downloadedPath: embeddedURL.path,
            installedPath: blackHoleDriverPath,
            installedBinaryPath: nil,
            requiresUserCompletion: false,
            message: "Roteamento de áudio do MacStream instalado. O dispositivo aparece em alguns segundos no CoreAudio."
        )
    }

    private func requiredArtifact(_ dependencyID: ManagedDependencyID) throws -> DependencyArtifact {
        guard let artifact = artifact(for: dependencyID) else {
            throw DependencyInstallerError.missingArtifact(dependencyID)
        }
        return artifact
    }

    private func downloadAndVerify(_ artifact: DependencyArtifact) async throws -> URL {
        let downloadsDirectory = dependenciesDirectory.appendingPathComponent("Downloads", isDirectory: true)
        let destinationURL = downloadsDirectory.appendingPathComponent(artifact.fileName)

        try await downloader.download(from: artifact.downloadURL, to: destinationURL)
        let actualChecksum = try sha256(for: destinationURL)
        guard actualChecksum == artifact.sha256.lowercased() else {
            throw DependencyInstallerError.checksumMismatch(
                expected: artifact.sha256.lowercased(),
                actual: actualChecksum
            )
        }

        return destinationURL
    }

    private func sha256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func findApplication(named appName: String, under rootURL: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DependencyInstallerError.applicationNotFound(rootURL.path)
        }

        for case let url as URL in enumerator where url.lastPathComponent == appName {
            return url
        }

        throw DependencyInstallerError.applicationNotFound(rootURL.path)
    }

    private func detachVolume(at mountURL: URL) async -> CommandResult {
        await commandRunner.run(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["detach", mountURL.path, "-quiet"],
            timeout: 30
        )
    }

    private func findSunshineExecutable(in appURL: URL) throws -> URL {
        let macOSDirectory = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let preferredNames = ["sunshine", "Sunshine"]

        for name in preferredNames {
            let url = macOSDirectory.appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        guard let contents = try? fileManager.contentsOfDirectory(at: macOSDirectory, includingPropertiesForKeys: nil) else {
            throw DependencyInstallerError.executableNotFound(macOSDirectory.path)
        }

        if let executable = contents.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return executable
        }

        throw DependencyInstallerError.executableNotFound(macOSDirectory.path)
    }
}

public enum DependencyManifest {
    public static func defaultArtifacts(architecture: String = currentArchitecture()) -> [DependencyArtifact] {
        [
            sunshineArtifact(architecture: architecture),
            blackHoleArtifact()
        ].compactMap { $0 }
    }

    public static func sunshineArtifact(architecture: String = currentArchitecture()) -> DependencyArtifact? {
        switch architecture {
        case "arm64", "arm64e":
            return DependencyArtifact(
                id: .sunshine,
                displayName: "Sunshine macOS arm64",
                version: "v2026.508.45922",
                downloadURL: URL(string: "https://github.com/LizardByte/Sunshine/releases/download/v2026.508.45922/Sunshine-macOS-arm64.dmg")!,
                sourceURL: URL(string: "https://github.com/LizardByte/Sunshine/releases/tag/v2026.508.45922")!,
                sha256: "8b9819f2dafcfa430b00cc08b07aa61d0ad138998d68f369bfc210e07db3eb4b",
                fileName: "Sunshine-macOS-arm64-v2026.508.45922.dmg",
                installerKind: .macOSDMGApplication,
                requiresAdministrator: false,
                requiresReboot: false,
                isPrerelease: true
            )
        case "x86_64":
            return DependencyArtifact(
                id: .sunshine,
                displayName: "Sunshine macOS x86_64",
                version: "v2026.508.45922",
                downloadURL: URL(string: "https://github.com/LizardByte/Sunshine/releases/download/v2026.508.45922/Sunshine-macOS-x86_64.dmg")!,
                sourceURL: URL(string: "https://github.com/LizardByte/Sunshine/releases/tag/v2026.508.45922")!,
                sha256: "8d1518ef938e42d04fd013057aabdf2945d6a6dd12f053943d4d47f68d17089d",
                fileName: "Sunshine-macOS-x86_64-v2026.508.45922.dmg",
                installerKind: .macOSDMGApplication,
                requiresAdministrator: false,
                requiresReboot: false,
                isPrerelease: true
            )
        default:
            return nil
        }
    }

    public static func blackHoleArtifact() -> DependencyArtifact {
        DependencyArtifact(
            id: .blackHole,
            displayName: "BlackHole 2ch",
            version: "0.6.1",
            downloadURL: URL(string: "https://existential.audio/downloads/BlackHole2ch-0.6.1.pkg")!,
            sourceURL: URL(string: "https://github.com/ExistentialAudio/BlackHole/releases/tag/v0.6.1")!,
            sha256: "c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988",
            fileName: "BlackHole2ch-0.6.1.pkg",
            installerKind: .macOSPKG,
            requiresAdministrator: true,
            requiresReboot: true,
            isPrerelease: false
        )
    }

    public static func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
