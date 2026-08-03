import Foundation

struct AuthorizedNoiseDevice: Equatable {
    let displayName: String
    let bluetoothIdentifier: UUID
}

enum OnboardingLifecycleAction: Equatable {
    case initializeBluetoothAndConnect
    case tearDownBluetooth
}

struct OnboardingLifecycle {
    private(set) var authorizedDevices: [AuthorizedNoiseDevice] = []
    private(set) var pickerIsActive = false
    private(set) var bluetoothInitializationRequested = false

    mutating func sessionActivated(
        with devices: [AuthorizedNoiseDevice]
    ) -> OnboardingLifecycleAction? {
        authorizedDevices = Self.normalized(devices)
        guard !authorizedDevices.isEmpty else {
            bluetoothInitializationRequested = false
            return nil
        }
        return requestBluetoothInitialization()
    }

    mutating func pickerWillPresent() { pickerIsActive = true }
    mutating func pickerDidPresent() { pickerIsActive = true }

    mutating func accessoryAdded(_ device: AuthorizedNoiseDevice) {
        authorizedDevices.removeAll {
            $0.bluetoothIdentifier == device.bluetoothIdentifier
        }
        authorizedDevices.append(device)
        authorizedDevices = Self.normalized(authorizedDevices)
    }

    mutating func replaceAuthorizedDevices(
        with devices: [AuthorizedNoiseDevice]
    ) -> OnboardingLifecycleAction? {
        authorizedDevices = Self.normalized(devices)
        guard authorizedDevices.isEmpty else {
            return requestBluetoothInitialization()
        }
        guard bluetoothInitializationRequested else { return nil }
        bluetoothInitializationRequested = false
        return .tearDownBluetooth
    }

    mutating func pickerDidDismiss() -> OnboardingLifecycleAction? {
        pickerIsActive = false
        guard !authorizedDevices.isEmpty else { return nil }
        return requestBluetoothInitialization()
    }

    mutating func pickerFailed() -> OnboardingLifecycleAction? {
        pickerIsActive = false
        guard authorizedDevices.isEmpty, bluetoothInitializationRequested else {
            return nil
        }
        bluetoothInitializationRequested = false
        return .tearDownBluetooth
    }

    mutating func sessionInvalidated() -> OnboardingLifecycleAction? {
        pickerIsActive = false
        authorizedDevices = []
        guard bluetoothInitializationRequested else { return nil }
        bluetoothInitializationRequested = false
        return .tearDownBluetooth
    }

    func radioStatusText(for state: BluetoothRadioState) -> String {
        guard !authorizedDevices.isEmpty, bluetoothInitializationRequested else {
            return pickerIsActive ? "Finding devices…" : "Ready to add a device"
        }
        return switch state {
        case .poweredOn: "Ready to connect"
        case .poweredOff: "Turn on Bluetooth"
        case .unauthorized: "Bluetooth access is not authorized"
        case .unsupported: "This iPhone does not support Bluetooth LE"
        case .resetting: "Bluetooth is resetting"
        case .unknown: "Checking Bluetooth"
        }
    }

    private mutating func requestBluetoothInitialization()
        -> OnboardingLifecycleAction? {
        guard !pickerIsActive, !bluetoothInitializationRequested else { return nil }
        bluetoothInitializationRequested = true
        return .initializeBluetoothAndConnect
    }

    private static func normalized(
        _ devices: [AuthorizedNoiseDevice]
    ) -> [AuthorizedNoiseDevice] {
        Dictionary(
            devices.map { ($0.bluetoothIdentifier, $0) },
            uniquingKeysWith: { _, newest in newest }
        ).values.sorted { $0.bluetoothIdentifier.uuidString < $1.bluetoothIdentifier.uuidString }
    }
}

enum BluetoothRadioState: Equatable {
    case poweredOn
    case poweredOff
    case unauthorized
    case unsupported
    case resetting
    case unknown
}
