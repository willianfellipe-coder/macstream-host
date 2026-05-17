// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

#if os(macOS)
import ApplicationServices
#endif

/// Reports whether the calling process has Accessibility (`AXIsProcessTrusted()`)
/// granted. macOS does not expose a query API to ask about a *different* process
/// — the result is always evaluated for the caller. To get a representative
/// answer for the MacStream engine, this probe MUST be invoked from a binary
/// signed with the same identity / identifier as the engine (`org.macstream.host`).
///
/// On macOS this calls into `ApplicationServices`. On other platforms the probe
/// returns `.unknown` so the rest of the diagnostic pipeline stays cross-platform
/// for the test target.
public enum AccessibilityProbe {
    public enum Result: String, Codable {
        case granted
        case denied
        case unknown
    }

    public static func currentStatus() -> Result {
        #if os(macOS)
        return AXIsProcessTrusted() ? .granted : .denied
        #else
        return .unknown
        #endif
    }
}
