// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum SunshineConfigurationValidator {
    public static func parseKeyValueLines(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }

            let parts = trimmedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        return values
    }

    public static func validateSunshineConfig(_ contents: String) -> ConfigurationValidationResult {
        let values = parseKeyValueLines(contents)
        var errors: [String] = []
        var warnings: [String] = []

        for requiredKey in ["sunshine_name", "stream_audio", "upnp", "port"] where values[requiredKey] == nil {
            errors.append("Missing required Sunshine setting: \(requiredKey)")
        }

        if let portValue = values["port"], Int(portValue) == nil {
            errors.append("Sunshine port must be numeric.")
        }

        if values["upnp"] != "disabled" {
            warnings.append("UPnP should remain disabled by default for the MVP.")
        }

        if values["audio_sink"] == nil {
            warnings.append("audio_sink is not set; native macOS audio capture must be validated manually.")
        }

        return ConfigurationValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            parsedValues: values
        )
    }

    public static func validateStreamingConfiguration(_ configuration: RecommendedStreamingConfiguration) -> ConfigurationValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if configuration.width <= 0 || configuration.height <= 0 {
            errors.append("Resolution must be positive.")
        }

        if configuration.framesPerSecond <= 0 {
            errors.append("Frame rate must be positive.")
        }

        if configuration.bitrateMbps <= 0 {
            errors.append("Bitrate must be positive.")
        }

        if configuration.framesPerSecond > 60 {
            warnings.append("Frame rates above 60 FPS need end-to-end validation on macOS and Moonlight.")
        }

        if configuration.bitrateMbps > 100 {
            warnings.append("Very high bitrate should be limited to validated local networks.")
        }

        return ConfigurationValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}
