// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class SunshineSessionTrackerTests: XCTestCase {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.timeZone = TimeZone.current
        return f
    }()

    private func date(_ raw: String) -> Date {
        return formatter.date(from: raw)!
    }

    func testEmptyLogReturnsFalse() {
        let since = date("2026-05-14 12:00:00.000")
        XCTAssertFalse(SunshineSessionTracker.sessionEndedAfter(since, in: ""))
    }

    func testOnlyConnectedAfterSinceReturnsFalse() {
        let since = date("2026-05-14 12:00:00.000")
        let log = """
        [2026-05-14 12:00:05.123]: Info: CLIENT CONNECTED
        """
        XCTAssertFalse(SunshineSessionTracker.sessionEndedAfter(since, in: log))
    }

    func testDisconnectedBeforeSinceReturnsFalse() {
        // A disconnect that happened before we even started the lock should
        // not trigger the auto-release — the user hasn't streamed yet during
        // this lock window.
        let since = date("2026-05-14 12:30:00.000")
        let log = """
        [2026-05-14 12:00:00.000]: Info: CLIENT CONNECTED
        [2026-05-14 12:10:00.000]: Info: CLIENT DISCONNECTED
        """
        XCTAssertFalse(SunshineSessionTracker.sessionEndedAfter(since, in: log))
    }

    func testDisconnectedAfterSinceReturnsTrue() {
        let since = date("2026-05-14 12:00:00.000")
        let log = """
        [2026-05-14 11:59:00.000]: Info: CLIENT CONNECTED
        [2026-05-14 12:05:30.123]: Info: CLIENT DISCONNECTED
        """
        XCTAssertTrue(SunshineSessionTracker.sessionEndedAfter(since, in: log))
    }

    func testReconnectAfterDisconnectReturnsFalse() {
        // User disconnected and then a new session started — host should
        // stay locked because a remote viewer is back on.
        let since = date("2026-05-14 12:00:00.000")
        let log = """
        [2026-05-14 12:01:00.000]: Info: CLIENT CONNECTED
        [2026-05-14 12:05:00.000]: Info: CLIENT DISCONNECTED
        [2026-05-14 12:06:00.000]: Info: CLIENT CONNECTED
        """
        XCTAssertFalse(SunshineSessionTracker.sessionEndedAfter(since, in: log))
    }

    func testMalformedLinesDoNotCrash() {
        let since = date("2026-05-14 12:00:00.000")
        let log = """
        garbage without brackets
        [malformed-date]: Info: CLIENT CONNECTED
        [2026-05-14 12:05:00.000]: Info: CLIENT DISCONNECTED
        """
        XCTAssertTrue(SunshineSessionTracker.sessionEndedAfter(since, in: log))
    }

    func testIgnoresUnrelatedLogLines() {
        let since = date("2026-05-14 12:00:00.000")
        let log = """
        [2026-05-14 12:01:00.000]: Info: Sunshine version: 2026.508.45922
        [2026-05-14 12:01:01.000]: Info: Trying encoder [videotoolbox]
        [2026-05-14 12:01:02.000]: Info: CLIENT CONNECTED
        [2026-05-14 12:01:05.000]: Info: Detected display: Built-in Retina Display
        [2026-05-14 12:05:00.000]: Info: CLIENT DISCONNECTED
        """
        XCTAssertTrue(SunshineSessionTracker.sessionEndedAfter(since, in: log))
    }
}
