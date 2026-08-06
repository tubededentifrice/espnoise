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
        XCTAssertEqual(bytes[0], 2)
        XCTAssertEqual(bytes[1], 1)
        XCTAssertEqual(bytes[2], 25)
        XCTAssertEqual(bytes[3], 80)
        XCTAssertEqual(Array(bytes[4..<6]), [0x0C, 0xFE])
        XCTAssertEqual(Array(bytes[22..<24]), [75, 0])
        XCTAssertEqual(Array(bytes[28..<32]), [0x78, 0x56, 0x34, 0x12])
    }

    func testConfigPacketDisablesAnalyticsCollection() throws {
        var settings = NoiseSettings()
        settings.analyticsEnabled = false
        let bytes = [UInt8](
            try ConfigPacketCodec.encode(settings: settings, revision: 1)
        )
        XCTAssertEqual(bytes[1], 0)
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

    func testThresholdSliderScaleNormalizesLegacyValues() {
        var settings = NoiseSettings()
        settings.greenThresholdTenths = -1_000
        settings.orangeThresholdTenths = -795
        settings.redThresholdTenths = 0
        let normalized = ThresholdSliderScale.normalizedSettings(settings)
        XCTAssertEqual(
            NoiseLevelScale.positiveLevel(
                fromDbfsTenths: normalized.greenThresholdTenths
            ),
            40
        )
        XCTAssertEqual(
            NoiseLevelScale.positiveLevel(
                fromDbfsTenths: normalized.orangeThresholdTenths
            ),
            41
        )
        XCTAssertEqual(
            NoiseLevelScale.positiveLevel(
                fromDbfsTenths: normalized.redThresholdTenths
            ),
            120
        )

        var overrides = DeviceOverrides()
        overrides.greenThresholdTenths = -1_000
        overrides.orangeThresholdTenths = -475
        let normalizedOverrides = ThresholdSliderScale.normalizedOverrides(
            overrides,
            global: NoiseSettings()
        )
        XCTAssertEqual(normalizedOverrides.greenThresholdTenths, -800)
        XCTAssertEqual(normalizedOverrides.orangeThresholdTenths, -470)
        XCTAssertEqual(ThresholdSliderScale.range, 40...120)
        XCTAssertEqual(ThresholdSliderScale.step, 1)

        var closeLegacyGlobal = NoiseSettings()
        closeLegacyGlobal.greenThresholdTenths = -800
        closeLegacyGlobal.orangeThresholdTenths = -795
        closeLegacyGlobal.redThresholdTenths = -790
        var closeLegacyOverrides = DeviceOverrides()
        closeLegacyOverrides.orangeThresholdTenths = -795
        let safeOverrides = ThresholdSliderScale.normalizedOverrides(
            closeLegacyOverrides,
            global: closeLegacyGlobal
        )
        XCTAssertNil(safeOverrides.greenThresholdTenths)
        XCTAssertNil(safeOverrides.orangeThresholdTenths)
        XCTAssertNil(safeOverrides.redThresholdTenths)
        XCTAssertNoThrow(
            try safeOverrides.applying(to: closeLegacyGlobal).validated()
        )

        var halfStepGlobal = NoiseSettings()
        halfStepGlobal.orangeThresholdTenths = -785
        var halfStepOverrides = DeviceOverrides()
        halfStepOverrides.greenThresholdTenths = -790
        let wholeStepOverrides = ThresholdSliderScale.normalizedOverrides(
            halfStepOverrides,
            global: halfStepGlobal
        )
        XCTAssertEqual(wholeStepOverrides.greenThresholdTenths, -800)
        XCTAssertEqual(
            wholeStepOverrides.greenThresholdTenths.map { $0 % 10 },
            0
        )
        XCTAssertNoThrow(
            try wholeStepOverrides.applying(to: halfStepGlobal).validated()
        )
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

    func testAnalyticsPacketHasExactLayoutAndRequest() throws {
        let bytes: [UInt8] = [
            2, 0,
            0x78, 0x56, 0x34, 0x12,
            0x00, 0xF1, 0x53, 0x65,
            0x84, 0x03,
            0x8A, 0x02,
            0x84, 0x03,
            60, 24, 6, 0,
        ]
        let packet = try AnalyticsPacketCodec.decode(Data(bytes))
        XCTAssertEqual(packet.protocolVersion, 2)
        XCTAssertEqual(packet.sequence, 0x1234_5678)
        XCTAssertEqual(packet.startUtcSeconds, 1_700_000_000)
        XCTAssertNil(packet.ageBuckets)
        XCTAssertEqual(packet.durationSeconds, 900)
        XCTAssertEqual(packet.meanLevel, 65)
        XCTAssertEqual(packet.peakLevel, 90)
        XCTAssertEqual(packet.greenSeconds, 300)
        XCTAssertEqual(packet.orangeSeconds, 120)
        XCTAssertEqual(packet.redSeconds, 30)
        XCTAssertFalse(packet.isPartial)

        XCTAssertEqual(
            [UInt8](AnalyticsPacketCodec.request(
                after: 0x1234_5678,
                currentDate: Date(timeIntervalSince1970: 1_700_000_000)
            )),
            [
                2, 1, 0x78, 0x56, 0x34, 0x12,
                0x00, 0xF1, 0x53, 0x65, 0, 0,
            ]
        )
    }

    func testAnalyticsPacketReadsLegacyFirmwareAndRequest() throws {
        let bytes: [UInt8] = [
            1, 0,
            0x78, 0x56, 0x34, 0x12,
            2, 0,
            0x84, 0x03,
            0x8A, 0x02,
            0x84, 0x03,
            0x2C, 0x01,
            120, 0,
            30, 0,
        ]
        let packet = try AnalyticsPacketCodec.decode(Data(bytes))
        XCTAssertEqual(packet.protocolVersion, 1)
        XCTAssertEqual(packet.ageBuckets, 2)
        XCTAssertEqual(packet.startUtcSeconds, 0)
        XCTAssertEqual(packet.greenSeconds, 300)
        XCTAssertEqual(packet.orangeSeconds, 120)
        XCTAssertEqual(packet.redSeconds, 30)
        XCTAssertEqual(
            [UInt8](AnalyticsPacketCodec.legacyRequest(after: 0x1234_5678)),
            [1, 1, 0x78, 0x56, 0x34, 0x12, 0, 0]
        )
    }

    func testAnalyticsPacketRejectsImpossibleStateTime() {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 2
        bytes[2] = 1
        bytes[6] = 0x00
        bytes[7] = 0xF1
        bytes[8] = 0x53
        bytes[9] = 0x65
        bytes[10] = 10
        bytes[16] = 3
        XCTAssertThrowsError(try AnalyticsPacketCodec.decode(Data(bytes)))
    }

    func testFleetAnalyticsUsesTimeWeightedValues() {
        let first = UUID()
        let second = UUID()
        let now = Date(timeIntervalSince1970: 100_000)
        let firstBucket = NoiseAnalyticsBucket(
            sequence: 1,
            startDate: now.addingTimeInterval(-900),
            endDate: now,
            meanLevel: 60,
            peakLevel: 80,
            greenSeconds: 300,
            orangeSeconds: 0,
            redSeconds: 0,
            isPartial: false
        )
        let secondBucket = NoiseAnalyticsBucket(
            sequence: 1,
            startDate: now.addingTimeInterval(-450),
            endDate: now,
            meanLevel: 90,
            peakLevel: 100,
            greenSeconds: 0,
            orangeSeconds: 0,
            redSeconds: 450,
            isPartial: true
        )
        let result = AnalyticsEngine.snapshot(
            recordsByDevice: [first: [firstBucket], second: [secondBucket]],
            selectedDeviceIDs: [first, second],
            names: [first: "First", second: "Second"],
            range: .day,
            now: now
        )
        XCTAssertEqual(result.meanLevel, 70, accuracy: 0.001)
        XCTAssertEqual(result.peakLevel, 100)
        XCTAssertEqual(result.warningPercent, 750 / 1_350 * 100, accuracy: 0.001)
        XCTAssertEqual(result.devices.first?.name, "Second")
        XCTAssertFalse(result.trend.isEmpty)
    }

    func testAnalyticsStoreReplacesPartialRecordAndPersists() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ESPNoiseAnalyticsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let deviceID = UUID()
        let now = Date()
        var store = AnalyticsStore(directory: directory)
        let partial = NoiseAnalyticsBucket(
            sequence: 4,
            startDate: now.addingTimeInterval(-60),
            endDate: now,
            meanLevel: 60,
            peakLevel: 70,
            greenSeconds: 10,
            orangeSeconds: 0,
            redSeconds: 0,
            isPartial: true
        )
        _ = store.upsert(partial, deviceID: deviceID, now: now)
        let complete = NoiseAnalyticsBucket(
            sequence: 4,
            startDate: now.addingTimeInterval(-900),
            endDate: now,
            meanLevel: 65,
            peakLevel: 80,
            greenSeconds: 300,
            orangeSeconds: 60,
            redSeconds: 0,
            isPartial: false
        )
        let updated = store.upsert(complete, deviceID: deviceID, now: now)
        XCTAssertEqual(updated, [complete])
        store.save(deviceID: deviceID)

        var restored = AnalyticsStore(directory: directory)
        let loaded = restored.load(deviceID: deviceID, now: now)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.sequence, complete.sequence)
        XCTAssertEqual(loaded.first?.meanLevel, complete.meanLevel)
        XCTAssertEqual(
            loaded.first?.startDate.timeIntervalSince1970 ?? 0,
            complete.startDate.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(
            loaded.first?.endDate.timeIntervalSince1970 ?? 0,
            complete.endDate.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(restored.lastCompletedSequence(deviceID: deviceID), 4)
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

    func testAnalyticsCollectionUsesGlobalValueAndDeviceOverride() throws {
        var global = store.record.globalSettings
        global.analyticsEnabled = false
        try store.updateGlobal(global)
        XCTAssertFalse(
            try XCTUnwrap(store.effectiveSettings(for: first))
                .analyticsEnabled
        )

        var overrides = DeviceOverrides()
        overrides.analyticsEnabled = true
        try store.updateDevice(id: first, name: "First", overrides: overrides)
        XCTAssertTrue(
            try XCTUnwrap(store.effectiveSettings(for: first))
                .analyticsEnabled
        )
        XCTAssertFalse(
            try XCTUnwrap(store.effectiveSettings(for: second))
                .analyticsEnabled
        )
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

    func testPersistenceUsesVersionedRecord() throws {
        var firstChange = store.record.globalSettings
        firstChange.buzzerPercent = 20
        try store.updateGlobal(firstChange)
        var finalChange = firstChange
        finalChange.buzzerPercent = 21
        try store.updateGlobal(finalChange)
        var overrides = DeviceOverrides()
        overrides.brightnessPercent = 12
        try store.updateDevice(
            id: first,
            name: "First",
            overrides: overrides
        )

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.record.schemaVersion, NoiseAppRecord.currentSchemaVersion)
        XCTAssertEqual(reloaded.record.devices.count, 2)
        XCTAssertEqual(reloaded.record.globalSettings.buzzerPercent, 21)
        XCTAssertEqual(
            reloaded.device(id: first)?.overrides.brightnessPercent,
            12
        )
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
        XCTAssertTrue(defaults.analyticsEnabled)
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
