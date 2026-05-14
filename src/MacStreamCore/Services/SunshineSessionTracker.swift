// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Parses Sunshine's structured log file to tell whether a remote streaming
/// session ended after a given reference date. The host privacy overlay
/// uses this signal to auto-release the lock when the Moonlight client
/// disconnects — Sunshine doesn't push events back to the host app, and
/// authenticating against its Web UI to query session state would be
/// heavier than reading the log it already writes.
///
/// Kept as a stateless enum so the parsing logic is trivially unit-testable
/// without touching the filesystem (callers pass a `String` of log
/// contents, and a convenience overload reads the canonical log path).
public enum SunshineSessionTracker {
    /// Returns true when the most recent client-lifecycle event AFTER
    /// `since` is a DISCONNECT that has not been followed by a fresh
    /// CONNECT. Used to detect "the user closed the Moonlight app".
    ///
    /// Returns false when:
    /// - No DISCONNECT line exists after `since` (still streaming, or
    ///   never started)
    /// - A CONNECT line appears after the most recent DISCONNECT (a new
    ///   session started, so the host shouldn't auto-release the lock)
    /// - The log can't be parsed
    public static func sessionEndedAfter(_ since: Date, in logContents: String) -> Bool {
        // Sunshine prints timestamps as `[2026-05-14 12:33:21.869]` — local
        // time, space-separated, with fractional seconds. ISO8601DateFormatter
        // is strict about the T/space boundary; a plain DateFormatter with an
        // explicit pattern is more forgiving. We treat the timestamp as POSIX
        // / `en_US_POSIX` UTC because Sunshine emits in the system's local
        // wall clock — the comparison against `since` is wall-clock anyway,
        // so any zone choice is consistent.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current

        var latestConnectAt: Date?
        var latestDisconnectAt: Date?

        // Suffix(2000) caps how much of a long-running log we re-scan each
        // tick — Sunshine's per-line cadence is low so this is plenty.
        for rawLine in logContents.split(whereSeparator: \.isNewline).suffix(2000) {
            let line = String(rawLine)
            guard let openBracket = line.firstIndex(of: "["),
                  let closeBracket = line.firstIndex(of: "]"),
                  openBracket < closeBracket else { continue }
            let rawDate = String(line[line.index(after: openBracket)..<closeBracket])
            guard let date = formatter.date(from: rawDate) else { continue }
            if line.contains("CLIENT CONNECTED") {
                latestConnectAt = date
            } else if line.contains("CLIENT DISCONNECTED") {
                latestDisconnectAt = date
            }
        }

        guard let disconnect = latestDisconnectAt, disconnect > since else { return false }
        if let connect = latestConnectAt, connect > disconnect { return false }
        return true
    }

    /// Default location where Sunshine writes its structured log, regardless
    /// of how MacStream Host redirects stdout/stderr.
    public static func defaultLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sunshine/sunshine.log")
    }

    /// Convenience overload that reads the canonical log path. Used by
    /// `AppState`'s stream-end watcher.
    public static func sessionEndedAfter(_ since: Date) -> Bool {
        guard let contents = try? String(contentsOf: defaultLogURL(), encoding: .utf8) else {
            return false
        }
        return sessionEndedAfter(since, in: contents)
    }
}
