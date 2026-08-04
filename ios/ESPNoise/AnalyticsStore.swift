import Foundation

struct AnalyticsStore {
    static let retentionSeconds: TimeInterval = 30 * 24 * 60 * 60

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var records: [UUID: [NoiseAnalyticsBucket]] = [:]

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ESPNoiseAnalytics", isDirectory: true)
        self.directory = base
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
    }

    mutating func load(deviceID: UUID, now: Date = Date()) -> [NoiseAnalyticsBucket] {
        if let existing = records[deviceID] { return existing }
        let loaded: [NoiseAnalyticsBucket]
        if let data = try? Data(contentsOf: fileURL(for: deviceID)),
           let decoded = try? decoder.decode([NoiseAnalyticsBucket].self, from: data) {
            loaded = retained(decoded, now: now)
        } else {
            loaded = []
        }
        records[deviceID] = loaded
        return loaded
    }

    mutating func upsert(
        _ bucket: NoiseAnalyticsBucket,
        deviceID: UUID,
        now: Date = Date()
    ) -> [NoiseAnalyticsBucket] {
        var current = load(deviceID: deviceID, now: now)
        if let index = current.firstIndex(where: { $0.sequence == bucket.sequence }) {
            current[index] = bucket
        } else {
            current.append(bucket)
        }
        current = retained(current, now: now)
        records[deviceID] = current
        return current
    }

    mutating func lastCompletedSequence(deviceID: UUID) -> UInt32 {
        load(deviceID: deviceID)
            .filter { !$0.isPartial }
            .max(by: { $0.endDate < $1.endDate })?
            .sequence ?? 0
    }

    func save(deviceID: UUID) {
        guard let current = records[deviceID],
              let data = try? encoder.encode(current) else { return }
        let url = fileURL(for: deviceID)
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            return
        }
    }

    mutating func remove(deviceID: UUID) {
        records.removeValue(forKey: deviceID)
        try? FileManager.default.removeItem(at: fileURL(for: deviceID))
    }

    private func retained(
        _ source: [NoiseAnalyticsBucket],
        now: Date
    ) -> [NoiseAnalyticsBucket] {
        let cutoff = now.addingTimeInterval(-Self.retentionSeconds)
        return source
            .filter { $0.endDate > cutoff }
            .sorted { $0.startDate < $1.startDate }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
