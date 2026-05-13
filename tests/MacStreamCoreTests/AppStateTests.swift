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
