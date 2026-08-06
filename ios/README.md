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

Each device page has a synchronized custom name and optional device values.
The custom name is saved on the ESP32 and is available to another phone. A
normal firmware upload keeps it. The hardware-name form `Device XXXX` is
reserved. Sampling values K, N, decision window, and X
are global only. The phone sends its complete effective settings after each
reconnect. Offline settings stay pending.

Noise analytics collection is on by default. The Global Settings page can turn
it off for all devices. Each device can override the global value. A device
with collection off does not collect or save new summaries. It erases its
saved summaries when the setting changes to off.

The Global Settings page saves each valid change on the phone immediately. It
then tries to send the newest complete settings to each connected device. The
Reset Global Values action saves the compiled defaults immediately. Device
overrides and names stay unchanged.

Green, orange, and red threshold sliders use the same quieter-to-louder scale.
The displayed scale is a positive relative level from 0 through 120. It is not
calibrated dB SPL. The app keeps these thresholds in color order while the
user moves a slider.

The top of each device page graphs live observation maxima against the three
thresholds. It also shows how many saved observations reached each threshold.
The Global Settings page shows one live chart for each device that is in range.
This short graph history stays in app memory only. The phone does not receive
raw microphone audio.

The Noise Analytics page reads 15-minute summaries from each device. A device
keeps at most 72 hours. The phone keeps at most 30 days for each device. The
page can show one device, a selected group, or all devices. It shows average
and peak relative levels, state time, time trends, device comparisons, and a
weekday and hour heatmap. The phone sends UTC time when it requests the
summaries. The page requests data when it opens and has a refresh control. The
app can also read the old analytics packet until the device has version 2
firmware. The summaries do not contain audio.

Hold the device mute button for two seconds to disable or enable the complete
Bluetooth controller. The device saves this state after a restart. The app
cannot synchronize while Bluetooth is off.

## Sync rules

Phone settings always win. Global settings, device overrides, and valid device
names save on the phone as they change. For each device, the app permits one
active settings write and one pending request for the newest complete settings.
Additional changes replace that pending request. A write response does not
complete a sync. The app completes a sync only when the device reports the
desired revision and the matching FNV-1a fingerprint. The app keeps stale,
delayed, duplicate, or incorrect reports separate for each device. iOS controls
connection and background timing, so the app does not promise a fixed update
time.

## Privacy

The app uses AccessorySetupKit and Core Bluetooth. It does not use Internet
access, location, accounts, or an external analytics service. Aggregated noise
history stays on the devices and the phone. It does not collect or save raw
microphone audio. Logs do not include device settings or device identifiers.

## Physical-device gates

Complete these checks before release:

- Confirm AccessorySetupKit pairing with production firmware.
- Confirm reconnect and state restoration after the app moves to the background.
- Confirm that an offline edit stays pending and syncs after reconnect.
- Confirm status notifications, readback, wrong fingerprints, stale revisions, and delayed reports.
- Confirm operation with multiple authorized devices at the same time.
- Confirm history recovery after a device stays out of range for one hour.
- Confirm analytics selection and charts with at least three devices.
- Confirm that the battery build never drives the LEDs above its 25% board
  limit. The USB build has a completed 100% power test.
- Confirm that a force-quit app does not claim background operation.
