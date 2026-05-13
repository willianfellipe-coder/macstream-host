// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class LogManagerTests: XCTestCase {
    func testRecentLogsReadsAndMasksHomePath() async throws {
        let directory = try makeTemporaryDirectory()
        let logURL = directory.appendingPathComponent("sunshine.out.log")
        try "/Users/example/private\nsecond line".write(to: logURL, atomically: true, encoding: .utf8)
        let manager = DefaultLogManager(logDirectoryURL: directory, homePath: "/Users/example")

        let logs = await manager.recentLogs(maxLines: 10)

        XCTAssertEqual(logs.map(\.message), ["~/private", "second line"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStreamHostLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
