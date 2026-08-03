# ESPNoise iOS companion

ESPNoise is an iOS 18 or later SwiftUI app. It sends settings to any number of authorized ESPNoise devices through Bluetooth LE.

## Build

Open `ESPNoise.xcodeproj` in Xcode. Select the shared `ESPNoise` scheme and an iPhone with iOS 18 or later. The project keeps local development team `4HX6DP68N3` for a user-authorized phone installation. Change the team only if your Apple account requires a different team.

For an unsigned check, run:

```sh
xcodebuild -project ESPNoise.xcodeproj -scheme ESPNoise \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Use the same command with `build-for-testing` to compile the XCTest target.

## Install and pair

1. Build and install the app on a physical iPhone.
2. Turn on the ESPNoise device and Bluetooth on the iPhone.
3. Open ESPNoise and select **Add Device**.
4. Select a device with a Bluetooth name that starts with `ESPNoise-`.
5. Keep the device near the phone until the app shows **Synchronized**.

If setup reports that it cannot add the accessory, keep the device powered,
restart it, and try **Add Device** again. A device with no completed bond keeps
first pairing available.

Each device page has a local custom name and optional device values. Sampling values K, N, decision window, and X are global only. The phone sends its complete effective settings after each reconnect. Offline settings stay pending.

Green, orange, and red threshold sliders use the same quieter-to-louder scale.
The app keeps these thresholds in color order while the user moves a slider.

## Sync rules

Phone settings always win. A write response does not complete a sync. The app completes a sync only when the device reports the desired revision and the matching FNV-1a fingerprint. The app keeps stale, delayed, duplicate, or incorrect reports separate for each device. iOS controls connection and background timing, so the app does not promise a fixed update time.

## Privacy

The app uses AccessorySetupKit and Core Bluetooth. It does not use Internet access, location, accounts, or analytics. It does not collect or save raw microphone audio. Logs do not include device settings or device identifiers.

## Physical-device gates

Complete these checks before release:

- Confirm AccessorySetupKit pairing with production firmware.
- Confirm reconnect and state restoration after the app moves to the background.
- Confirm that an offline edit stays pending and syncs after reconnect.
- Confirm status notifications, readback, wrong fingerprints, stale revisions, and delayed reports.
- Confirm operation with multiple authorized devices at the same time.
- Confirm that the battery build never drives the LEDs above its 25% board
  limit. The USB build has a completed 100% power test.
- Confirm that a force-quit app does not claim background operation.
