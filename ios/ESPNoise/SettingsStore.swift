import Foundation

struct SettingsStore {
    private enum Keys {
        static let record = "ESPNoise.settingsRecord"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var record: NoiseAppRecord

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.record),
           let decoded = try? decoder.decode(NoiseAppRecord.self, from: data),
           decoded.schemaVersion == NoiseAppRecord.currentSchemaVersion {
            record = decoded
            var migrated = false
            for index in record.devices.indices
            where record.devices[index].nameSyncPending == nil
                && DeviceNameValidation.isHardwareDefaultName(
                    record.devices[index].customName
                ) {
                record.devices[index].nameSyncPending = false
                record.devices[index].lastConfirmedName = nil
                migrated = true
            }
            for index in record.devices.indices
            where DeviceNameValidation.normalized(
                record.devices[index].customName
            ) == nil {
                record.devices[index].customName =
                    DeviceNameValidation.migratedLegacyName(
                        record.devices[index].customName
                    )
                record.devices[index].lastConfirmedName = nil
                record.devices[index].nameSyncPending = true
                migrated = true
            }
            if migrated,
               let migratedData = try? encoder.encode(record) {
                defaults.set(migratedData, forKey: Keys.record)
            }
        } else {
            record = NoiseAppRecord()
        }
    }

    mutating func reconcileDevice(id: UUID, suggestedName: String) {
        guard !record.devices.contains(where: { $0.id == id }) else { return }
        let suffix = suggestedName.hasPrefix("ESPNoise-")
            ? String(suggestedName.dropFirst("ESPNoise-".count))
            : suggestedName
        let name = DeviceNameValidation.normalized(suffix) ?? "ESPNoise Device"
        record.devices.append(
            NoiseDeviceRecord(
                id: id,
                customName: name,
                desiredRevision: allocateRevision(),
                nameSyncPending: false
            )
        )
        save()
    }

    mutating func updateGlobal(_ settings: NoiseSettings) throws {
        let valid = try settings.validated()
        for device in record.devices {
            _ = try device.overrides.applying(to: valid).validated()
        }
        let oldGlobal = record.globalSettings
        guard oldGlobal != valid else { return }
        let affected = record.devices.indices.filter {
            record.devices[$0].overrides.applying(to: oldGlobal)
                != record.devices[$0].overrides.applying(to: valid)
        }
        record.globalSettings = valid
        for index in affected {
            record.devices[index].desiredRevision = allocateRevision()
        }
        save()
    }

    mutating func updateDevice(
        id: UUID,
        name: String,
        overrides: DeviceOverrides
    ) throws {
        guard let index = record.devices.firstIndex(where: { $0.id == id }),
              let cleanName = DeviceNameValidation.normalizedUserName(name)
        else { return }
        let oldEffective = effectiveSettings(for: id)
        let newEffective = overrides.applying(to: record.globalSettings)
        _ = try newEffective.validated()
        if record.devices[index].customName != cleanName {
            record.devices[index].customName = cleanName
            record.devices[index].nameSyncPending = true
        }
        record.devices[index].overrides = overrides
        if oldEffective != newEffective {
            record.devices[index].desiredRevision = allocateRevision()
        }
        save()
    }

    mutating func resetOverrides(id: UUID) throws {
        guard let device = record.devices.first(where: { $0.id == id }) else { return }
        try updateDevice(id: id, name: device.customName, overrides: DeviceOverrides())
    }

    mutating func markSynced(
        id: UUID,
        revision: UInt32,
        fingerprint: UInt32,
        at date: Date
    ) {
        guard let index = record.devices.firstIndex(where: { $0.id == id }),
              record.devices[index].desiredRevision == revision else { return }
        record.devices[index].lastAppliedRevision = revision
        record.devices[index].lastAppliedFingerprint = fingerprint
        if nameIsConfirmed(id: id) {
            record.devices[index].lastSuccessfulSync = date
        }
        save()
    }

    mutating func adoptNameFromDevice(id: UUID, name: String, at date: Date) {
        guard let index = record.devices.firstIndex(where: { $0.id == id }),
              let cleanName = DeviceNameValidation.normalized(name),
              !nameNeedsSync(id: id) else { return }
        let recordName = record.devices[index].customName
        let confirmedName = record.devices[index].lastConfirmedName
        if let confirmedName,
           cleanName != confirmedName,
           DeviceNameValidation.isHardwareDefaultName(cleanName),
           !DeviceNameValidation.isHardwareDefaultName(recordName) {
            record.devices[index].nameSyncPending = true
        } else {
            record.devices[index].customName = cleanName
            record.devices[index].lastConfirmedName = cleanName
            record.devices[index].nameSyncPending = false
            if !settingsArePending(id: id) {
                record.devices[index].lastSuccessfulSync = date
            }
        }
        save()
    }

    mutating func markNameSynced(id: UUID, name: String, at date: Date) {
        guard let index = record.devices.firstIndex(where: { $0.id == id }),
              record.devices[index].customName == name else { return }
        record.devices[index].nameSyncPending = false
        record.devices[index].lastConfirmedName = name
        if !settingsArePending(id: id) {
            record.devices[index].lastSuccessfulSync = date
        }
        save()
    }

    mutating func removeDevice(id: UUID) {
        record.devices.removeAll { $0.id == id }
        save()
    }

    func device(id: UUID) -> NoiseDeviceRecord? {
        record.devices.first { $0.id == id }
    }

    func effectiveSettings(for id: UUID) -> NoiseSettings? {
        device(id: id)?.overrides.applying(to: record.globalSettings)
    }

    func settingsArePending(id: UUID) -> Bool {
        guard let device = device(id: id),
              let settings = effectiveSettings(for: id),
              let fingerprint = try? ConfigPacketCodec.fingerprint(settings: settings)
        else { return true }
        return device.lastAppliedRevision != device.desiredRevision
            || device.lastAppliedFingerprint != fingerprint
    }

    func nameNeedsSync(id: UUID) -> Bool {
        guard let device = device(id: id) else { return true }
        return device.nameSyncPending ?? true
    }

    func nameIsConfirmed(id: UUID) -> Bool {
        guard let device = device(id: id) else { return false }
        return !nameNeedsSync(id: id)
            && device.lastConfirmedName == device.customName
    }

    func isPending(id: UUID) -> Bool {
        settingsArePending(id: id) || nameNeedsSync(id: id)
            || !nameIsConfirmed(id: id)
    }

    private mutating func allocateRevision() -> UInt32 {
        let revision = max(record.nextRevision, 1)
        record.nextRevision = revision == UInt32.max ? 1 : revision + 1
        return revision
    }

    private func save() {
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: Keys.record)
    }
}
