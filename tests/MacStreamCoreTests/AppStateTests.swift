// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class AppStateTests: XCTestCase {
    @MainActor
    func testRefreshBuildsDashboardAndChecklist() async {
        let appState = makeTestAppState()

        await appState.refresh()

        XCTAssertFalse(appState.setupChecklist.isEmpty)
        XCTAssertEqual(appState.dashboard.sunshineStatus.state, .stopped)
        XCTAssertEqual(appState.dashboard.blackHoleStatus, .missing)
        XCTAssertFalse(appState.dashboard.recommendedNextStep.isEmpty)
    }

    @MainActor
    func testSunshineActionsRefreshStatusAndMessage() async {
        let appState = makeTestAppState()

        await appState.startSunshine()

        XCTAssertEqual(appState.dashboard.sunshineStatus.state, .running)
        XCTAssertEqual(appState.lastSunshineOperationMessage, "Motor de vídeo iniciado.")

        await appState.stopSunshine()

        XCTAssertEqual(appState.dashboard.sunshineStatus.state, .stopped)
        XCTAssertEqual(appState.lastSunshineOperationMessage, "Motor de vídeo parado.")
    }

    @MainActor
    func testCreateDefaultSunshineConfigurationPublishesMessage() async {
        let appState = makeTestAppState()

        await appState.createDefaultSunshineConfiguration()

        XCTAssertEqual(appState.lastSunshineOperationMessage, "Configuração padrão do motor gerada.")
    }

    @MainActor
    func testDiagnosticsReportIncludesRuntimeState() async {
        let appState = makeTestAppState()

        let report = await appState.diagnosticsReport()

        XCTAssertEqual(report.settings, appState.runtimeSettings)
        XCTAssertFalse(report.audioDevices.isEmpty)
        XCTAssertEqual(report.launchAgentStatus, .notInstalled)
        XCTAssertFalse(report.dependencies.isEmpty)
        XCTAssertFalse(report.buildInfo.bundleIdentifier.isEmpty)
    }

    @MainActor
    func testRunPreflightPublishesStructuredResult() async {
        let permissions = MockPermissionManager(permissionsStatus: MacOSPermissionsStatus(checks: [
            PermissionCheck(id: .screenRecording, status: .granted, detail: "OK"),
            PermissionCheck(id: .microphone, status: .granted, detail: "OK"),
            PermissionCheck(id: .localNetwork, status: .granted, detail: "OK"),
            PermissionCheck(id: .accessibility, status: .granted, detail: "OK")
        ]))
        let appState = makeTestAppState(
            blackHole: MockBlackHoleManager(status: .installed),
            permissions: permissions
        )

        await appState.runPreflight(startAfterValidation: true, overwriteConfig: true)

        let result = appState.lastPreflightResult
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.configurationWrites.count, 2)
        XCTAssertEqual(result?.dashboard.sunshineStatus.state, .running)
        XCTAssertEqual(result?.operationalState, .running)
        XCTAssertEqual(result?.startedSunshine, true)
        XCTAssertEqual(appState.lastOperationMessage, "Preflight concluído.")
    }

    @MainActor
    func testOnboardingShowsDependencyBlockers() async {
        let appState = makeTestAppState(
            sunshine: MockSunshineManager(currentStatus: SunshineStatus(state: .notInstalled)),
            blackHole: MockBlackHoleManager(status: .missing)
        )

        await appState.refresh()

        XCTAssertEqual(appState.operationalState, .needsDependency)
        XCTAssertEqual(appState.dependencyStatuses.first(where: { $0.id == .sunshine })?.status, .fail)
        XCTAssertEqual(appState.onboardingSteps.first(where: { $0.id == .sunshine })?.state, .failed)
        XCTAssertEqual(Set(appState.onboardingSteps.map(\.id)), Set(OnboardingStepID.allCases))
    }

    @MainActor
    func testMoonlightChecklistCanCompletePairingStep() async {
        let appState = makeTestAppState()
        await appState.refresh()

        for item in MoonlightChecklistItemID.allCases {
            appState.markMoonlightChecklistItemComplete(item)
        }

        XCTAssertEqual(
            appState.onboardingSteps.first(where: { $0.id == .moonlightPairing })?.state,
            .passed
        )
    }

    @MainActor
    func testInstallManagedSunshinePersistsManagedBinaryPath() async {
        let settingsManager = MockSettingsManager()
        let appState = makeTestAppState(settingsManager: settingsManager)

        await appState.installManagedSunshine()

        XCTAssertEqual(appState.runtimeSettings.sunshineBinaryPath, "/tmp/Sunshine.app/Contents/MacOS/sunshine")
        XCTAssertEqual(settingsManager.settings.sunshineBinaryPath, "/tmp/Sunshine.app/Contents/MacOS/sunshine")
        XCTAssertEqual(appState.dependencyInstallProgress?.stage, .completed)
        XCTAssertEqual(appState.lastDependencyInstallResult?.dependencyID, .sunshine)
    }

    @MainActor
    func testSavingSettingsRebuildsRuntimeSettings() async {
        let settingsManager = MockSettingsManager()
        let appState = makeTestAppState(settingsManager: settingsManager)

        await appState.saveSettings(
            sunshineBinaryPath: "/tmp/sunshine",
            configDirectoryPath: "/tmp/macstream-config",
            logDirectoryPath: "/tmp/macstream-logs",
            audioCaptureMode: .nativeSystemAudio
        )

        XCTAssertEqual(appState.runtimeSettings.sunshineBinaryPath, "/tmp/sunshine")
        XCTAssertEqual(appState.runtimeSettings.configDirectoryPath, "/tmp/macstream-config")
        XCTAssertEqual(appState.runtimeSettings.audioCaptureMode, .nativeSystemAudio)
        XCTAssertEqual(settingsManager.settings.logDirectoryPath, "/tmp/macstream-logs")
    }

    @MainActor
    func testRequestMacOSPermissionsRequestsOnlyPromptableAppPermissions() async {
        let permissions = MockPermissionManager()
        let appState = makeTestAppState(permissions: permissions)

        await appState.requestMacOSPermissions()

        XCTAssertEqual(
            permissions.requestedPermissions,
            [.screenRecording, .microphone, .accessibility]
        )
        XCTAssertFalse(appState.lastPermissionRequestResults.isEmpty)
    }

    @MainActor
    func testLockHostForPrivacyInAppOverlayModeSetsFlagAndSkipsAgent() async {
        let agent = MockAgentManager()
        let remoteWork = MockRemoteWorkSessionManager()
        var settings = MacStreamHostSettings.defaults()
        settings.hostPrivacyPolicy = HostPrivacyPolicy(mode: .appOverlay)
        let appState = makeTestAppState(
            runtimeSettings: settings,
            agent: agent,
            remoteWork: remoteWork
        )

        await appState.lockHostForPrivacy()

        XCTAssertTrue(appState.privacyOverlayActive)
        XCTAssertEqual(remoteWork.lockHostCallCount, 0)
        XCTAssertTrue(agent.commands.allSatisfy { $0.kind != .lockHost })
    }

    @MainActor
    func testLockHostForPrivacyInSystemSuspendModeRoutesThroughRemoteWorkManager() async {
        let remoteWork = MockRemoteWorkSessionManager()
        var settings = MacStreamHostSettings.defaults()
        settings.hostPrivacyPolicy = HostPrivacyPolicy(mode: .systemSuspend)
        let appState = makeTestAppState(
            runtimeSettings: settings,
            remoteWork: remoteWork
        )

        await appState.lockHostForPrivacy()

        XCTAssertFalse(appState.privacyOverlayActive)
        XCTAssertEqual(remoteWork.lockHostCallCount, 1)
    }

    @MainActor
    func testDismissPrivacyOverlayClearsFlag() async {
        var settings = MacStreamHostSettings.defaults()
        settings.hostPrivacyPolicy = HostPrivacyPolicy(mode: .appOverlay)
        let appState = makeTestAppState(runtimeSettings: settings)

        await appState.lockHostForPrivacy()
        XCTAssertTrue(appState.privacyOverlayActive)

        _ = appState.dismissPrivacyOverlay()

        XCTAssertFalse(appState.privacyOverlayActive)
    }

    @MainActor
    func testDismissPrivacyOverlayRejectsWrongPasswordWhenRequired() async {
        var settings = MacStreamHostSettings.defaults()
        settings.hostPrivacyPolicy = HostPrivacyPolicy(mode: .appOverlay)
        settings.appPasswordPolicy = AppPasswordPolicy(requireOnOverlayUnlock: true)
        let passwordStore = InMemoryAppPasswordStore(initial: "topsecret")
        let appState = makeTestAppState(runtimeSettings: settings, appPasswordStore: passwordStore)

        await appState.lockHostForPrivacy()
        XCTAssertTrue(appState.privacyOverlayActive)

        let rejected = appState.dismissPrivacyOverlay(passwordCandidate: "wrong")
        XCTAssertFalse(rejected)
        XCTAssertTrue(appState.privacyOverlayActive)

        let accepted = appState.dismissPrivacyOverlay(passwordCandidate: "topsecret")
        XCTAssertTrue(accepted)
        XCTAssertFalse(appState.privacyOverlayActive)
    }

    @MainActor
    func testResetSunshineScreenRecordingGrantInvokesTccutilForBothBundleIds() async {
        // After the flatten, the parent bundle id is the only one that
        // matters at runtime, but older installs may have stamped the legacy
        // engine sub-bundle id and the upstream LizardByte identifier into
        // TCC. Reset all three to cover every upgrade path.
        let runner = CapturingCommandRunner()
        let permissions = MockPermissionManager()
        let appState = makeTestAppState(permissions: permissions, commandRunner: runner)

        await appState.resetSunshineScreenRecordingGrant()

        let tccCalls = runner.invocations.filter { $0.executablePath == "/usr/bin/tccutil" }
        XCTAssertEqual(tccCalls.count, 3)
        XCTAssertEqual(tccCalls[0].arguments, ["reset", "ScreenCapture", "org.macstream.host"])
        XCTAssertEqual(tccCalls[1].arguments, ["reset", "ScreenCapture", "org.macstream.host.engine.sunshine"])
        XCTAssertEqual(tccCalls[2].arguments, ["reset", "ScreenCapture", "dev.lizardbyte.app.Sunshine"])
        XCTAssertEqual(permissions.openedSettings, [.screenRecording])
    }

    @MainActor
    func testSetAppPasswordUpdatesIsAppPasswordSet() {
        let passwordStore = InMemoryAppPasswordStore()
        let appState = makeTestAppState(appPasswordStore: passwordStore)
        XCTAssertFalse(appState.isAppPasswordSet)

        appState.setAppPassword("hello123")
        XCTAssertTrue(appState.isAppPasswordSet)
        XCTAssertTrue(passwordStore.verify("hello123"))

        appState.clearAppPassword()
        XCTAssertFalse(appState.isAppPasswordSet)
    }

    @MainActor
    func testRouteSystemAudioReportsRoutedWhenBlackHoleAvailable() async {
        let speakers = AudioDevice(id: "1", name: "Alto-falantes do Mac", channels: 2, isInput: false, isOutput: true, status: .available)
        let blackHole = AudioDevice(id: "2", name: "BlackHole 2ch", channels: 2, isInput: true, isOutput: true, status: .available)
        let mockAudio = MockAudioDeviceManager(devices: [speakers, blackHole], currentOutputID: speakers.id)
        let appState = makeTestAppState(audio: mockAudio)

        let result = await appState.routeSystemAudioToMacStream()

        if case .routed(let previous, let new) = result {
            XCTAssertEqual(previous?.name, "Alto-falantes do Mac")
            XCTAssertEqual(new.name, "BlackHole 2ch")
        } else {
            XCTFail("Expected .routed, got \(result)")
        }
        XCTAssertEqual(appState.lastOperationMessage,
                       "Saída do sistema agora é BlackHole 2ch (anterior: Alto-falantes do Mac).")
        XCTAssertEqual(mockAudio.currentOutputID, blackHole.id)
    }

    @MainActor
    func testRouteSystemAudioReportsAlreadyRoutedWhenOutputIsBlackHole() async {
        let blackHole = AudioDevice(id: "2", name: "BlackHole 2ch", channels: 2, isInput: true, isOutput: true, status: .available)
        let mockAudio = MockAudioDeviceManager(devices: [blackHole], currentOutputID: blackHole.id)
        let appState = makeTestAppState(audio: mockAudio)

        let result = await appState.routeSystemAudioToMacStream()

        XCTAssertEqual(result, .alreadyRouted(currentDevice: blackHole))
        XCTAssertEqual(appState.lastOperationMessage,
                       "Saída do sistema já está em BlackHole 2ch.")
    }

    @MainActor
    func testRouteSystemAudioReportsUnavailableWhenBlackHoleMissing() async {
        let speakers = AudioDevice(id: "1", name: "Alto-falantes do Mac", channels: 2, isInput: false, isOutput: true, status: .available)
        let mockAudio = MockAudioDeviceManager(devices: [speakers], currentOutputID: speakers.id)
        let appState = makeTestAppState(audio: mockAudio)

        let result = await appState.routeSystemAudioToMacStream()

        XCTAssertEqual(result, .targetDeviceUnavailable)
        XCTAssertEqual(appState.lastOperationMessage,
                       "Roteamento de áudio do MacStream não está disponível. Conclua a instalação do mecanismo de áudio em Components.")
    }

    @MainActor
    func testRestoreSystemAudioRollsBackToPreviousDevice() async {
        let speakers = AudioDevice(id: "1", name: "Alto-falantes do Mac", channels: 2, isInput: false, isOutput: true, status: .available)
        let blackHole = AudioDevice(id: "2", name: "BlackHole 2ch", channels: 2, isInput: true, isOutput: true, status: .available)
        let mockAudio = MockAudioDeviceManager(devices: [speakers, blackHole], currentOutputID: blackHole.id)
        let appState = makeTestAppState(audio: mockAudio)

        let result = await appState.restoreSystemAudioOutput(to: speakers.id)

        if case .routed(_, let new) = result {
            XCTAssertEqual(new.name, "Alto-falantes do Mac")
        } else {
            XCTFail("Expected .routed, got \(result)")
        }
        XCTAssertEqual(appState.lastOperationMessage,
                       "Saída do sistema restaurada para Alto-falantes do Mac.")
        XCTAssertEqual(mockAudio.currentOutputID, speakers.id)
    }
}
