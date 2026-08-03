import AccessorySetupKit
@preconcurrency import CoreBluetooth
import Foundation
import os
import UIKit

struct NoiseMeasurement: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let level: Double
}

struct NoiseMeasurementHistory: Equatable, Sendable {
    static let retentionSeconds: TimeInterval = 300
    static let maximumPointCount = 180

    private(set) var measurements: [NoiseMeasurement] = []
    private(set) var lastSequence: UInt16?

    @discardableResult
    mutating func append(
        sequence: UInt16,
        maximumTenths: Int16,
        at date: Date
    ) -> Bool {
        guard sequence != lastSequence else { return false }
        lastSequence = sequence
        measurements.append(
            NoiseMeasurement(
                id: UUID(),
                date: date,
                level: NoiseLevelScale.positiveLevel(
                    fromDbfsTenths: maximumTenths
                )
            )
        )
        prune(at: date)
        if measurements.count > Self.maximumPointCount {
            measurements.removeFirst(
                measurements.count - Self.maximumPointCount
            )
        }
        return true
    }

    @discardableResult
    mutating func prune(at date: Date) -> Bool {
        let previousCount = measurements.count
        let cutoff = date.addingTimeInterval(-Self.retentionSeconds)
        measurements.removeAll { $0.date <= cutoff }
        return measurements.count != previousCount
    }

    mutating func resetSequence() {
        lastSequence = nil
    }
}

struct NoiseDeviceViewState: Identifiable, Equatable {
    let id: UUID
    let name: String
    let connectionText: String
    let syncText: String
    let alarmText: String?
    let lastSyncDate: Date?
    let lastError: String?
    let isConnected: Bool
    let measurements: [NoiseMeasurement]
    let latestStatus: DeviceStatus?
    let settingsAreApplied: Bool
}

@MainActor
final class NoiseSyncManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "3F751B85-D1AC-4699-AEEC-8B5B720B706B")
    static let configUUID = CBUUID(string: "0235A089-40E1-4985-A78B-046EA4D983A9")
    static let statusUUID = CBUUID(string: "214F1B5A-DD35-4626-8247-FA07DA61EE64")
    static let nameUUID = CBUUID(string: "AC1D60EF-369C-4640-8055-506A1514BD49")

    @Published private(set) var devices: [NoiseDeviceViewState] = []
    @Published private(set) var globalSettings = NoiseSettings()
    @Published private(set) var setupText = "Starting accessory setup"
    @Published private(set) var lastError: String?

    private enum Keys {
        static let restorationIdentifier = "ESPNoise.centralRestorationIdentifier"
    }

    private final class Runtime {
        let identifier: UUID
        var peripheral: CBPeripheral?
        var configCharacteristic: CBCharacteristic?
        var statusCharacteristic: CBCharacteristic?
        var nameCharacteristic: CBCharacteristic?
        var connectionText = "Waiting for Bluetooth"
        var isConnected = false
        var connectPending = false
        var reconnectAttempts = 0
        var reconnectWorkItem: DispatchWorkItem?
        var acknowledgementWorkItems: [DispatchWorkItem] = []
        var nameAcknowledgementWorkItems: [DispatchWorkItem] = []
        var statusExpiryWorkItem: DispatchWorkItem?
        var measurementExpiryWorkItem: DispatchWorkItem?
        var sentRevision: UInt32?
        var sentFingerprint: UInt32?
        var nameWritePending = false
        var nameQueryWritePending = false
        var hasReceivedName = false
        var status: DeviceStatus?
        var statusDate: Date?
        var measurementHistory = NoiseMeasurementHistory()
        var lastError: String?
        var nameError: String?

        init(identifier: UUID) { self.identifier = identifier }
    }

    private var settingsStore = SettingsStore()
    private let defaults = UserDefaults.standard
    private let accessorySession = ASAccessorySession()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.espnoise.companion",
        category: "Bluetooth"
    )
    private var onboarding = OnboardingLifecycle()
    private var accessorySessionActivated = false
    private var centralManager: CBCentralManager?
    private var runtimes: [UUID: Runtime] = [:]

#if DEBUG
    var hasCentralManagerForTesting: Bool { centralManager != nil }
#endif

    override init() {
        super.init()
        globalSettings = settingsStore.record.globalSettings
        accessorySession.activate(on: .main) { [weak self] event in
            self?.handleAccessoryEvent(event)
        }
    }

    func addDevice() {
        guard accessorySessionActivated else {
            lastError = "Accessory setup is not ready. Try again."
            return
        }
        guard !onboarding.pickerIsActive else { return }
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = Self.serviceUUID
        descriptor.bluetoothNameSubstring = "ESPNoise-"
        descriptor.supportedOptions = [.bluetoothPairingLE]
        guard let image = UIImage(systemName: "waveform.badge.mic") else {
            lastError = "The setup image is not available."
            return
        }
        let item = ASPickerDisplayItem(
            name: "ESPNoise",
            productImage: image,
            descriptor: descriptor
        )
        onboarding.pickerWillPresent()
        setupText = "Finding devices"
        accessorySession.showPicker(for: [item]) { [weak self] error in
            Task { @MainActor in
                guard let self, let error else { return }
                self.lastError = self.safeError(error, prefix: "Setup failed")
                if let action = self.onboarding.pickerFailed() {
                    self.handle(action)
                }
                self.updateSetupText()
            }
        }
    }

    func deviceRecord(id: UUID) -> NoiseDeviceRecord? {
        settingsStore.device(id: id)
    }

    func effectiveSettings(id: UUID) -> NoiseSettings? {
        settingsStore.effectiveSettings(for: id)
    }

    func saveGlobalSettings(_ settings: NoiseSettings) throws {
        try settingsStore.updateGlobal(settings)
        globalSettings = settingsStore.record.globalSettings
        publish()
        sendPendingToConnectedDevices()
    }

    func saveDevice(
        id: UUID,
        name: String,
        overrides: DeviceOverrides
    ) throws {
        try settingsStore.updateDevice(id: id, name: name, overrides: overrides)
        publish()
        if let runtime = runtimes[id] { sendDesired(to: runtime) }
    }

    func resetOverrides(id: UUID) throws {
        try settingsStore.resetOverrides(id: id)
        publish()
        if let runtime = runtimes[id] { sendDesired(to: runtime) }
    }

    func syncNow(id: UUID) {
        guard let runtime = runtimes[id] else { return }
        runtime.lastError = nil
        runtime.nameError = nil
        runtime.reconnectAttempts = 0
        if runtime.isConnected {
            sendDesired(to: runtime)
        } else {
            runtime.connectionText = "Connecting"
            connectAuthorizedDevices()
        }
        publish()
    }

    func removeDevice(id: UUID) {
        guard let accessory = authorizedAccessories.first(where: {
            $0.bluetoothIdentifier == id
        }) else { return }
        if let runtime = runtimes[id] { stop(runtime) }
        accessorySession.removeAccessory(accessory) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.runtimes[id]?.lastError = self.safeError(
                        error,
                        prefix: "Could not remove the device"
                    )
                    self.publish()
                    return
                }
                self.runtimes.removeValue(forKey: id)
                self.settingsStore.removeDevice(id: id)
                let remaining = self.onboarding.authorizedDevices.filter {
                    $0.bluetoothIdentifier != id
                }
                if let action = self.onboarding.replaceAuthorizedDevices(with: remaining) {
                    self.handle(action)
                }
                self.publish()
            }
        }
    }

    private var authorizedAccessories: [ASAccessory] {
        accessorySession.accessories.filter {
            $0.state == .authorized && $0.bluetoothIdentifier != nil
        }
    }

    private var currentAuthorizedDevices: [AuthorizedNoiseDevice] {
        authorizedAccessories.compactMap { accessory in
            guard let identifier = accessory.bluetoothIdentifier else { return nil }
            return AuthorizedNoiseDevice(
                displayName: accessory.displayName,
                bluetoothIdentifier: identifier
            )
        }
    }

    private func handleAccessoryEvent(_ event: ASAccessoryEvent) {
        if let error = event.error {
            logger.error("Accessory event failed: \(error.localizedDescription, privacy: .private)")
        }
        switch event.eventType {
        case .activated:
            accessorySessionActivated = true
            let authorized = currentAuthorizedDevices
            reconcile(authorized)
            if let action = onboarding.sessionActivated(with: authorized) { handle(action) }
        case .accessoryAdded:
            if let accessory = event.accessory,
               let identifier = accessory.bluetoothIdentifier {
                let device = AuthorizedNoiseDevice(
                    displayName: accessory.displayName,
                    bluetoothIdentifier: identifier
                )
                onboarding.accessoryAdded(device)
                reconcile(onboarding.authorizedDevices)
            }
        case .accessoryChanged:
            reconcileFromSession()
        case .accessoryRemoved:
            reconcileFromSession()
        case .pickerDidPresent:
            onboarding.pickerDidPresent()
        case .pickerDidDismiss:
            reconcileFromSession()
            if let action = onboarding.pickerDidDismiss() { handle(action) }
            else { connectAuthorizedDevices() }
        case .pickerSetupFailed:
            lastError = event.error.map { safeError($0, prefix: "Pairing failed") }
                ?? "Pairing failed."
            if let action = onboarding.pickerFailed() { handle(action) }
        case .invalidated:
            accessorySessionActivated = false
            reconcile([])
            if let action = onboarding.sessionInvalidated() { handle(action) }
            setupText = "Accessory setup is not available"
        default:
            break
        }
        updateSetupText()
    }

    private func reconcileFromSession() {
        let devices = currentAuthorizedDevices
        reconcile(devices)
        if let action = onboarding.replaceAuthorizedDevices(with: devices) {
            handle(action)
        }
    }

    private func reconcile(_ authorized: [AuthorizedNoiseDevice]) {
        let identifiers = Set(authorized.map(\.bluetoothIdentifier))
        for id in runtimes.keys where !identifiers.contains(id) {
            if let runtime = runtimes[id] { stop(runtime) }
            runtimes.removeValue(forKey: id)
        }
        for device in authorized {
            settingsStore.reconcileDevice(
                id: device.bluetoothIdentifier,
                suggestedName: device.displayName
            )
            if runtimes[device.bluetoothIdentifier] == nil {
                runtimes[device.bluetoothIdentifier] = Runtime(
                    identifier: device.bluetoothIdentifier
                )
            }
        }
        publish()
    }

    private func handle(_ action: OnboardingLifecycleAction) {
        switch action {
        case .initializeBluetoothAndConnect: initializeBluetooth()
        case .tearDownBluetooth: tearDownBluetooth()
        }
    }

    private func initializeBluetooth() {
        guard centralManager == nil, accessorySessionActivated,
              !onboarding.authorizedDevices.isEmpty else {
            connectAuthorizedDevices()
            return
        }
        let identifier: String
        if let saved = defaults.string(forKey: Keys.restorationIdentifier) {
            identifier = saved
        } else {
            identifier = "com.espnoise.companion.central.\(UUID().uuidString)"
            defaults.set(identifier, forKey: Keys.restorationIdentifier)
        }
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: identifier]
        )
    }

    private func tearDownBluetooth() {
        centralManager?.stopScan()
        for runtime in runtimes.values { stop(runtime) }
        centralManager?.delegate = nil
        centralManager = nil
    }

    private func connectAuthorizedDevices() {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        let unresolved = runtimes.values.filter { $0.peripheral == nil }.map(\.identifier)
        for peripheral in centralManager.retrievePeripherals(withIdentifiers: unresolved) {
            adopt(peripheral)
        }
        for runtime in runtimes.values {
            guard let peripheral = runtime.peripheral else {
                runtime.connectionText = "Authorized; waiting for the device"
                continue
            }
            switch peripheral.state {
            case .connected:
                runtime.isConnected = true
                peripheral.discoverServices([Self.serviceUUID])
            case .disconnected:
                requestConnection(runtime)
            case .connecting:
                runtime.connectPending = true
                runtime.connectionText = "Connecting"
            case .disconnecting:
                runtime.connectionText = "Disconnecting"
            @unknown default:
                runtime.connectionText = "Waiting for Bluetooth"
            }
        }
        updateScan()
        publish()
    }

    private func adopt(_ peripheral: CBPeripheral) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        if runtime.peripheral !== peripheral {
            runtime.configCharacteristic = nil
            runtime.statusCharacteristic = nil
            runtime.nameCharacteristic = nil
        }
        runtime.peripheral = peripheral
        peripheral.delegate = self
    }

    private func requestConnection(_ runtime: Runtime) {
        guard let centralManager, let peripheral = runtime.peripheral,
              !runtime.connectPending, peripheral.state == .disconnected else { return }
        runtime.connectPending = true
        runtime.connectionText = "Connecting"
        centralManager.connect(
            peripheral,
            options: [CBConnectPeripheralOptionEnableAutoReconnect: true]
        )
    }

    private func updateScan() {
        guard let centralManager, centralManager.state == .poweredOn else { return }
        let unresolved = Set(runtimes.values.filter { $0.peripheral == nil }.map(\.identifier))
        guard !unresolved.isEmpty else {
            centralManager.stopScan()
            return
        }
        if !centralManager.isScanning {
            centralManager.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    private func scheduleReconnect(_ runtime: Runtime) {
        runtime.reconnectWorkItem?.cancel()
        let delays: [TimeInterval] = [3, 15, 60]
        let attempt = min(runtime.reconnectAttempts, delays.count - 1)
        let delay = delays[attempt]
        runtime.reconnectAttempts = min(runtime.reconnectAttempts + 1,
                                        delays.count - 1)
        let id = runtime.identifier
        let work = DispatchWorkItem { [weak self] in
            guard let self, let current = self.runtimes[id] else { return }
            self.requestConnection(current)
            self.publish()
        }
        runtime.reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stop(_ runtime: Runtime) {
        runtime.acknowledgementWorkItems.forEach { $0.cancel() }
        runtime.acknowledgementWorkItems = []
        runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
        runtime.nameAcknowledgementWorkItems = []
        runtime.statusExpiryWorkItem?.cancel()
        runtime.reconnectWorkItem?.cancel()
        if let peripheral = runtime.peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        runtime.peripheral = nil
        runtime.configCharacteristic = nil
        runtime.statusCharacteristic = nil
        runtime.nameCharacteristic = nil
        runtime.sentRevision = nil
        runtime.sentFingerprint = nil
        runtime.nameWritePending = false
        runtime.nameQueryWritePending = false
        runtime.hasReceivedName = false
        runtime.isConnected = false
        runtime.connectPending = false
    }

    private func sendPendingToConnectedDevices() {
        for runtime in runtimes.values where runtime.isConnected {
            sendDesired(to: runtime)
        }
    }

    private func sendDesired(to runtime: Runtime) {
        sendDesiredSettings(to: runtime)
        sendDesiredName(to: runtime)
        publish()
    }

    private func sendDesiredSettings(to runtime: Runtime) {
        guard runtime.isConnected,
              let peripheral = runtime.peripheral,
              let characteristic = runtime.configCharacteristic,
              let device = settingsStore.device(id: runtime.identifier),
              let settings = settingsStore.effectiveSettings(for: runtime.identifier)
        else { return }
        if runtime.nameCharacteristic == nil,
           runtime.nameWritePending || runtime.nameQueryWritePending {
            return
        }
        do {
            let packet = try ConfigPacketCodec.encode(
                settings: settings,
                revision: device.desiredRevision
            )
            guard peripheral.maximumWriteValueLength(for: .withResponse)
                    >= packet.count else {
                runtime.lastError =
                    "The Bluetooth connection cannot transfer the settings packet."
                return
            }
            runtime.lastError = nil
            runtime.connectionText = "Sending settings"
            runtime.sentRevision = device.desiredRevision
            runtime.sentFingerprint = ConfigPacketCodec.fnv1a32(packet.prefix(28))
            peripheral.writeValue(packet, for: characteristic, type: .withResponse)
            scheduleAcknowledgementReads(runtime)
        } catch {
            runtime.lastError = error.localizedDescription
        }
    }

    private func sendDesiredName(to runtime: Runtime) {
        guard runtime.isConnected,
              settingsStore.nameNeedsSync(id: runtime.identifier),
              !runtime.nameWritePending,
              let peripheral = runtime.peripheral,
              let device = settingsStore.device(id: runtime.identifier)
        else { return }
        let characteristic = runtime.nameCharacteristic
            ?? runtime.configCharacteristic
        guard let characteristic else { return }
        if runtime.nameCharacteristic == nil,
           runtime.sentRevision != nil || runtime.nameQueryWritePending {
            return
        }
        do {
            let packet = try DeviceNamePacketCodec.encode(
                name: device.customName
            )
            guard peripheral.maximumWriteValueLength(for: .withResponse)
                    >= packet.count else {
                runtime.nameError =
                    "The Bluetooth connection cannot transfer the device name."
                return
            }
            runtime.nameError = nil
            runtime.nameWritePending = true
            runtime.connectionText = "Sending device name"
            peripheral.writeValue(
                packet,
                for: characteristic,
                type: .withResponse
            )
            scheduleNameAcknowledgementReads(runtime)
        } catch {
            runtime.nameError = error.localizedDescription
        }
    }

    private func scheduleAcknowledgementReads(_ runtime: Runtime) {
        runtime.acknowledgementWorkItems.forEach { $0.cancel() }
        runtime.acknowledgementWorkItems = []
        for delay in [2.0, 5.0, 10.0] {
            let id = runtime.identifier
            let work = DispatchWorkItem { [weak self] in
                guard let self, let current = self.runtimes[id],
                      self.settingsStore.settingsArePending(id: id),
                      let peripheral = current.peripheral,
                      let status = current.statusCharacteristic else { return }
                peripheral.readValue(for: status)
                if delay == 10 {
                    current.lastError = "The device did not confirm the settings. The settings stay pending."
                    self.publish()
                }
            }
            runtime.acknowledgementWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func scheduleNameAcknowledgementReads(_ runtime: Runtime) {
        runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
        runtime.nameAcknowledgementWorkItems = []
        for delay in [2.0, 5.0, 10.0] {
            let id = runtime.identifier
            let work = DispatchWorkItem { [weak self] in
                guard let self, let current = self.runtimes[id],
                      self.settingsStore.nameNeedsSync(id: id)
                        || !current.hasReceivedName,
                      let peripheral = current.peripheral else { return }
                if let name = current.nameCharacteristic {
                    peripheral.readValue(for: name)
                } else if let configuration = current.configCharacteristic {
                    guard !current.nameQueryWritePending else { return }
                    current.nameQueryWritePending = true
                    peripheral.writeValue(
                        DeviceNamePacketCodec.queryPacket,
                        for: configuration,
                        type: .withResponse
                    )
                }
                if delay == 10 {
                    current.nameWritePending = false
                    current.nameQueryWritePending = false
                    current.nameError = self.settingsStore.nameNeedsSync(id: id)
                        ? "The device did not confirm its name. The name stays pending."
                        : "The device did not return its saved name."
                    self.publish()
                }
            }
            runtime.nameAcknowledgementWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func requestDeviceName(from runtime: Runtime) {
        guard runtime.isConnected,
              !runtime.hasReceivedName,
              runtime.nameAcknowledgementWorkItems.isEmpty,
              let peripheral = runtime.peripheral else { return }
        if runtime.nameCharacteristic == nil,
           runtime.sentRevision != nil {
            return
        }
        if let name = runtime.nameCharacteristic {
            peripheral.readValue(for: name)
        } else if let configuration = runtime.configCharacteristic {
            runtime.nameQueryWritePending = true
            peripheral.writeValue(
                DeviceNamePacketCodec.queryPacket,
                for: configuration,
                type: .withResponse
            )
        } else {
            return
        }
        scheduleNameAcknowledgementReads(runtime)
    }

    private func handleStatus(_ data: Data, for runtime: Runtime) {
        do {
            let status = try StatusPacketCodec.decode(data)
            appendMeasurement(from: status, to: runtime)
            runtime.status = status
            runtime.statusDate = Date()
            scheduleStatusExpiry(runtime)
            if status.errorCode != 0 {
                runtime.acknowledgementWorkItems.forEach { $0.cancel() }
                runtime.acknowledgementWorkItems = []
                runtime.lastError =
                    "The device could not save the settings (error \(status.errorCode))."
                publish()
                return
            }
            guard let desired = settingsStore.device(id: runtime.identifier),
                  let settings = settingsStore.effectiveSettings(for: runtime.identifier)
            else { return }
            let expectedFingerprint = try ConfigPacketCodec.fingerprint(settings: settings)
            if status.appliedRevision == desired.desiredRevision,
               status.fingerprint == expectedFingerprint {
                runtime.acknowledgementWorkItems.forEach { $0.cancel() }
                runtime.acknowledgementWorkItems = []
                runtime.lastError = nil
                if runtime.sentRevision == status.appliedRevision,
                   runtime.sentFingerprint == status.fingerprint {
                    settingsStore.markSynced(
                        id: runtime.identifier,
                        revision: status.appliedRevision,
                        fingerprint: status.fingerprint,
                        at: Date()
                    )
                    runtime.sentRevision = nil
                    runtime.sentFingerprint = nil
                }
                runtime.connectionText = "Connected"
                if settingsStore.nameNeedsSync(id: runtime.identifier) {
                    sendDesiredName(to: runtime)
                } else {
                    requestDeviceName(from: runtime)
                }
            } else if status.appliedRevision == desired.desiredRevision {
                runtime.lastError = "The device confirmed different settings. The phone settings stay pending."
            }
        } catch {
            runtime.lastError = "The device sent an invalid status packet."
        }
        publish()
    }

    private func handleName(_ data: Data, for runtime: Runtime) {
        do {
            let appliedName = try DeviceNamePacketCodec.decode(data)
            runtime.hasReceivedName = true
            runtime.nameQueryWritePending = false
            if settingsStore.nameNeedsSync(id: runtime.identifier) {
                guard let desired = settingsStore.device(
                    id: runtime.identifier
                )?.customName else { return }
                if appliedName == desired {
                    runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
                    runtime.nameAcknowledgementWorkItems = []
                    runtime.nameWritePending = false
                    runtime.nameError = nil
                    runtime.connectionText = "Connected"
                    settingsStore.markNameSynced(
                        id: runtime.identifier,
                        name: appliedName,
                        at: Date()
                    )
                    sendDesiredSettings(to: runtime)
                } else if !runtime.nameWritePending {
                    sendDesiredName(to: runtime)
                }
            } else {
                runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
                runtime.nameAcknowledgementWorkItems = []
                runtime.nameError = nil
                settingsStore.adoptNameFromDevice(
                    id: runtime.identifier,
                    name: appliedName,
                    at: Date()
                )
                if settingsStore.nameNeedsSync(id: runtime.identifier) {
                    sendDesiredName(to: runtime)
                }
                if runtime.nameCharacteristic == nil {
                    sendDesiredSettings(to: runtime)
                }
            }
        } catch {
            runtime.nameError = "The device sent an invalid name packet."
        }
        publish()
    }

    private func appendMeasurement(from status: DeviceStatus, to runtime: Runtime) {
        guard let sequence = status.measurementSequence,
              let maximum = status.observationMaximumTenths else { return }
        if runtime.measurementHistory.append(
            sequence: sequence,
            maximumTenths: maximum,
            at: Date()
        ) {
            scheduleMeasurementExpiry(runtime)
        }
    }

    private func scheduleMeasurementExpiry(_ runtime: Runtime) {
        runtime.measurementExpiryWorkItem?.cancel()
        guard let oldest = runtime.measurementHistory.measurements.first else {
            runtime.measurementExpiryWorkItem = nil
            return
        }
        let expiryDate = oldest.date.addingTimeInterval(
            NoiseMeasurementHistory.retentionSeconds
        )
        let delay = max(0.05, expiryDate.timeIntervalSinceNow)
        let id = runtime.identifier
        let work = DispatchWorkItem { [weak self] in
            guard let self, let current = self.runtimes[id] else { return }
            current.measurementHistory.prune(at: Date())
            self.scheduleMeasurementExpiry(current)
            self.publish()
        }
        runtime.measurementExpiryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleStatusExpiry(_ runtime: Runtime) {
        runtime.statusExpiryWorkItem?.cancel()
        let id = runtime.identifier
        let work = DispatchWorkItem { [weak self] in
            guard let self, let current = self.runtimes[id] else { return }
            current.status = nil
            current.statusDate = nil
            self.publish()
        }
        runtime.statusExpiryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func publish() {
        globalSettings = settingsStore.record.globalSettings
        let now = Date()
        devices = runtimes.values.compactMap { runtime in
            guard let device = settingsStore.device(id: runtime.identifier) else { return nil }
            if runtime.measurementHistory.prune(at: now) {
                scheduleMeasurementExpiry(runtime)
            }
            let freshStatus: DeviceStatus?
            if let status = runtime.status, let date = runtime.statusDate,
               now.timeIntervalSince(date) < 15 {
                freshStatus = status
            } else {
                freshStatus = nil
            }
            let alarmText: String?
            if let status = freshStatus {
                var parts = [status.state.label]
                if status.alarmIsActive { parts.append("alarm active") }
                if status.isMuted { parts.append("muted") }
                alarmText = parts.joined(separator: ", ")
            } else {
                alarmText = nil
            }
            let pending = settingsStore.isPending(id: runtime.identifier)
            let settingsPending = settingsStore.settingsArePending(
                id: runtime.identifier
            )
            let displayedError = runtime.lastError ?? runtime.nameError
            let syncText = displayedError != nil
                ? "Error"
                : (pending ? "Pending" : "Synchronized")
            return NoiseDeviceViewState(
                id: runtime.identifier,
                name: device.customName,
                connectionText: runtime.connectionText,
                syncText: syncText,
                alarmText: alarmText,
                lastSyncDate: device.lastSuccessfulSync,
                lastError: displayedError,
                isConnected: runtime.isConnected,
                measurements: runtime.measurementHistory.measurements,
                latestStatus: freshStatus,
                settingsAreApplied: !settingsPending
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        updateSetupText()
    }

    private func updateSetupText() {
        if onboarding.pickerIsActive { setupText = "Finding devices" }
        else if devices.isEmpty {
            setupText = accessorySessionActivated ? "Ready to add a device" : "Starting accessory setup"
        } else {
            setupText = devices.count == 1 ? "Managing 1 device" : "Managing \(devices.count) devices"
        }
    }

    private func safeError(_ error: Error, prefix: String) -> String {
        let nsError = error as NSError
        if nsError.domain == ASErrorDomain && nsError.code == 150 {
            return "\(prefix). The phone found the device but could not connect. Keep it near the phone. Restart the device, then select Add Device again."
        }
        return "\(prefix) (\(nsError.domain) code \(nsError.code))."
    }

    private func radioState(_ state: CBManagerState) -> BluetoothRadioState {
        switch state {
        case .poweredOn: .poweredOn
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        case .resetting: .resetting
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}

extension NoiseSyncManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard centralManager === central else { return }
        setupText = onboarding.radioStatusText(for: radioState(central.state))
        if central.state == .poweredOn {
            connectAuthorizedDevices()
        } else {
            central.stopScan()
            for runtime in runtimes.values {
                runtime.isConnected = false
                runtime.connectPending = false
                runtime.connectionText = onboarding.radioStatusText(for: radioState(central.state))
            }
            publish()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        guard centralManager === central,
              let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey]
                as? [CBPeripheral] else { return }
        for peripheral in peripherals where runtimes[peripheral.identifier] != nil {
            adopt(peripheral)
            if peripheral.state == .connected {
                runtimes[peripheral.identifier]?.isConnected = true
                peripheral.discoverServices([Self.serviceUUID])
            }
        }
        publish()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard centralManager === central, runtimes[peripheral.identifier] != nil else { return }
        adopt(peripheral)
        if let runtime = runtimes[peripheral.identifier] { requestConnection(runtime) }
        updateScan()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard centralManager === central, let runtime = runtimes[peripheral.identifier] else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        runtime.reconnectWorkItem?.cancel()
        runtime.reconnectAttempts = 0
        runtime.connectPending = false
        runtime.isConnected = true
        runtime.connectionText = "Connected; finding services"
        runtime.measurementHistory.resetSequence()
        adopt(peripheral)
        peripheral.discoverServices([Self.serviceUUID])
        publish()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        runtime.connectPending = false
        runtime.isConnected = false
        runtime.lastError = error.map { safeError($0, prefix: "Connection failed") }
        scheduleReconnect(runtime)
        publish()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        runtime.isConnected = false
        runtime.connectPending = isReconnecting
        runtime.configCharacteristic = nil
        runtime.statusCharacteristic = nil
        runtime.nameCharacteristic = nil
        runtime.nameQueryWritePending = false
        runtime.hasReceivedName = false
        runtime.sentRevision = nil
        runtime.sentFingerprint = nil
        runtime.nameWritePending = false
        runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
        runtime.nameAcknowledgementWorkItems = []
        runtime.measurementHistory.resetSequence()
        runtime.connectionText = isReconnecting ? "Out of range; reconnecting" : "Out of range"
        if !isReconnecting { scheduleReconnect(runtime) }
        publish()
    }
}

extension NoiseSyncManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        if let error {
            runtime.lastError = safeError(error, prefix: "Service discovery failed")
            publish()
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            runtime.lastError = "The ESPNoise service is not available."
            publish()
            return
        }
        peripheral.discoverCharacteristics(
            [Self.configUUID, Self.statusUUID, Self.nameUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        if let error {
            runtime.lastError = safeError(error, prefix: "Characteristic discovery failed")
            publish()
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.configUUID { runtime.configCharacteristic = characteristic }
            if characteristic.uuid == Self.statusUUID { runtime.statusCharacteristic = characteristic }
            if characteristic.uuid == Self.nameUUID { runtime.nameCharacteristic = characteristic }
        }
        guard runtime.configCharacteristic != nil,
              let status = runtime.statusCharacteristic else {
            runtime.lastError = "The ESPNoise service is incomplete. Update the firmware."
            publish()
            return
        }
        if let name = runtime.nameCharacteristic {
            peripheral.setNotifyValue(true, for: name)
            peripheral.readValue(for: name)
        }
        if let configuration = runtime.configCharacteristic {
            peripheral.setNotifyValue(true, for: configuration)
        }
        peripheral.setNotifyValue(true, for: status)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        if let error {
            if characteristic.uuid == Self.nameUUID {
                let label = "Name notifications failed"
                runtime.nameError = safeError(error, prefix: label)
            } else {
                let label = characteristic.uuid == Self.configUUID
                    ? "Settings notifications failed"
                    : "Status notifications failed"
                runtime.lastError = safeError(error, prefix: label)
            }
        } else if characteristic.isNotifying {
            peripheral.readValue(for: characteristic)
            if characteristic.uuid == Self.statusUUID {
                sendDesired(to: runtime)
            } else if characteristic.uuid == Self.configUUID {
                requestDeviceName(from: runtime)
            }
        }
        publish()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        if let error {
            if characteristic.uuid == Self.nameUUID {
                let label = "Device name read failed"
                runtime.nameError = safeError(error, prefix: label)
            } else {
                let label = characteristic.uuid == Self.configUUID
                    ? "Settings read failed"
                    : "Status read failed"
                runtime.lastError = safeError(error, prefix: label)
            }
        } else if let data = characteristic.value {
            if characteristic.uuid == Self.statusUUID {
                handleStatus(data, for: runtime)
            } else if characteristic.uuid == Self.nameUUID {
                handleName(data, for: runtime)
            } else if characteristic.uuid == Self.configUUID,
                      data.count == DeviceNamePacketCodec.packetLength {
                handleName(data, for: runtime)
            }
        }
        publish()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let runtime = runtimes[peripheral.identifier] else { return }
        if let error {
            if characteristic.uuid == Self.configUUID {
                if runtime.nameCharacteristic == nil,
                   runtime.nameWritePending {
                    runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
                    runtime.nameAcknowledgementWorkItems = []
                    runtime.nameWritePending = false
                    runtime.nameError = safeError(
                        error,
                        prefix: "Device name transfer failed"
                    )
                } else if runtime.nameQueryWritePending {
                    runtime.nameQueryWritePending = false
                    runtime.nameError = safeError(
                        error,
                        prefix: "Device name read request failed"
                    )
                } else if runtime.sentRevision != nil {
                    runtime.acknowledgementWorkItems.forEach { $0.cancel() }
                    runtime.acknowledgementWorkItems = []
                    runtime.sentRevision = nil
                    runtime.sentFingerprint = nil
                    runtime.lastError = safeError(
                        error,
                        prefix: "Settings transfer failed"
                    )
                }
            } else if characteristic.uuid == Self.nameUUID {
                runtime.nameAcknowledgementWorkItems.forEach { $0.cancel() }
                runtime.nameAcknowledgementWorkItems = []
                runtime.nameWritePending = false
                runtime.nameError = safeError(
                    error,
                    prefix: "Device name transfer failed"
                )
            }
            publish()
        } else if characteristic.uuid == Self.configUUID,
                  runtime.nameQueryWritePending {
            runtime.nameQueryWritePending = false
        }
    }
}
