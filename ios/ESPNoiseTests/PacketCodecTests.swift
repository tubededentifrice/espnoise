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
    }

    func testStatusLengthAndVersionAreChecked() {
        XCTAssertThrowsError(try StatusPacketCodec.decode(Data(repeating: 0, count: 15)))
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 2
        XCTAssertThrowsError(try StatusPacketCodec.decode(Data(bytes)))
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
        XCTAssertNil(DeviceNameValidation.normalized(String(repeating: "a", count: 41)))
        XCTAssertNil(DeviceNameValidation.normalized("Bad\u{0007}Name"))
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
