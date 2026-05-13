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
        XCTAssertEqual(appState.lastSunshineOperationMessage, "Sunshine iniciado com ownership do MacStream Host.")

        await appState.stopSunshine()

        XCTAssertEqual(appState.dashboard.sunshineStatus.state, .stopped)
        XCTAssertEqual(appState.lastSunshineOperationMessage, "Processo Sunshine owned pelo MacStream Host parado.")
    }

    @MainActor
    func testCreateDefaultSunshineConfigurationPublishesMessage() async {
        let appState = makeTestAppState()

        await appState.createDefaultSunshineConfiguration()

        XCTAssertEqual(appState.lastSunshineOperationMessage, "Configuração padrão do Sunshine gerada.")
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
    func testInstallBlackHoleReportsWaitingForInstallerCompletion() async {
        let appState = makeTestAppState()

        await appState.installBlackHole()

        XCTAssertEqual(appState.dependencyInstallProgress?.id, .blackHole)
        XCTAssertEqual(appState.dependencyInstallProgress?.stage, .waitingForUser)
        XCTAssertEqual(appState.lastDependencyInstallResult?.requiresUserCompletion, true)
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
}
