// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import MacStreamCore

final class ConfigurationValidatorTests: XCTestCase {
    func testParsesSunshineKeyValueConfiguration() {
        let contents = """
        # comment
        sunshine_name = MacStream Host
        stream_audio = enabled
        upnp = disabled
        port = 47989
        audio_sink = BlackHole 2ch
        """

        let values = SunshineConfigurationValidator.parseKeyValueLines(contents)

        XCTAssertEqual(values["sunshine_name"], "MacStream Host")
        XCTAssertEqual(values["audio_sink"], "BlackHole 2ch")
        XCTAssertEqual(values["port"], "47989")
    }

    func testValidSunshineConfigurationPassesWithExpectedWarningsOnly() {
        let manager = MockConfigurationManager()
        let contents = manager.renderDefaultSunshineConfiguration(audioSink: "BlackHole 2ch")

        let result = manager.validateSunshineConfiguration(contents)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testInvalidStreamingConfigurationFails() {
        let configuration = RecommendedStreamingConfiguration(
            profile: .custom,
            width: 0,
            height: 1080,
            framesPerSecond: 60,
            bitrateMbps: 30,
            codec: .automatic,
            audioMode: .unknown
        )

        let result = SunshineConfigurationValidator.validateStreamingConfiguration(configuration)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors, ["Resolution must be positive."])
    }
}
