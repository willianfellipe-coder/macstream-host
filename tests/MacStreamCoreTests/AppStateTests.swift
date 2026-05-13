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
}
