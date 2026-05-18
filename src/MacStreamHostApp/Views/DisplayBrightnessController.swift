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
/// Three mechanisms are tried per display in order:
///
/// 1. `DisplayServicesSetBrightness` (private framework on macOS 13+) — works
///    on built-in Apple panels (Retina, Studio Display, XDR).
/// 2. `IODisplaySetFloatParameter` with `kIODisplayBrightnessKey` (legacy IOKit).
/// 3. `CGSetDisplayTransferByFormula(displayID, 0,0,0, 0,0,0, 0,0,0)` — gamma
///    blackout. The fallback for external monitors that don't expose
///    DDC/CI brightness control. Gamma is applied per-display by the GPU
///    AFTER the framebuffer, BEFORE the panel, so the captured framebuffer
///    that Moonlight reads stays untouched. The local LG / Dell / etc.
///    monitor physically goes black.
///
/// We **never** fall back to an NSWindow blackout because that overlay leaks
/// into ScreenCaptureKit and therefore into the Moonlight feed. If all
/// methods fail, `dimResult` reports it so the UI can warn the user instead
/// of silently doing the wrong thing.
public struct DisplayDimResult {
    public enum Method: String { case displayServices, ioKit, gammaBlackout, none }

    public var dimmedDisplays: [CGDirectDisplayID]
    public var skippedNonBuiltIn: [CGDirectDisplayID]
    public var failedDisplays: [CGDirectDisplayID]
    public var methodUsed: Method
    /// Per-display method actually used. Useful so the UI can explain to
    /// the user "Built-in escurecido via DisplayServices, LG ULTRAWIDE
    /// via gamma blackout".
    public var perDisplayMethods: [CGDirectDisplayID: Method]

    public init(
        dimmedDisplays: [CGDirectDisplayID] = [],
        skippedNonBuiltIn: [CGDirectDisplayID] = [],
        failedDisplays: [CGDirectDisplayID] = [],
        methodUsed: Method = .none,
        perDisplayMethods: [CGDirectDisplayID: Method] = [:]
    ) {
        self.dimmedDisplays = dimmedDisplays
        self.skippedNonBuiltIn = skippedNonBuiltIn
        self.failedDisplays = failedDisplays
        self.methodUsed = methodUsed
        self.perDisplayMethods = perDisplayMethods
    }

    public var didDimAny: Bool { dimmedDisplays.isEmpty == false }
    public var summary: String {
        if dimmedDisplays.isEmpty {
            if skippedNonBuiltIn.isEmpty {
                return "Nenhum display físico foi escurecido."
            }
            return "Nenhum display físico interno escurecido (skipados: \(skippedNonBuiltIn.count))."
        }
        let displaysWord = dimmedDisplays.count == 1 ? "display" : "displays"
        // Aggregate method tally for the summary so the user sees e.g.
        // "2 displays escurecidos (1 via brightness, 1 via gammaBlackout)".
        var counts: [Method: Int] = [:]
        for method in perDisplayMethods.values {
            counts[method, default: 0] += 1
        }
        if counts.count <= 1 {
            return "\(dimmedDisplays.count) \(displaysWord) escurecido via \(methodUsed.rawValue)."
        }
        let breakdown = counts
            .map { "\($0.value) \($0.key.rawValue)" }
            .sorted()
            .joined(separator: ", ")
        return "\(dimmedDisplays.count) \(displaysWord) escurecidos (\(breakdown))."
    }
}

final class DisplayBrightnessController {
    private var snapshots: [CGDirectDisplayID: (Float, DisplayDimResult.Method)] = [:]
    /// Displays whose gamma we zeroed and must restore via
    /// `CGDisplayRestoreColorSyncSettings` on unlock. Tracked separately
    /// from `snapshots` because gamma doesn't have a per-display "previous
    /// value" we can read — the OS restore call resets all displays to
    /// their calibrated baselines in one shot.
    private var gammaBlackedOutDisplays: Set<CGDirectDisplayID> = []
    private let displayServices = DisplayServicesBridge()
    private let ioKit = IOKitBrightnessBridge()

    /// Dims every active physical display except `keepLitDisplayID` (when
    /// provided). The kept-lit display is where the dashboard / unlock
    /// UI lives — without it the user has no visible surface to act on
    /// once every framebuffer goes to black.
    @discardableResult
    func dimAllDisplays(except keepLitDisplayID: CGDirectDisplayID? = nil) -> DisplayDimResult {
        var dimmed: [CGDirectDisplayID] = []
        var failed: [CGDirectDisplayID] = []
        var skipped: [CGDirectDisplayID] = []
        var effectiveMethod: DisplayDimResult.Method = .none
        var perDisplayMethods: [CGDirectDisplayID: DisplayDimResult.Method] = [:]

        for displayID in activeDisplays() {
            if let keepLitDisplayID, displayID == keepLitDisplayID {
                // The display hosting the unlock UI must stay lit so the
                // user can actually click "Desbloquear". We still count
                // it as "skipped" so the summary tells the user why.
                skipped.append(displayID)
                continue
            }
            guard CGDisplayIsBuiltin(displayID) != 0 || CGDisplayIsOnline(displayID) != 0 else {
                skipped.append(displayID)
                continue
            }
            if CGDisplayIsBuiltin(displayID) == 0 && isProbablyNetworkDisplay(displayID) {
                skipped.append(displayID)
                continue
            }

            let order = dimOrder(for: displayID)
            var success = false
            for method in order {
                switch method {
                case .displayServices, .ioKit:
                    if tryDim(displayID: displayID, using: method) {
                        dimmed.append(displayID)
                        perDisplayMethods[displayID] = method
                        if effectiveMethod == .none { effectiveMethod = method }
                        success = true
                    }
                case .gammaBlackout:
                    if tryGammaBlackout(displayID: displayID) {
                        dimmed.append(displayID)
                        perDisplayMethods[displayID] = .gammaBlackout
                        if effectiveMethod == .none { effectiveMethod = .gammaBlackout }
                        success = true
                    }
                case .none:
                    break
                }
                if success { break }
            }
            if !success {
                failed.append(displayID)
            }
        }

        return DisplayDimResult(
            dimmedDisplays: dimmed,
            skippedNonBuiltIn: skipped,
            failedDisplays: failed,
            methodUsed: effectiveMethod,
            perDisplayMethods: perDisplayMethods
        )
    }

    /// Picks the dim-method priority order per display. Built-in Apple
    /// panels respond reliably to the brightness APIs (the kernel
    /// controls the LCD backlight), so we prefer that path because it's
    /// fully reversible without touching the system-wide ColorSync
    /// settings. External monitors return `kIOReturnSuccess` from the
    /// brightness APIs even when they ignore the command — that's why
    /// the LG ULTRAWIDE stayed lit in the previous build despite our
    /// "added gamma fallback". To make external dims actually take
    /// effect, we put `gammaBlackout` first for non-builtin displays.
    /// The brightness paths remain as last-resort tail-fallbacks so
    /// installations with DDC/CI helpers (MonitorControl, etc.) get
    /// the most aggressive coverage possible.
    private func dimOrder(for displayID: CGDirectDisplayID) -> [DisplayDimResult.Method] {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return [.displayServices, .ioKit, .gammaBlackout]
        }
        return [.gammaBlackout, .displayServices, .ioKit]
    }

    func restoreAllDisplays() {
        for (displayID, snapshot) in snapshots {
            let (value, method) = snapshot
            switch method {
            case .displayServices:
                _ = displayServices.setBrightness(for: displayID, value: value)
            case .ioKit:
                _ = ioKit.setBrightness(for: displayID, value: value)
            case .gammaBlackout, .none:
                break
            }
        }
        snapshots.removeAll()

        // CGDisplayRestoreColorSyncSettings() is a single global call that
        // restores every display's gamma to the user's calibrated profile.
        // We only invoke it when we actually touched at least one display,
        // to avoid the unnecessary side-effect of overriding any other
        // app's gamma settings (rare but possible).
        if !gammaBlackedOutDisplays.isEmpty {
            CGDisplayRestoreColorSyncSettings()
            gammaBlackedOutDisplays.removeAll()
        }
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
        case .gammaBlackout, .none:
            // gammaBlackout has its own dedicated entry point below;
            // .none never reaches here.
            return false
        }
    }

    /// Forces this display to render solid black by zeroing every gamma
    /// channel (R, G, B). Returns true on success. The change persists
    /// until `CGDisplayRestoreColorSyncSettings()` is called or the
    /// display is unplugged.
    ///
    /// CGSetDisplayTransferByFormula(displayID, redMin, redMax, redGamma,
    /// greenMin, greenMax, greenGamma, blueMin, blueMax, blueGamma).
    /// Passing every parameter as 0 produces a constant-zero transfer
    /// curve — the GPU sends black to the panel regardless of what was
    /// drawn into the framebuffer.
    private func tryGammaBlackout(displayID: CGDirectDisplayID) -> Bool {
        let status = CGSetDisplayTransferByFormula(
            displayID,
            0, 0, 0,
            0, 0, 0,
            0, 0, 0
        )
        guard status == .success else {
            return false
        }
        gammaBlackedOutDisplays.insert(displayID)
        return true
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
