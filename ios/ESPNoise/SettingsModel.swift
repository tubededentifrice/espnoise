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

enum ThresholdSliderScale {
    static let minimum = 40.0
    static let maximum = NoiseLevelScale.maximum
    static let range = minimum...maximum
    static let step = 1.0
    static let orderGapTenths: Int16 = 10

    static func normalizedSettings(_ source: NoiseSettings) -> NoiseSettings {
        var result = source
        var green = normalizedLevel(source.greenThresholdTenths)
        green = min(green, Int(maximum) - 2)
        var orange = normalizedLevel(source.orangeThresholdTenths)
        orange = min(max(orange, green + 1), Int(maximum) - 1)
        var red = normalizedLevel(source.redThresholdTenths)
        red = min(max(red, orange + 1), Int(maximum))
        result.greenThresholdTenths = tenths(green)
        result.orangeThresholdTenths = tenths(orange)
        result.redThresholdTenths = tenths(red)
        return result
    }

    static func normalizedOverrides(
        _ source: DeviceOverrides,
        global: NoiseSettings
    ) -> DeviceOverrides {
        var result = source
        // Use the stored global values because SettingsStore applies device
        // overrides to this exact base when the user saves the page.
        let inherited = global
        if let green = result.greenThresholdTenths {
            result.greenThresholdTenths = tenths(normalizedLevel(green))
        }
        if let orange = result.orangeThresholdTenths {
            result.orangeThresholdTenths = tenths(normalizedLevel(orange))
        }
        if let red = result.redThresholdTenths {
            result.redThresholdTenths = tenths(normalizedLevel(red))
        }

        for _ in 0..<4 {
            let green = result.greenThresholdTenths
                ?? inherited.greenThresholdTenths
            let orange = result.orangeThresholdTenths
                ?? inherited.orangeThresholdTenths
            let red = result.redThresholdTenths
                ?? inherited.redThresholdTenths
            if green + orderGapTenths > orange {
                if result.greenThresholdTenths != nil {
                    result.greenThresholdTenths = wholeAtMost(
                        orange - orderGapTenths
                    )
                } else if result.orangeThresholdTenths != nil {
                    result.orangeThresholdTenths = wholeAtLeast(
                        green + orderGapTenths
                    )
                }
            }
            let adjustedOrange = result.orangeThresholdTenths
                ?? inherited.orangeThresholdTenths
            if adjustedOrange + orderGapTenths > red {
                if result.redThresholdTenths != nil {
                    result.redThresholdTenths = wholeAtLeast(
                        adjustedOrange + orderGapTenths
                    )
                } else if result.orangeThresholdTenths != nil {
                    result.orangeThresholdTenths = wholeAtMost(
                        red - orderGapTenths
                    )
                }
            }
            clampOverrides(&result)
        }

        let green = result.greenThresholdTenths
            ?? inherited.greenThresholdTenths
        let orange = result.orangeThresholdTenths
            ?? inherited.orangeThresholdTenths
        let red = result.redThresholdTenths ?? inherited.redThresholdTenths
        guard green + orderGapTenths <= orange,
              orange + orderGapTenths <= red else {
            result.greenThresholdTenths = nil
            result.orangeThresholdTenths = nil
            result.redThresholdTenths = nil
            return result
        }
        return result
    }

    private static func normalizedLevel(_ value: Int16) -> Int {
        let level = Int(
            NoiseLevelScale.positiveLevel(fromDbfsTenths: value).rounded()
        )
        return min(Int(maximum), max(Int(minimum), level))
    }

    private static func tenths(_ level: Int) -> Int16 {
        NoiseLevelScale.dbfsTenths(fromPositiveLevel: Double(level))
    }

    private static func wholeAtMost(_ value: Int16) -> Int16 {
        let raw = Int(value)
        let remainder = raw % Int(orderGapTenths)
        guard remainder != 0 else { return value }
        let quotient = raw / Int(orderGapTenths) - (raw < 0 ? 1 : 0)
        return Int16(quotient * Int(orderGapTenths))
    }

    private static func wholeAtLeast(_ value: Int16) -> Int16 {
        let raw = Int(value)
        let remainder = raw % Int(orderGapTenths)
        guard remainder != 0 else { return value }
        let quotient = raw / Int(orderGapTenths) + (raw > 0 ? 1 : 0)
        return Int16(quotient * Int(orderGapTenths))
    }

    private static func clampOverrides(_ overrides: inout DeviceOverrides) {
        let minimumTenths = tenths(Int(minimum))
        if let green = overrides.greenThresholdTenths {
            overrides.greenThresholdTenths = min(0, max(minimumTenths, green))
        }
        if let orange = overrides.orangeThresholdTenths {
            overrides.orangeThresholdTenths = min(0, max(minimumTenths, orange))
        }
        if let red = overrides.redThresholdTenths {
            overrides.redThresholdTenths = min(0, max(minimumTenths, red))
        }
    }
}

struct NoiseSettings: Codable, Equatable, Hashable, Sendable {
    var analyticsEnabled: Bool = true
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

    init(
        analyticsEnabled: Bool = true,
        brightnessPercent: UInt8 = 100,
        buzzerPercent: UInt8 = 50,
        greenThresholdTenths: Int16 = -550,
        orangeThresholdTenths: Int16 = -480,
        redThresholdTenths: Int16 = -420,
        sampleDurationMilliseconds: UInt32 = 1_000,
        samplePeriodMilliseconds: UInt32 = 10_000,
        decisionWindowMilliseconds: UInt32 = 60_000,
        triggerPercent: UInt8 = 50,
        muteDurationSeconds: UInt32 = 1_800
    ) {
        self.analyticsEnabled = analyticsEnabled
        self.brightnessPercent = brightnessPercent
        self.buzzerPercent = buzzerPercent
        self.greenThresholdTenths = greenThresholdTenths
        self.orangeThresholdTenths = orangeThresholdTenths
        self.redThresholdTenths = redThresholdTenths
        self.sampleDurationMilliseconds = sampleDurationMilliseconds
        self.samplePeriodMilliseconds = samplePeriodMilliseconds
        self.decisionWindowMilliseconds = decisionWindowMilliseconds
        self.triggerPercent = triggerPercent
        self.muteDurationSeconds = muteDurationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case analyticsEnabled
        case brightnessPercent
        case buzzerPercent
        case greenThresholdTenths
        case orangeThresholdTenths
        case redThresholdTenths
        case sampleDurationMilliseconds
        case samplePeriodMilliseconds
        case decisionWindowMilliseconds
        case triggerPercent
        case muteDurationSeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        analyticsEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .analyticsEnabled
        ) ?? true
        brightnessPercent = try values.decode(
            UInt8.self,
            forKey: .brightnessPercent
        )
        buzzerPercent = try values.decode(UInt8.self, forKey: .buzzerPercent)
        greenThresholdTenths = try values.decode(
            Int16.self,
            forKey: .greenThresholdTenths
        )
        orangeThresholdTenths = try values.decode(
            Int16.self,
            forKey: .orangeThresholdTenths
        )
        redThresholdTenths = try values.decode(
            Int16.self,
            forKey: .redThresholdTenths
        )
        sampleDurationMilliseconds = try values.decode(
            UInt32.self,
            forKey: .sampleDurationMilliseconds
        )
        samplePeriodMilliseconds = try values.decode(
            UInt32.self,
            forKey: .samplePeriodMilliseconds
        )
        decisionWindowMilliseconds = try values.decode(
            UInt32.self,
            forKey: .decisionWindowMilliseconds
        )
        triggerPercent = try values.decode(
            UInt8.self,
            forKey: .triggerPercent
        )
        muteDurationSeconds = try values.decode(
            UInt32.self,
            forKey: .muteDurationSeconds
        )
    }
}

struct DeviceOverrides: Codable, Equatable, Hashable, Sendable {
    var analyticsEnabled: Bool?
    var brightnessPercent: UInt8?
    var buzzerPercent: UInt8?
    var greenThresholdTenths: Int16?
    var orangeThresholdTenths: Int16?
    var redThresholdTenths: Int16?
    var muteDurationSeconds: UInt32?

    var isEmpty: Bool {
        analyticsEnabled == nil && brightnessPercent == nil
            && buzzerPercent == nil
            && greenThresholdTenths == nil
            && orangeThresholdTenths == nil
            && redThresholdTenths == nil && muteDurationSeconds == nil
    }

    func applying(to settings: NoiseSettings) -> NoiseSettings {
        var result = settings
        result.analyticsEnabled = analyticsEnabled ?? settings.analyticsEnabled
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
    var nameSyncPending: Bool?
    var lastConfirmedName: String?
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
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= DeviceNamePacketCodec.maximumUTF8Bytes,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }

    static func normalizedUserName(_ candidate: String) -> String? {
        guard let name = normalized(candidate),
              !isHardwareDefaultName(name) else { return nil }
        return name
    }

    static func migratedLegacyName(_ candidate: String) -> String {
        let withoutControls = String(
            candidate.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            }
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        var migrated = ""
        for character in withoutControls {
            let next = migrated + String(character)
            guard next.utf8.count <= DeviceNamePacketCodec.maximumUTF8Bytes
            else { break }
            migrated = next
        }
        return normalized(migrated) ?? "ESPNoise Device"
    }

    static func isHardwareDefaultName(_ name: String) -> Bool {
        guard name.hasPrefix("Device ") else { return false }
        let suffix = name.dropFirst("Device ".count)
        return suffix.count == 4 && suffix.allSatisfy { $0.isHexDigit }
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
    var requiredTriggerSampleCount: UInt32 {
        guard samplePeriodMilliseconds > 0 else { return 0 }
        let historyCount = decisionWindowMilliseconds / samplePeriodMilliseconds
        return (historyCount * UInt32(triggerPercent) + 99) / 100
    }

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
        guard requiredTriggerSampleCount >= 2 else {
            throw NoiseSettingsValidationError.sporadicTrigger
        }
        guard (60...86_400).contains(muteDurationSeconds) else {
            throw NoiseSettingsValidationError.muteDuration
        }
        return self
    }
}
