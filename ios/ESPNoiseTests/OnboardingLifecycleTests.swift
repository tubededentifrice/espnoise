import XCTest
@testable import ESPNoise

final class OnboardingLifecycleTests: XCTestCase {
    private let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private var device: AuthorizedNoiseDevice {
        AuthorizedNoiseDevice(displayName: "Desk", bluetoothIdentifier: id)
    }

    @MainActor
    func testFreshManagerHasNoCentralManager() {
        let manager = NoiseSyncManager()
        XCTAssertFalse(manager.hasCentralManagerForTesting)
    }

    func testFreshInstallDoesNotCreateBluetoothCentral() {
        var lifecycle = OnboardingLifecycle()
        XCTAssertNil(lifecycle.sessionActivated(with: []))
        XCTAssertFalse(lifecycle.bluetoothInitializationRequested)
    }

    func testCentralStartsOnlyAfterPickerCloses() {
        var lifecycle = OnboardingLifecycle()
        _ = lifecycle.sessionActivated(with: [])
        lifecycle.pickerWillPresent()
        lifecycle.accessoryAdded(device)
        XCTAssertFalse(lifecycle.bluetoothInitializationRequested)
        XCTAssertEqual(lifecycle.pickerDidDismiss(), .initializeBluetoothAndConnect)
        XCTAssertNil(lifecycle.pickerDidDismiss())
    }

    func testLaunchWithAuthorizedDeviceStartsOneCentral() {
        var lifecycle = OnboardingLifecycle()
        XCTAssertEqual(
            lifecycle.sessionActivated(with: [device]),
            .initializeBluetoothAndConnect
        )
        XCTAssertNil(lifecycle.replaceAuthorizedDevices(with: [device]))
    }

    func testLastRemovalTearsDownBluetooth() {
        var lifecycle = OnboardingLifecycle()
        _ = lifecycle.sessionActivated(with: [device])
        XCTAssertEqual(lifecycle.replaceAuthorizedDevices(with: []), .tearDownBluetooth)
        XCTAssertFalse(lifecycle.bluetoothInitializationRequested)
    }
}

final class LatestSettingsWriteQueueTests: XCTestCase {
    func testManyRequestsKeepOnlyTheLatestPendingWrite() {
        var queue = LatestSettingsWriteQueue()

        XCTAssertTrue(queue.requestWrite())
        for _ in 0..<100 {
            XCTAssertFalse(queue.requestWrite())
        }
        XCTAssertTrue(queue.writeIsActive)
        XCTAssertTrue(queue.latestWriteIsPending)

        XCTAssertTrue(queue.completeWrite())
        XCTAssertFalse(queue.writeIsActive)
        XCTAssertFalse(queue.latestWriteIsPending)
        XCTAssertTrue(queue.requestWrite())
        XCTAssertFalse(queue.completeWrite())
    }

    func testResetDropsAnObsoletePendingWrite() {
        var queue = LatestSettingsWriteQueue()
        XCTAssertTrue(queue.requestWrite())
        XCTAssertFalse(queue.requestWrite())

        queue.reset()

        XCTAssertFalse(queue.writeIsActive)
        XCTAssertFalse(queue.latestWriteIsPending)
        XCTAssertTrue(queue.requestWrite())
    }
}
