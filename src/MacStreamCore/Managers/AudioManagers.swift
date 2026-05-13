// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import Foundation

public protocol AudioDeviceProviding {
    func audioDevices() throws -> [AudioDevice]
}

public final class DefaultBlackHoleManager: BlackHoleManaging {
    private let audioDeviceProvider: AudioDeviceProviding
    private let fileManager: FileManager
    private let halDriverPaths: [String]

    public init(
        audioDeviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(),
        fileManager: FileManager = .default,
        halDriverPaths: [String]? = nil
    ) {
        self.audioDeviceProvider = audioDeviceProvider
        self.fileManager = fileManager
        self.halDriverPaths = halDriverPaths ?? Self.defaultHALDriverPaths()
    }

    public func installationStatus() async -> BlackHoleInstallationStatus {
        if let devices = try? audioDeviceProvider.audioDevices(),
           devices.contains(where: Self.isBlackHole2chDevice) {
            return .installed
        }

        if halDriverPaths.contains(where: { fileManager.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }) {
            return .installed
        }

        return .missing
    }

    public func installationGuidance() async -> String {
        "Install BlackHole 2ch manually from the official project or use native macOS audio capture after validation."
    }

    public static func isBlackHole2chDevice(_ device: AudioDevice) -> Bool {
        let normalizedName = device.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        guard normalizedName.contains("blackhole") else {
            return false
        }

        return normalizedName.contains("2ch") || device.channels == 2
    }

    private static func defaultHALDriverPaths() -> [String] {
        [
            "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver",
            "/Library/Audio/Plug-Ins/HAL/BlackHole.driver",
            "~/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver",
            "~/Library/Audio/Plug-Ins/HAL/BlackHole.driver"
        ]
    }
}

public final class DefaultAudioDeviceManager: AudioDeviceManaging {
    private let audioDeviceProvider: AudioDeviceProviding
    private let preferredModeOverride: AudioCaptureMode?

    public init(
        audioDeviceProvider: AudioDeviceProviding = CoreAudioDeviceProvider(),
        preferredModeOverride: AudioCaptureMode? = nil
    ) {
        self.audioDeviceProvider = audioDeviceProvider
        self.preferredModeOverride = preferredModeOverride
    }

    public func listAudioDevices() async -> [AudioDevice] {
        (try? audioDeviceProvider.audioDevices()) ?? []
    }

    public func preferredCaptureMode() async -> AudioCaptureMode {
        if let preferredModeOverride, preferredModeOverride != .unknown {
            return preferredModeOverride
        }

        let devices = await listAudioDevices()
        return devices.contains(where: DefaultBlackHoleManager.isBlackHole2chDevice) ? .blackHole2ch : .nativeSystemAudio
    }

    public func validateAudioRoute() async -> CheckStatus {
        let devices = await listAudioDevices()
        let preferredMode = await preferredCaptureMode()

        if preferredMode == .nativeSystemAudio {
            // Native capture is a fully supported mode on macOS 14.2+. If we
            // can enumerate at least one output device through CoreAudio there
            // is a route the video engine can use; no warning is necessary.
            let hasOutput = devices.contains(where: { $0.isOutput })
            if hasOutput { return .pass }
            return devices.isEmpty ? .fail : .warning
        }

        if devices.contains(where: DefaultBlackHoleManager.isBlackHole2chDevice) {
            return .pass
        }

        return devices.isEmpty ? .fail : .warning
    }
}

public final class CoreAudioDeviceProvider: AudioDeviceProviding {
    public init() {}

    public func audioDevices() throws -> [AudioDevice] {
        try audioDeviceIDs().compactMap(audioDevice(for:))
    }

    private func audioDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        guard sizeStatus == noErr, dataSize > 0 else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)

        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard dataStatus == noErr else {
            return []
        }

        return deviceIDs
    }

    private func audioDevice(for deviceID: AudioDeviceID) -> AudioDevice? {
        let inputChannels = channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)
        let outputChannels = channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput)
        let totalChannels = max(inputChannels, outputChannels)
        let name = deviceName(for: deviceID) ?? "Audio Device \(deviceID)"
        let isInput = inputChannels > 0 || streamCount(for: deviceID, scope: kAudioDevicePropertyScopeInput) > 0
        let isOutput = outputChannels > 0 || streamCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0

        guard isInput || isOutput else {
            return nil
        }

        return AudioDevice(
            id: String(deviceID),
            name: name,
            channels: totalChannels,
            sampleRate: nominalSampleRate(for: deviceID),
            isInput: isInput,
            isOutput: isOutput,
            status: totalChannels > 0 ? .available : .unknown
        )
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let namePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        namePointer.initialize(to: nil)
        defer {
            namePointer.deinitialize(count: 1)
            namePointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            namePointer
        )

        guard status == noErr else {
            return nil
        }

        return namePointer.pointee as String?
    }

    private func nominalSampleRate(for deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        var sampleRate = Float64(0)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &sampleRate
        )

        guard status == noErr, sampleRate > 0 else {
            return nil
        }

        return sampleRate
    }

    private func streamCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            return 0
        }

        return Int(dataSize) / MemoryLayout<AudioStreamID>.size
    }

    private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            rawPointer
        )

        guard dataStatus == noErr else {
            return 0
        }

        let bufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(bufferList)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
