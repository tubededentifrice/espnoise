import Foundation

struct NoiseAnalyticsPacket: Equatable, Sendable {
    static let bucketDurationSeconds: UInt16 = 15 * 60

    let sequence: UInt32
    let ageBuckets: UInt16
    let durationSeconds: UInt16
    let meanLevel: Double
    let peakLevel: Double
    let greenSeconds: UInt16
    let orangeSeconds: UInt16
    let redSeconds: UInt16
    let isPartial: Bool
}

enum AnalyticsPacketCodec {
    static let packetLength = 20
    static let requestLength = 8

    static func request(after sequence: UInt32) -> Data {
        var bytes = [UInt8](repeating: 0, count: requestLength)
        bytes[0] = 1
        bytes[1] = 1
        put(sequence, at: 2, in: &bytes)
        return Data(bytes)
    }

    static func decode(_ data: Data) throws -> NoiseAnalyticsPacket {
        let bytes = [UInt8](data)
        guard bytes.count == packetLength else {
            throw PacketCodecError.invalidLength
        }
        guard bytes[0] == 1 else {
            throw PacketCodecError.unsupportedVersion
        }
        let flags = bytes[1]
        guard flags & ~UInt8(0x01) == 0 else {
            throw PacketCodecError.invalidSettings
        }
        let sequence = uint32(bytes, at: 2)
        let age = uint16(bytes, at: 6)
        let duration = uint16(bytes, at: 8)
        let mean = uint16(bytes, at: 10)
        let peak = uint16(bytes, at: 12)
        let green = uint16(bytes, at: 14)
        let orange = uint16(bytes, at: 16)
        let red = uint16(bytes, at: 18)
        let isPartial = flags & 0x01 != 0
        guard sequence != 0,
              duration <= NoiseAnalyticsPacket.bucketDurationSeconds,
              mean <= peak, peak <= 1_200,
              UInt32(green) + UInt32(orange) + UInt32(red)
                <= UInt32(duration),
              (isPartial ? age == 0 : age > 0) else {
            throw PacketCodecError.invalidSettings
        }
        return NoiseAnalyticsPacket(
            sequence: sequence,
            ageBuckets: age,
            durationSeconds: duration,
            meanLevel: Double(mean) / 10,
            peakLevel: Double(peak) / 10,
            greenSeconds: green,
            orangeSeconds: orange,
            redSeconds: red,
            isPartial: isPartial
        )
    }

    static func sequenceIsAfter(_ sequence: UInt32, _ reference: UInt32) -> Bool {
        sequence != reference
            && Int32(bitPattern: sequence &- reference) > 0
    }

    private static func put(_ value: UInt32, at offset: Int, in bytes: inout [UInt8]) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8(
                truncatingIfNeeded: value >> (index * 8)
            )
        }
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { value, index in
            value | UInt32(bytes[offset + index]) << (index * 8)
        }
    }
}

struct NoiseAnalyticsBucket: Codable, Equatable, Identifiable, Sendable {
    var id: UInt32 { sequence }

    let sequence: UInt32
    let startDate: Date
    let endDate: Date
    let meanLevel: Double
    let peakLevel: Double
    let greenSeconds: Double
    let orangeSeconds: Double
    let redSeconds: Double
    let isPartial: Bool

    var durationSeconds: Double {
        max(0, endDate.timeIntervalSince(startDate))
    }

    var quietSeconds: Double {
        max(0, durationSeconds - greenSeconds - orangeSeconds - redSeconds)
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable, Sendable {
    case day = "24 hours"
    case week = "7 days"
    case month = "30 days"

    var id: Self { self }

    var seconds: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
    }
}

struct AnalyticsTrendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let meanLevel: Double
    let peakLevel: Double
    let quietSeconds: Double
    let greenSeconds: Double
    let orangeSeconds: Double
    let redSeconds: Double

    var id: Date { date }
}

struct DeviceAnalyticsSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let meanLevel: Double
    let peakLevel: Double
    let warningPercent: Double
    let redPercent: Double
    let deviceHours: Double
}

struct AnalyticsHeatCell: Identifiable, Equatable, Sendable {
    let weekday: Int
    let hour: Int
    let meanLevel: Double

    var id: String { "\(weekday)-\(hour)" }
    var weekdayLabel: String {
        Calendar.current.shortWeekdaySymbols[(weekday + 5) % 7]
    }
}

struct FleetAnalyticsSnapshot: Equatable, Sendable {
    var meanLevel = 0.0
    var peakLevel = 0.0
    var warningPercent = 0.0
    var redPercent = 0.0
    var deviceHours = 0.0
    var trend: [AnalyticsTrendPoint] = []
    var devices: [DeviceAnalyticsSummary] = []
    var heatmap: [AnalyticsHeatCell] = []

    var hasData: Bool { deviceHours > 0 }
}

enum AnalyticsEngine {
    private struct Accumulator {
        var weightedLevel = 0.0
        var duration = 0.0
        var peak = 0.0
        var quiet = 0.0
        var green = 0.0
        var orange = 0.0
        var red = 0.0

        mutating func add(_ bucket: NoiseAnalyticsBucket) {
            let seconds = bucket.durationSeconds
            guard seconds > 0 else { return }
            weightedLevel += bucket.meanLevel * seconds
            duration += seconds
            peak = max(peak, bucket.peakLevel)
            quiet += bucket.quietSeconds
            green += bucket.greenSeconds
            orange += bucket.orangeSeconds
            red += bucket.redSeconds
        }

        mutating func add(_ other: Accumulator) {
            weightedLevel += other.weightedLevel
            duration += other.duration
            peak = max(peak, other.peak)
            quiet += other.quiet
            green += other.green
            orange += other.orange
            red += other.red
        }

        var mean: Double { duration > 0 ? weightedLevel / duration : 0 }
        var warningPercent: Double {
            duration > 0 ? (green + orange + red) / duration * 100 : 0
        }
        var redPercent: Double { duration > 0 ? red / duration * 100 : 0 }
    }

    static func snapshot(
        recordsByDevice: [UUID: [NoiseAnalyticsBucket]],
        selectedDeviceIDs: Set<UUID>,
        names: [UUID: String],
        range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FleetAnalyticsSnapshot {
        let cutoff = now.addingTimeInterval(-range.seconds)
        var fleet = Accumulator()
        var timeBins: [Date: Accumulator] = [:]
        var deviceSummaries: [DeviceAnalyticsSummary] = []
        var heatBins: [String: Accumulator] = [:]

        for id in selectedDeviceIDs {
            var device = Accumulator()
            for bucket in recordsByDevice[id] ?? []
            where bucket.endDate > cutoff && bucket.startDate < now {
                device.add(bucket)
                let binDate = trendBin(
                    for: bucket.startDate,
                    range: range,
                    calendar: calendar
                )
                timeBins[binDate, default: Accumulator()].add(bucket)
                let components = calendar.dateComponents(
                    [.weekday, .hour],
                    from: bucket.startDate
                )
                if let weekday = components.weekday,
                   let hour = components.hour {
                    heatBins["\(weekday)-\(hour)", default: Accumulator()]
                        .add(bucket)
                }
            }
            fleet.add(device)
            if device.duration > 0 {
                deviceSummaries.append(
                    DeviceAnalyticsSummary(
                        id: id,
                        name: names[id] ?? "Device",
                        meanLevel: device.mean,
                        peakLevel: device.peak,
                        warningPercent: device.warningPercent,
                        redPercent: device.redPercent,
                        deviceHours: device.duration / 3_600
                    )
                )
            }
        }

        let trend = timeBins.map { date, value in
            AnalyticsTrendPoint(
                date: date,
                meanLevel: value.mean,
                peakLevel: value.peak,
                quietSeconds: value.quiet,
                greenSeconds: value.green,
                orangeSeconds: value.orange,
                redSeconds: value.red
            )
        }.sorted { $0.date < $1.date }

        let heatmap = heatBins.compactMap { key, value -> AnalyticsHeatCell? in
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, value.duration > 0 else { return nil }
            return AnalyticsHeatCell(
                weekday: parts[0],
                hour: parts[1],
                meanLevel: value.mean
            )
        }.sorted {
            ($0.weekday, $0.hour) < ($1.weekday, $1.hour)
        }

        return FleetAnalyticsSnapshot(
            meanLevel: fleet.mean,
            peakLevel: fleet.peak,
            warningPercent: fleet.warningPercent,
            redPercent: fleet.redPercent,
            deviceHours: fleet.duration / 3_600,
            trend: trend,
            devices: deviceSummaries.sorted {
                if $0.warningPercent == $1.warningPercent {
                    return $0.name.localizedCaseInsensitiveCompare($1.name)
                        == .orderedAscending
                }
                return $0.warningPercent > $1.warningPercent
            },
            heatmap: heatmap
        )
    }

    private static func trendBin(
        for date: Date,
        range: AnalyticsRange,
        calendar: Calendar
    ) -> Date {
        let day = calendar.startOfDay(for: date)
        switch range {
        case .day:
            let hour = calendar.component(.hour, from: date)
            return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        case .week:
            let hour = calendar.component(.hour, from: date)
            return calendar.date(
                byAdding: .hour,
                value: (hour / 6) * 6,
                to: day
            ) ?? day
        case .month:
            return day
        }
    }
}
