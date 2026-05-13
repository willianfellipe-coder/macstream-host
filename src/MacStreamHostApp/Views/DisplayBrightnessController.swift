// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Darwin
import Foundation
import IOKit

/// Drops every **built-in / wired** display to brightness 0 so the local viewer
/// goes dark while the framebuffer keeps being produced normally — Moonlight
/// keeps seeing the live desktop and the remote user can keep working through
/// the Mac. Sidecar / AirPlay displays are skipped because their "brightness"
/// can affect the framebuffer that's transmitted to the iPad.
///
/// Three private/legacy mechanisms are tried in order:
///
/// 1. `DisplayServicesSetBrightness` (private framework on macOS 13+)
/// 2. `IODisplaySetFloatParameter` with `kIODisplayBrightnessKey` (legacy IOKit, still works)
///
/// We **never** fall back to an NSWindow blackout because that overlay leaks
/// into ScreenCaptureKit and therefore into the Moonlight feed. If both
/// methods fail, `dimResult` reports it so the UI can warn the user instead
/// of silently doing the wrong thing.
public struct DisplayDimResult {
    public enum Method: String { case displayServices, ioKit, none }

    public var dimmedDisplays: [CGDirectDisplayID]
    public var skippedNonBuiltIn: [CGDirectDisplayID]
    public var failedDisplays: [CGDirectDisplayID]
    public var methodUsed: Method

    public var didDimAny: Bool { dimmedDisplays.isEmpty == false }
    public var summary: String {
        if dimmedDisplays.isEmpty {
            if skippedNonBuiltIn.isEmpty {
                return "Nenhum display físico foi escurecido."
            }
            return "Nenhum display físico interno escurecido (skipados: \(skippedNonBuiltIn.count))."
        }
        let method = methodUsed.rawValue
        let displaysWord = dimmedDisplays.count == 1 ? "display" : "displays"
        return "\(dimmedDisplays.count) \(displaysWord) escurecido via \(method)."
    }
}

final class DisplayBrightnessController {
    private var snapshots: [CGDirectDisplayID: (Float, DisplayDimResult.Method)] = [:]
    private let displayServices = DisplayServicesBridge()
    private let ioKit = IOKitBrightnessBridge()

    @discardableResult
    func dimAllDisplays() -> DisplayDimResult {
        var dimmed: [CGDirectDisplayID] = []
        var failed: [CGDirectDisplayID] = []
        var skipped: [CGDirectDisplayID] = []
        var effectiveMethod: DisplayDimResult.Method = .none

        for displayID in activeDisplays() {
            guard CGDisplayIsBuiltin(displayID) != 0 || CGDisplayIsOnline(displayID) != 0 else {
                skipped.append(displayID)
                continue
            }
            if CGDisplayIsBuiltin(displayID) == 0 && isProbablyNetworkDisplay(displayID) {
                skipped.append(displayID)
                continue
            }

            if tryDim(displayID: displayID, using: .displayServices) {
                dimmed.append(displayID)
                effectiveMethod = .displayServices
            } else if tryDim(displayID: displayID, using: .ioKit) {
                dimmed.append(displayID)
                if effectiveMethod == .none { effectiveMethod = .ioKit }
            } else {
                failed.append(displayID)
            }
        }

        return DisplayDimResult(
            dimmedDisplays: dimmed,
            skippedNonBuiltIn: skipped,
            failedDisplays: failed,
            methodUsed: effectiveMethod
        )
    }

    func restoreAllDisplays() {
        for (displayID, snapshot) in snapshots {
            let (value, method) = snapshot
            switch method {
            case .displayServices:
                _ = displayServices.setBrightness(for: displayID, value: value)
            case .ioKit:
                _ = ioKit.setBrightness(for: displayID, value: value)
            case .none:
                break
            }
        }
        snapshots.removeAll()
    }

    private func tryDim(displayID: CGDirectDisplayID, using method: DisplayDimResult.Method) -> Bool {
        switch method {
        case .displayServices:
            guard displayServices.isAvailable,
                  let current = displayServices.getBrightness(for: displayID) else { return false }
            guard displayServices.setBrightness(for: displayID, value: 0) else { return false }
            if snapshots[displayID] == nil {
                snapshots[displayID] = (current, .displayServices)
            }
            return true
        case .ioKit:
            guard let current = ioKit.getBrightness(for: displayID) else { return false }
            guard ioKit.setBrightness(for: displayID, value: 0) else { return false }
            if snapshots[displayID] == nil {
                snapshots[displayID] = (current, .ioKit)
            }
            return true
        case .none:
            return false
        }
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

    /// Network/AirPlay displays don't expose a usable brightness service. Even
    /// if we could write to it, doing so risks corrupting the framebuffer the
    /// remote viewer is consuming. Better to skip them entirely.
    private func isProbablyNetworkDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        let vendor = CGDisplayVendorNumber(displayID)
        // Sidecar / AirPlay receivers expose vendor 0x05ac (Apple) and model 0 — same
        // signature shows up for some emulated displays. Built-in returns nonzero model.
        if vendor == 0x05ac && CGDisplayModelNumber(displayID) == 0 {
            return true
        }
        return false
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

/// Legacy IOKit path — `IODisplaySetFloatParameter` with `kIODisplayBrightnessKey`.
/// Still works on Apple Silicon and Intel macOS as a backstop when the
/// DisplayServices private framework is unavailable.
private final class IOKitBrightnessBridge {
    func setBrightness(for displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let service = service(for: displayID) else { return false }
        defer { IOObjectRelease(service) }
        let key = "brightness" as CFString
        let result = IODisplaySetFloatParameter(service, 0, key, max(0, min(1, value)))
        return result == kIOReturnSuccess
    }

    func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
        guard let service = service(for: displayID) else { return nil }
        defer { IOObjectRelease(service) }
        let key = "brightness" as CFString
        var value: Float = 0
        let result = IODisplayGetFloatParameter(service, 0, key, &value)
        guard result == kIOReturnSuccess else { return nil }
        return value
    }

    private func service(for displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var candidate: io_service_t = IOIteratorNext(iterator)
        while candidate != 0 {
            let info = IODisplayCreateInfoDictionary(candidate, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
            let vendorID = info[kDisplayVendorID] as? UInt32 ?? 0
            let productID = info[kDisplayProductID] as? UInt32 ?? 0
            if vendorID == CGDisplayVendorNumber(displayID), productID == CGDisplayModelNumber(displayID) {
                return candidate
            }
            IOObjectRelease(candidate)
            candidate = IOIteratorNext(iterator)
        }
        return nil
    }
}
