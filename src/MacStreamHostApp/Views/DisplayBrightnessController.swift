// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Darwin
import Foundation

/// Dims every physical display by driving brightness through the private
/// DisplayServices framework, snapshotting the previous value so it can be
/// restored on demand. Apple intentionally hides this entry point in the
/// public SDK, but it's the same API used by Lunar/MonitorControl/BetterDisplay
/// and is stable across macOS 13/14/15 on Apple Silicon and Intel.
///
/// We use this instead of an NSWindow backdrop because ScreenCaptureKit (which
/// Sunshine consumes) ignores NSWindow.sharingType — any overlay window would
/// still leak into the remote feed. Lowering brightness keeps the framebuffer
/// untouched, so the Moonlight client sees the live desktop while the local
/// monitors go dark.
final class DisplayBrightnessController {
    private var snapshots: [CGDirectDisplayID: Float] = [:]
    private let bridge = DisplayServicesBridge()

    var isSupported: Bool { bridge.isAvailable }

    func dimAllDisplays() -> Bool {
        guard bridge.isAvailable else { return false }

        var didAny = false
        for displayID in activeDisplays() {
            if snapshots[displayID] == nil, let current = bridge.getBrightness(for: displayID) {
                snapshots[displayID] = current
            }
            if bridge.setBrightness(for: displayID, value: 0) {
                didAny = true
            }
        }
        return didAny
    }

    func restoreAllDisplays() {
        for (displayID, value) in snapshots {
            _ = bridge.setBrightness(for: displayID, value: value)
        }
        snapshots.removeAll()
    }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        var actualCount: UInt32 = 0
        guard CGGetActiveDisplayList(displayCount, &ids, &actualCount) == .success else {
            return []
        }
        return Array(ids.prefix(Int(actualCount)))
    }
}

private final class DisplayServicesBridge {
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let setSymbol: UnsafeMutableRawPointer?
    private let getSymbol: UnsafeMutableRawPointer?

    init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        )
        setSymbol = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        getSymbol = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    var isAvailable: Bool {
        handle != nil && setSymbol != nil && getSymbol != nil
    }

    func setBrightness(for displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let setSymbol else { return false }
        let function = unsafeBitCast(setSymbol, to: SetFn.self)
        return function(displayID, max(0, min(1, value))) == 0
    }

    func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
        guard let getSymbol else { return nil }
        let function = unsafeBitCast(getSymbol, to: GetFn.self)
        var value: Float = 0
        guard function(displayID, &value) == 0 else { return nil }
        return value
    }
}
