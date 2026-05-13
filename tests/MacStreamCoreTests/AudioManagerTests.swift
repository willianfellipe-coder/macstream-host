// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class AudioManagerTests: XCTestCase {
    func testBlackHoleManagerDetectsBlackHole2chFromAudioDevices() async {
        let manager = DefaultBlackHoleManager(
            audioDeviceProvider: FakeAudioDeviceProvider(devices: [
                AudioDevice(id: "1", name: "Built-in Output", channels: 2, isInput: false, isOutput: true, status: .available),
                AudioDevice(id: "2", name: "BlackHole 2ch", channels: 2, isInput: true, isOutput: true, status: .available)
            ]),
            halDriverPaths: []
        )

        let status = await manager.installationStatus()

        XCTAssertEqual(status, .installed)
    }

    func testBlackHoleManagerFallsBackToHALDriverPath() async throws {
        let directory = try makeTemporaryDirectory()
        let driverURL = directory.appendingPathComponent("BlackHole2ch.driver")
        try FileManager.default.createDirectory(at: driverURL, withIntermediateDirectories: true)

        let manager = DefaultBlackHoleManager(
            audioDeviceProvider: FakeAudioDeviceProvider(devices: []),
            halDriverPaths: [driverURL.path]
        )

        let status = await manager.installationStatus()

        XCTAssertEqual(status, .installed)
    }

    func testBlackHoleManagerReportsMissingWithoutDeviceOrDriverPath() async {
        let manager = DefaultBlackHoleManager(
            audioDeviceProvider: FakeAudioDeviceProvider(devices: [
                AudioDevice(id: "1", name: "Built-in Output", channels: 2, isInput: false, isOutput: true, status: .available)
            ]),
            halDriverPaths: []
        )

        let status = await manager.installationStatus()

        XCTAssertEqual(status, .missing)
    }

    func testAudioDeviceManagerPrefersBlackHoleWhenPresent() async {
        let manager = DefaultAudioDeviceManager(
            audioDeviceProvider: FakeAudioDeviceProvider(devices: [
                AudioDevice(id: "2", name: "BlackHole 2ch", channels: 2, isInput: true, isOutput: true, status: .available)
            ])
        )

        let mode = await manager.preferredCaptureMode()
        let status = await manager.validateAudioRoute()

        XCTAssertEqual(mode, .blackHole2ch)
        XCTAssertEqual(status, .pass)
    }

    func testAudioDeviceManagerWarnsWhenOnlyGeneralAudioDevicesExist() async {
        let manager = DefaultAudioDeviceManager(
            audioDeviceProvider: FakeAudioDeviceProvider(devices: [
                AudioDevice(id: "1", name: "Built-in Output", channels: 2, isInput: false, isOutput: true, status: .available)
            ])
        )

        let mode = await manager.preferredCaptureMode()
        let status = await manager.validateAudioRoute()

        XCTAssertEqual(mode, .nativeSystemAudio)
        XCTAssertEqual(status, .warning)
    }

    func testAudioDeviceManagerFailsWhenNoDevicesExist() async {
        let manager = DefaultAudioDeviceManager(audioDeviceProvider: FakeAudioDeviceProvider(devices: []))

        let status = await manager.validateAudioRoute()

        XCTAssertEqual(status, .fail)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostAudioTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private struct FakeAudioDeviceProvider: AudioDeviceProviding {
    let devices: [AudioDevice]

    func audioDevices() throws -> [AudioDevice] {
        devices
    }
}
