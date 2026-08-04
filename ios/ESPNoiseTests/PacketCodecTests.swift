import XCTest
@testable import ESPNoise

final class PacketCodecTests: XCTestCase {
    func testConfigPacketHasExactLayout() throws {
        let settings = NoiseSettings(
            brightnessPercent: 25,
            buzzerPercent: 80,
            greenThresholdTenths: -500,
            orangeThresholdTenths: -350,
            redThresholdTenths: -200,
            sampleDurationMilliseconds: 40,
            samplePeriodMilliseconds: 100,
            decisionWindowMilliseconds: 4_000,
            triggerPercent: 75,
            muteDurationSeconds: 600
        )
        let data = try ConfigPacketCodec.encode(settings: settings, revision: 0x1234_5678)
        let bytes = [UInt8](data)
        XCTAssertEqual(bytes.count, 32)
        XCTAssertEqual(bytes[0], 1)
        XCTAssertEqual(bytes[1], 0)
        XCTAssertEqual(bytes[2], 25)
        XCTAssertEqual(bytes[3], 80)
        XCTAssertEqual(Array(bytes[4..<6]), [0x0C, 0xFE])
        XCTAssertEqual(Array(bytes[22..<24]), [75, 0])
        XCTAssertEqual(Array(bytes[28..<32]), [0x78, 0x56, 0x34, 0x12])
    }

    func testFNVUsesOnlyBytesZeroThroughTwentySeven() throws {
        let settings = NoiseSettings()
        let first = try ConfigPacketCodec.encode(settings: settings, revision: 1)
        let second = try ConfigPacketCodec.encode(settings: settings, revision: 999)
        XCTAssertEqual(
            ConfigPacketCodec.fnv1a32(first.prefix(28)),
            ConfigPacketCodec.fnv1a32(second.prefix(28))
        )
        XCTAssertEqual(
            try ConfigPacketCodec.fingerprint(settings: settings),
            ConfigPacketCodec.fnv1a32(first.prefix(28))
        )
    }

    func testFNVMatchesKnownVector() {
        XCTAssertEqual(
            ConfigPacketCodec.fnv1a32(Array("hello".utf8)),
            0x4F9F_2CAB
        )
    }

    func testInvalidBoundsAreRejected() {
        var settings = NoiseSettings()
        settings.brightnessPercent = 101
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))

        settings = NoiseSettings()
        settings.triggerPercent = 100
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))

        settings = NoiseSettings()
        settings.greenThresholdTenths = -100
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))

        settings = NoiseSettings()
        settings.sampleDurationMilliseconds = 200
        settings.samplePeriodMilliseconds = 100
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))

        settings = NoiseSettings()
        settings.decisionWindowMilliseconds = 60_001
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))

        settings = NoiseSettings()
        settings.samplePeriodMilliseconds = 1_000
        settings.decisionWindowMilliseconds = 1_000
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))

        settings = NoiseSettings()
        settings.muteDurationSeconds = 59
        XCTAssertThrowsError(try ConfigPacketCodec.encode(settings: settings, revision: 1))
    }

    func testStatusPacketDecodesLittleEndianFields() throws {
        let bytes: [UInt8] = [
            1, 3, 0x07, 4,
            0x78, 0x56, 0x34, 0x12,
            0xEF, 0xCD, 0xAB, 0x90,
            0x04, 0x03, 0x02, 0x01,
        ]
        let status = try StatusPacketCodec.decode(Data(bytes))
        XCTAssertEqual(status.state, .red)
        XCTAssertTrue(status.isMuted)
        XCTAssertTrue(status.isSampling)
        XCTAssertTrue(status.alarmIsActive)
        XCTAssertEqual(status.errorCode, 4)
        XCTAssertEqual(status.appliedRevision, 0x1234_5678)
        XCTAssertEqual(status.fingerprint, 0x90AB_CDEF)
        XCTAssertEqual(status.uptimeSeconds, 0x0102_0304)
        XCTAssertNil(status.observationMaximumTenths)
    }

    func testLiveStatusPacketDecodesMeasurementAndHistory() throws {
        let bytes: [UInt8] = [
            2, 2, 0x0A, 0,
            0x78, 0x56, 0x34, 0x12,
            0xEF, 0xCD, 0xAB, 0x90,
            0x20, 0xFE,
            0x34, 0x12,
            6, 4, 3, 1,
        ]
        let status = try StatusPacketCodec.decode(Data(bytes))
        XCTAssertEqual(status.state, .orange)
        XCTAssertTrue(status.isSampling)
        XCTAssertEqual(status.observationMaximumTenths, -480)
        XCTAssertEqual(status.measurementSequence, 0x1234)
        XCTAssertEqual(status.historyCount, 6)
        XCTAssertEqual(status.greenSampleCount, 4)
        XCTAssertEqual(status.orangeSampleCount, 3)
        XCTAssertEqual(status.redSampleCount, 1)
        XCTAssertNil(status.uptimeSeconds)
    }

    func testLiveStatusRejectsImpossibleHistoryCounts() {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 2
        bytes[12] = 0x20
        bytes[13] = 0xFE
        bytes[16] = 3
        bytes[17] = 4
        XCTAssertThrowsError(try StatusPacketCodec.decode(Data(bytes)))
    }

    func testPositiveNoiseLevelScaleRoundTrips() {
        XCTAssertEqual(NoiseLevelScale.positiveLevel(fromDbfsTenths: -1_200), 0)
        XCTAssertEqual(NoiseLevelScale.positiveLevel(fromDbfsTenths: -550), 65)
        XCTAssertEqual(NoiseLevelScale.positiveLevel(fromDbfsTenths: 0), 120)
        XCTAssertEqual(NoiseLevelScale.dbfsTenths(fromPositiveLevel: 72), -480)
    }

    func testTriggerPercentIncludesExactPercentage() throws {
        var settings = NoiseSettings()
        XCTAssertEqual(settings.requiredTriggerSampleCount, 3)

        settings.samplePeriodMilliseconds = 1_000
        settings.decisionWindowMilliseconds = 2_000
        settings.triggerPercent = 50
        XCTAssertEqual(settings.requiredTriggerSampleCount, 1)
        XCTAssertThrowsError(try settings.validated())

        settings.triggerPercent = 51
        XCTAssertEqual(settings.requiredTriggerSampleCount, 2)
        XCTAssertNoThrow(try settings.validated())
    }

    func testMeasurementHistoryRejectsDuplicatesAndAcceptsSequenceWrap() {
        var history = NoiseMeasurementHistory()
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(history.append(
            sequence: UInt16.max,
            maximumTenths: -500,
            at: now
        ))
        XCTAssertFalse(history.append(
            sequence: UInt16.max,
            maximumTenths: -400,
            at: now.addingTimeInterval(1)
        ))
        XCTAssertTrue(history.append(
            sequence: 0,
            maximumTenths: -400,
            at: now.addingTimeInterval(2)
        ))
        XCTAssertEqual(history.measurements.map(\.level), [70, 80])
    }

    func testMeasurementHistoryPrunesAfterFiveMinutesWithoutAppend() {
        var history = NoiseMeasurementHistory()
        let start = Date(timeIntervalSince1970: 1_000)
        history.append(sequence: 1, maximumTenths: -600, at: start)
        history.append(
            sequence: 2,
            maximumTenths: -500,
            at: start.addingTimeInterval(1)
        )
        XCTAssertTrue(history.prune(
            at: start.addingTimeInterval(
                NoiseMeasurementHistory.retentionSeconds
            )
        ))
        XCTAssertEqual(history.measurements.count, 1)
        XCTAssertTrue(history.prune(
            at: start.addingTimeInterval(
                NoiseMeasurementHistory.retentionSeconds + 1
            )
        ))
        XCTAssertTrue(history.measurements.isEmpty)
    }

    func testStatusLengthAndVersionAreChecked() {
        XCTAssertThrowsError(try StatusPacketCodec.decode(Data(repeating: 0, count: 15)))
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 2
        XCTAssertThrowsError(try StatusPacketCodec.decode(Data(bytes)))
    }

    func testDeviceNamePacketUsesExactTwentyByteLayout() throws {
        let packet = try DeviceNamePacketCodec.encode(name: "Café")
        let bytes = [UInt8](packet)
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(bytes[0], 1)
        XCTAssertEqual(bytes[1], 5)
        XCTAssertEqual(Array(bytes[2..<7]), [0x43, 0x61, 0x66, 0xC3, 0xA9])
        XCTAssertTrue(bytes[7...].allSatisfy { $0 == 0 })
        XCTAssertEqual(try DeviceNamePacketCodec.decode(packet), "Café")
    }

    func testDeviceNameQueryUsesZeroLengthPacket() {
        let bytes = [UInt8](DeviceNamePacketCodec.queryPacket)
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(bytes[0], 1)
        XCTAssertTrue(bytes[1...].allSatisfy { $0 == 0 })
        XCTAssertThrowsError(
            try DeviceNamePacketCodec.decode(
                DeviceNamePacketCodec.queryPacket
            )
        )
    }

    func testDeviceNamePacketRejectsInvalidUTF8AndPadding() throws {
        var bytes = [UInt8](try DeviceNamePacketCodec.encode(name: "Office"))
        bytes[2] = 0x07
        XCTAssertThrowsError(try DeviceNamePacketCodec.decode(Data(bytes)))

        bytes = [UInt8](try DeviceNamePacketCodec.encode(name: "Office"))
        bytes[19] = 1
        XCTAssertThrowsError(try DeviceNamePacketCodec.decode(Data(bytes)))
    }
}

final class SettingsStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: SettingsStore!
    private let first = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let second = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    override func setUp() {
        suiteName = "ESPNoiseTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = SettingsStore(defaults: defaults)
        store.reconcileDevice(id: first, suggestedName: "First")
        store.reconcileDevice(id: second, suggestedName: "Second")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
    }

    func testInheritanceAndSparseOverrides() throws {
        var overrides = DeviceOverrides()
        overrides.buzzerPercent = 10
        try store.updateDevice(id: first, name: "First", overrides: overrides)
        let effective = try XCTUnwrap(store.effectiveSettings(for: first))
        XCTAssertEqual(effective.buzzerPercent, 10)
        XCTAssertEqual(effective.brightnessPercent, store.record.globalSettings.brightnessPercent)
        XCTAssertNil(store.device(id: first)?.overrides.brightnessPercent)
    }

    func testGlobalChangeDoesNotMarkOverriddenDevicePending() throws {
        var overrides = DeviceOverrides()
        overrides.brightnessPercent = 10
        try store.updateDevice(id: first, name: "First", overrides: overrides)
        let firstRevision = try XCTUnwrap(store.device(id: first)?.desiredRevision)
        let secondRevision = try XCTUnwrap(store.device(id: second)?.desiredRevision)
        var global = store.record.globalSettings
        global.brightnessPercent = 15
        try store.updateGlobal(global)
        XCTAssertEqual(store.device(id: first)?.desiredRevision, firstRevision)
        XCTAssertNotEqual(store.device(id: second)?.desiredRevision, secondRevision)
    }

    func testGlobalSamplingChangeMarksAllDevicesPending() throws {
        let firstRevision = store.device(id: first)?.desiredRevision
        let secondRevision = store.device(id: second)?.desiredRevision
        var global = store.record.globalSettings
        global.decisionWindowMilliseconds += global.samplePeriodMilliseconds
        try store.updateGlobal(global)
        XCTAssertNotEqual(store.device(id: first)?.desiredRevision, firstRevision)
        XCTAssertNotEqual(store.device(id: second)?.desiredRevision, secondRevision)
    }

    func testMatchingRevisionAndFingerprintClearPending() throws {
        store.adoptNameFromDevice(
            id: first,
            name: "First",
            at: Date(timeIntervalSince1970: 500)
        )
        let device = try XCTUnwrap(store.device(id: first))
        let settings = try XCTUnwrap(store.effectiveSettings(for: first))
        let fingerprint = try ConfigPacketCodec.fingerprint(settings: settings)
        XCTAssertTrue(store.isPending(id: first))
        store.markSynced(
            id: first,
            revision: device.desiredRevision,
            fingerprint: fingerprint,
            at: Date()
        )
        XCTAssertFalse(store.isPending(id: first))
        store.markSynced(
            id: first,
            revision: device.desiredRevision - 1,
            fingerprint: fingerprint,
            at: Date()
        )
        XCTAssertFalse(store.isPending(id: first))
    }

    func testPersistenceUsesVersionedRecord() {
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.record.schemaVersion, NoiseAppRecord.currentSchemaVersion)
        XCTAssertEqual(reloaded.record.devices.count, 2)
    }

    func testNameValidation() {
        XCTAssertEqual(DeviceNameValidation.normalized("  Main Desk  "), "Main Desk")
        XCTAssertNil(DeviceNameValidation.normalized(""))
        XCTAssertNotNil(DeviceNameValidation.normalized(String(repeating: "a", count: 18)))
        XCTAssertNil(DeviceNameValidation.normalized(String(repeating: "a", count: 19)))
        XCTAssertNil(DeviceNameValidation.normalized("Bad\u{0007}Name"))
        XCTAssertNil(DeviceNameValidation.normalizedUserName("Device B9EC"))
        XCTAssertEqual(
            DeviceNameValidation.migratedLegacyName(
                "A long legacy conference room name"
            ),
            "A long legacy conf"
        )
    }

    func testLongLegacyNameIsMigratedAndMarkedPending() throws {
        var legacy = NoiseAppRecord()
        legacy.devices = [
            NoiseDeviceRecord(
                id: first,
                customName: "A long legacy conference room name",
                desiredRevision: 1,
                lastSuccessfulSync: nil,
                lastAppliedRevision: nil,
                lastAppliedFingerprint: nil,
                nameSyncPending: nil,
                lastConfirmedName: nil
            )
        ]
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "ESPNoise.settingsRecord"
        )

        let migrated = SettingsStore(defaults: defaults)
        let device = try XCTUnwrap(migrated.device(id: first))
        XCTAssertEqual(device.customName, "A long legacy conf")
        XCTAssertTrue(migrated.nameNeedsSync(id: first))
        XCTAssertLessThanOrEqual(device.customName.utf8.count, 18)
    }

    func testLegacyHardwareNameWaitsForDeviceRead() throws {
        var legacy = NoiseAppRecord()
        legacy.devices = [
            NoiseDeviceRecord(
                id: first,
                customName: "Device B9EC",
                desiredRevision: 1,
                lastSuccessfulSync: nil,
                lastAppliedRevision: nil,
                lastAppliedFingerprint: nil,
                nameSyncPending: nil,
                lastConfirmedName: nil
            )
        ]
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "ESPNoise.settingsRecord"
        )

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertFalse(migrated.nameNeedsSync(id: first))
        XCTAssertFalse(migrated.nameIsConfirmed(id: first))
        XCTAssertTrue(migrated.isPending(id: first))
    }

    func testFreshDeviceCompletesOnlyAfterNameRead() throws {
        let device = try XCTUnwrap(store.device(id: first))
        let settings = try XCTUnwrap(store.effectiveSettings(for: first))
        let fingerprint = try ConfigPacketCodec.fingerprint(settings: settings)
        let settingsDate = Date(timeIntervalSince1970: 1_000)
        store.markSynced(
            id: first,
            revision: device.desiredRevision,
            fingerprint: fingerprint,
            at: settingsDate
        )
        XCTAssertNil(store.device(id: first)?.lastSuccessfulSync)
        XCTAssertTrue(store.isPending(id: first))

        let nameDate = Date(timeIntervalSince1970: 2_000)
        store.adoptNameFromDevice(id: first, name: "First", at: nameDate)
        XCTAssertEqual(store.device(id: first)?.lastSuccessfulSync, nameDate)
        XCTAssertFalse(store.isPending(id: first))
    }

    func testLastSyncChangesOnlyAfterAllValuesAreComplete() throws {
        let firstDate = Date(timeIntervalSince1970: 1_000)
        store.markNameSynced(id: first, name: "First", at: firstDate)
        XCTAssertNil(store.device(id: first)?.lastSuccessfulSync)

        let device = try XCTUnwrap(store.device(id: first))
        let settings = try XCTUnwrap(store.effectiveSettings(for: first))
        let fingerprint = try ConfigPacketCodec.fingerprint(settings: settings)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        store.markSynced(
            id: first,
            revision: device.desiredRevision,
            fingerprint: fingerprint,
            at: secondDate
        )
        XCTAssertEqual(store.device(id: first)?.lastSuccessfulSync, secondDate)

        try store.updateDevice(
            id: first,
            name: "Meeting Room",
            overrides: DeviceOverrides()
        )
        var global = store.record.globalSettings
        global.buzzerPercent += 1
        try store.updateGlobal(global)
        let pending = try XCTUnwrap(store.device(id: first))
        let newSettings = try XCTUnwrap(store.effectiveSettings(for: first))
        let newFingerprint = try ConfigPacketCodec.fingerprint(
            settings: newSettings
        )
        let thirdDate = Date(timeIntervalSince1970: 3_000)
        store.markSynced(
            id: first,
            revision: pending.desiredRevision,
            fingerprint: newFingerprint,
            at: thirdDate
        )
        XCTAssertEqual(store.device(id: first)?.lastSuccessfulSync, secondDate)

        let fourthDate = Date(timeIntervalSince1970: 4_000)
        store.markNameSynced(
            id: first,
            name: "Meeting Room",
            at: fourthDate
        )
        XCTAssertEqual(store.device(id: first)?.lastSuccessfulSync, fourthDate)
    }

    func testNameOnlyChangeHasIndependentPendingState() throws {
        var savedOverrides = DeviceOverrides()
        savedOverrides.brightnessPercent = 10
        try store.updateDevice(
            id: first,
            name: "First",
            overrides: savedOverrides
        )
        let revision = try XCTUnwrap(store.device(id: first)?.desiredRevision)
        XCTAssertFalse(store.nameNeedsSync(id: first))
        store.updateDeviceName(id: first, name: "Meeting Room")
        XCTAssertEqual(store.device(id: first)?.desiredRevision, revision)
        XCTAssertEqual(
            store.device(id: first)?.overrides.brightnessPercent,
            10
        )
        XCTAssertTrue(store.nameNeedsSync(id: first))
        store.markNameSynced(id: first, name: "Meeting Room", at: Date())
        XCTAssertFalse(store.nameNeedsSync(id: first))
        XCTAssertEqual(store.device(id: first)?.lastConfirmedName, "Meeting Room")
    }

    func testFreshPhoneAdoptsNameAndConfirmedPhoneRestoresAfterErase() throws {
        store.adoptNameFromDevice(
            id: first,
            name: "Quiet Room",
            at: Date()
        )
        XCTAssertEqual(store.device(id: first)?.customName, "Quiet Room")
        XCTAssertFalse(store.nameNeedsSync(id: first))

        try store.updateDevice(
            id: first,
            name: "Main Room",
            overrides: DeviceOverrides()
        )
        store.markNameSynced(id: first, name: "Main Room", at: Date())
        store.adoptNameFromDevice(
            id: first,
            name: "Device B9EC",
            at: Date()
        )
        XCTAssertEqual(store.device(id: first)?.customName, "Main Room")
        XCTAssertTrue(store.nameNeedsSync(id: first))
    }

    func testConfirmedPhoneAdoptsLaterRemoteCustomName() throws {
        try store.updateDevice(
            id: first,
            name: "Main Room",
            overrides: DeviceOverrides()
        )
        store.markNameSynced(id: first, name: "Main Room", at: Date())
        store.adoptNameFromDevice(
            id: first,
            name: "Quiet Room",
            at: Date()
        )

        XCTAssertEqual(store.device(id: first)?.customName, "Quiet Room")
        XCTAssertFalse(store.nameNeedsSync(id: first))
    }

    func testGlobalDefaultsKeepDeviceOverrides() throws {
        var overrides = DeviceOverrides()
        overrides.buzzerPercent = 10
        try store.updateDevice(id: first, name: "First", overrides: overrides)
        var changed = NoiseSettings()
        changed.buzzerPercent = 80
        try store.updateGlobal(changed)
        try store.updateGlobal(NoiseSettings())
        XCTAssertEqual(store.record.globalSettings, NoiseSettings())
        XCTAssertEqual(store.device(id: first)?.overrides.buzzerPercent, 10)
    }

    func testProductDefaultsMatchFirmwareDefaults() {
        let defaults = NoiseSettings()
        XCTAssertEqual(defaults.brightnessPercent, 100)
        XCTAssertEqual(defaults.buzzerPercent, 50)
        XCTAssertEqual(defaults.greenThresholdTenths, -550)
        XCTAssertEqual(defaults.orangeThresholdTenths, -480)
        XCTAssertEqual(defaults.redThresholdTenths, -420)
        XCTAssertEqual(defaults.sampleDurationMilliseconds, 1_000)
        XCTAssertEqual(defaults.samplePeriodMilliseconds, 10_000)
        XCTAssertEqual(defaults.decisionWindowMilliseconds, 60_000)
        XCTAssertEqual(defaults.triggerPercent, 50)
        XCTAssertEqual(defaults.muteDurationSeconds, 1_800)
    }

    func testGlobalChangeRejectsAnInvalidEffectiveOverride() throws {
        var overrides = DeviceOverrides()
        overrides.greenThresholdTenths = -500
        try store.updateDevice(id: first, name: "First", overrides: overrides)
        var global = store.record.globalSettings
        global.orangeThresholdTenths = -520
        XCTAssertThrowsError(try store.updateGlobal(global))
    }
}
