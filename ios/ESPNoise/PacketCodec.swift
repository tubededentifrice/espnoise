import Foundation

enum PacketCodecError: LocalizedError, Equatable {
    case invalidLength
    case unsupportedVersion
    case invalidSettings

    var errorDescription: String? {
        switch self {
        case .invalidLength: "The Bluetooth packet has an incorrect length."
        case .unsupportedVersion: "The Bluetooth packet version is not supported."
        case .invalidSettings: "One or more settings are outside the supported range."
        }
    }
}

enum AlarmState: UInt8, Codable, Sendable {
    case quiet = 0
    case green = 1
    case orange = 2
    case red = 3

    var label: String {
        switch self {
        case .quiet: "Quiet"
        case .green: "Green"
        case .orange: "Orange"
        case .red: "Red"
        }
    }
}

struct DeviceStatus: Equatable, Sendable {
    let state: AlarmState
    let isMuted: Bool
    let isSampling: Bool
    let alarmIsActive: Bool
    let errorCode: UInt8
    let appliedRevision: UInt32
    let fingerprint: UInt32
    let uptimeSeconds: UInt32?
    let observationMaximumTenths: Int16?
    let measurementSequence: UInt16?
    let historyCount: UInt8
    let greenSampleCount: UInt8
    let orangeSampleCount: UInt8
    let redSampleCount: UInt8
}

enum ConfigPacketCodec {
    static let packetLength = 32

    static func encode(settings: NoiseSettings, revision: UInt32) throws -> Data {
        do { _ = try settings.validated() } catch { throw PacketCodecError.invalidSettings }
        var bytes = [UInt8](repeating: 0, count: packetLength)
        bytes[0] = 1
        bytes[2] = settings.brightnessPercent
        bytes[3] = settings.buzzerPercent
        put(UInt16(bitPattern: settings.greenThresholdTenths), at: 4, in: &bytes)
        put(UInt16(bitPattern: settings.orangeThresholdTenths), at: 6, in: &bytes)
        put(UInt16(bitPattern: settings.redThresholdTenths), at: 8, in: &bytes)
        put(settings.sampleDurationMilliseconds, at: 10, in: &bytes)
        put(settings.samplePeriodMilliseconds, at: 14, in: &bytes)
        put(settings.decisionWindowMilliseconds, at: 18, in: &bytes)
        bytes[22] = settings.triggerPercent
        put(settings.muteDurationSeconds, at: 24, in: &bytes)
        put(revision, at: 28, in: &bytes)
        return Data(bytes)
    }

    static func fingerprint(settings: NoiseSettings) throws -> UInt32 {
        let packet = try encode(settings: settings, revision: 0)
        return fnv1a32(packet.prefix(28))
    }

    static func fnv1a32<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        bytes.reduce(UInt32(2_166_136_261)) { hash, byte in
            (hash ^ UInt32(byte)) &* 16_777_619
        }
    }

    private static func put(_ value: UInt16, at offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private static func put(_ value: UInt32, at offset: Int, in bytes: inout [UInt8]) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
        }
    }
}

enum StatusPacketCodec {
    static func decode(_ data: Data) throws -> DeviceStatus {
        let bytes = [UInt8](data)
        guard let version = bytes.first else { throw PacketCodecError.invalidLength }
        switch version {
        case 1:
            return try decodeVersion1(bytes)
        case 2:
            return try decodeVersion2(bytes)
        default:
            throw PacketCodecError.unsupportedVersion
        }
    }

    private static func decodeVersion1(_ bytes: [UInt8]) throws -> DeviceStatus {
        guard bytes.count == 16 else { throw PacketCodecError.invalidLength }
        return try commonStatus(
            bytes,
            uptimeSeconds: uint32(bytes, at: 12),
            observationMaximumTenths: nil,
            measurementSequence: nil,
            historyCount: 0,
            greenSampleCount: 0,
            orangeSampleCount: 0,
            redSampleCount: 0
        )
    }

    private static func decodeVersion2(_ bytes: [UInt8]) throws -> DeviceStatus {
        guard bytes.count == 20 else { throw PacketCodecError.invalidLength }
        let measurementIsValid = bytes[2] & 0x08 != 0
        let maximum = int16(bytes, at: 12)
        let historyCount = bytes[16]
        let greenCount = bytes[17]
        let orangeCount = bytes[18]
        let redCount = bytes[19]
        guard historyCount <= 120,
              greenCount <= historyCount,
              orangeCount <= greenCount,
              redCount <= orangeCount,
              !measurementIsValid || (-1_200...0).contains(maximum) else {
            throw PacketCodecError.invalidSettings
        }
        return try commonStatus(
            bytes,
            uptimeSeconds: nil,
            observationMaximumTenths: measurementIsValid ? maximum : nil,
            measurementSequence: measurementIsValid ? uint16(bytes, at: 14) : nil,
            historyCount: historyCount,
            greenSampleCount: greenCount,
            orangeSampleCount: orangeCount,
            redSampleCount: redCount
        )
    }

    private static func commonStatus(
        _ bytes: [UInt8],
        uptimeSeconds: UInt32?,
        observationMaximumTenths: Int16?,
        measurementSequence: UInt16?,
        historyCount: UInt8,
        greenSampleCount: UInt8,
        orangeSampleCount: UInt8,
        redSampleCount: UInt8
    ) throws -> DeviceStatus {
        guard let state = AlarmState(rawValue: bytes[1]) else {
            throw PacketCodecError.invalidSettings
        }
        return DeviceStatus(
            state: state,
            isMuted: bytes[2] & 0x01 != 0,
            isSampling: bytes[2] & 0x02 != 0,
            alarmIsActive: bytes[2] & 0x04 != 0,
            errorCode: bytes[3],
            appliedRevision: uint32(bytes, at: 4),
            fingerprint: uint32(bytes, at: 8),
            uptimeSeconds: uptimeSeconds,
            observationMaximumTenths: observationMaximumTenths,
            measurementSequence: measurementSequence,
            historyCount: historyCount,
            greenSampleCount: greenSampleCount,
            orangeSampleCount: orangeSampleCount,
            redSampleCount: redSampleCount
        )
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func int16(_ bytes: [UInt8], at offset: Int) -> Int16 {
        Int16(bitPattern: uint16(bytes, at: offset))
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { value, index in
            value | (UInt32(bytes[offset + index]) << (index * 8))
        }
    }
}
