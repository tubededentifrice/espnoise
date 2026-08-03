import Foundation

enum NoiseLevelScale {
    static let minimum = 0.0
    static let maximum = 120.0
    static func positiveLevel(fromDbfsTenths value: Int16) -> Double {
        Double(value) / 10 + 120
    }

    static func dbfsTenths(fromPositiveLevel value: Double) -> Int16 {
        Int16((value * 10).rounded()) - 1_200
    }
}

struct NoiseSettings: Codable, Equatable, Sendable {
    var brightnessPercent: UInt8 = 100
    var buzzerPercent: UInt8 = 50
    var greenThresholdTenths: Int16 = -550
    var orangeThresholdTenths: Int16 = -480
    var redThresholdTenths: Int16 = -420
    var sampleDurationMilliseconds: UInt32 = 1_000
    var samplePeriodMilliseconds: UInt32 = 10_000
    var decisionWindowMilliseconds: UInt32 = 60_000
    var triggerPercent: UInt8 = 50
    var muteDurationSeconds: UInt32 = 1_800
}

struct DeviceOverrides: Codable, Equatable, Sendable {
    var brightnessPercent: UInt8?
    var buzzerPercent: UInt8?
    var greenThresholdTenths: Int16?
    var orangeThresholdTenths: Int16?
    var redThresholdTenths: Int16?
    var muteDurationSeconds: UInt32?

    var isEmpty: Bool {
        brightnessPercent == nil && buzzerPercent == nil
            && greenThresholdTenths == nil
            && orangeThresholdTenths == nil
            && redThresholdTenths == nil && muteDurationSeconds == nil
    }

    func applying(to settings: NoiseSettings) -> NoiseSettings {
        var result = settings
        result.brightnessPercent = brightnessPercent ?? settings.brightnessPercent
        result.buzzerPercent = buzzerPercent ?? settings.buzzerPercent
        result.greenThresholdTenths =
            greenThresholdTenths ?? settings.greenThresholdTenths
        result.orangeThresholdTenths =
            orangeThresholdTenths ?? settings.orangeThresholdTenths
        result.redThresholdTenths = redThresholdTenths ?? settings.redThresholdTenths
        result.muteDurationSeconds =
            muteDurationSeconds ?? settings.muteDurationSeconds
        return result
    }
}

struct NoiseDeviceRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var customName: String
    var overrides = DeviceOverrides()
    var desiredRevision: UInt32
    var lastSuccessfulSync: Date?
    var lastAppliedRevision: UInt32?
    var lastAppliedFingerprint: UInt32?
}

struct NoiseAppRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var globalSettings = NoiseSettings()
    var devices: [NoiseDeviceRecord] = []
    var nextRevision: UInt32 = 1
}

enum DeviceNameValidation {
    static func normalized(_ candidate: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }
}

enum NoiseSettingsValidationError: LocalizedError, Equatable {
    case percentOutOfRange
    case thresholdOutOfRange
    case thresholdOrder
    case samplingTiming
    case decisionWindow
    case historySize
    case sporadicTrigger
    case muteDuration

    var errorDescription: String? {
        switch self {
        case .percentOutOfRange:
            "Brightness and buzzer volume must be from 0 through 100%. X must be from 1 through 99%."
        case .thresholdOutOfRange:
            "Each displayed noise threshold must be from 0 through 120."
        case .thresholdOrder:
            "Set the green threshold below orange, and set orange below red."
        case .samplingTiming:
            "K and N must be greater than zero, and K must not exceed N."
        case .decisionWindow:
            "The decision window must contain a whole number of N periods."
        case .historySize:
            "The decision window must contain from 1 through 120 observations."
        case .sporadicTrigger:
            "This sampling rule could warn after one sporadic sound. Increase the history size or X."
        case .muteDuration:
            "The mute duration must be from 60 seconds through 24 hours."
        }
    }
}

extension NoiseSettings {
    func validated() throws -> NoiseSettings {
        guard brightnessPercent <= 100, buzzerPercent <= 100,
              triggerPercent >= 1, triggerPercent <= 99 else {
            throw NoiseSettingsValidationError.percentOutOfRange
        }
        guard greenThresholdTenths >= -1_200,
              redThresholdTenths <= 0 else {
            throw NoiseSettingsValidationError.thresholdOutOfRange
        }
        guard greenThresholdTenths < orangeThresholdTenths,
              orangeThresholdTenths < redThresholdTenths else {
            throw NoiseSettingsValidationError.thresholdOrder
        }
        guard sampleDurationMilliseconds > 0,
              samplePeriodMilliseconds > 0,
              sampleDurationMilliseconds <= samplePeriodMilliseconds else {
            throw NoiseSettingsValidationError.samplingTiming
        }
        guard decisionWindowMilliseconds >= samplePeriodMilliseconds,
              decisionWindowMilliseconds % samplePeriodMilliseconds == 0 else {
            throw NoiseSettingsValidationError.decisionWindow
        }
        let historyCount = decisionWindowMilliseconds / samplePeriodMilliseconds
        guard historyCount > 0, historyCount <= 120 else {
            throw NoiseSettingsValidationError.historySize
        }
        let requiredSamples = historyCount * UInt32(triggerPercent) / 100 + 1
        guard requiredSamples >= 2 else {
            throw NoiseSettingsValidationError.sporadicTrigger
        }
        guard (60...86_400).contains(muteDurationSeconds) else {
            throw NoiseSettingsValidationError.muteDuration
        }
        return self
    }
}
