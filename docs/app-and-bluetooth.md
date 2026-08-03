# iPhone app and Bluetooth settings

The ESPNoise iPhone app manages one or more ESPNoise devices. The app uses
Bluetooth Low Energy. It does not need Wi-Fi, an Internet service, an account,
location data, or analytics.

The firmware does not send or save raw microphone audio. It sends only the
current alarm state and settings status.

## Settings model

The app keeps one global profile. Each device uses this profile by default.
A device can override these values:

- LED brightness
- Buzzer volume
- Green, orange, and red dBFS thresholds
- Mute-button duration

Observation time K, observation period N, decision-window time, and sample
ratio X are global values. A device cannot override them.

Each device page shows the inherited or overridden state of each applicable
value. A reset action removes the override. It does not copy the current
global value into a new override.

## Synchronization rule

The phone is the settings source. A complete effective profile is sent after
each device connection. Thus, these events start synchronization:

- The device starts while the phone is in range.
- The device returns to range.
- The app starts and reconnects.
- The user selects **Sync Now**.
- A saved phone setting changes while the device is connected.

If a setting changes while a device is out of range, the app marks that
device as pending. The device continues to use its last valid saved profile.
The app sends the pending profile after the next connection.

The app does not report success after the Bluetooth write alone. The device
must validate, save, and apply the profile. It then returns the phone revision
and a settings fingerprint. The app records the synchronization time only
when both values match its desired profile.

Do not let two phones automatically manage the same device. The phone that
reconnects last can replace the settings from the other phone.

## Device page and fleet status

The home page shows these important values for each device:

- Device name
- In range or out of range
- Current alarm state when the value is fresh
- Synced, pending, or error state
- Time of the last successful settings synchronization

Each device has a separate page for its overrides, effective values, manual
synchronization, and removal.

The app has no configured device-count limit. The practical count of active
Bluetooth connections depends on iOS, the radio environment, and the distance
to each device.

## Setting limits

The app checks a profile before it sends it. The device checks it again before
it saves or applies it. The device is the final safety control.

- Brightness and buzzer volume are from 0% through 100%.
- The battery-build brightness output cannot be more than 25% until a power
  test approves a higher value.
- Green must be lower than orange, and orange must be lower than red.
- K must be greater than zero and cannot be greater than N.
- The decision window must be a multiple of N.
- X cannot permit one observation to start an alarm.
- A settings change clears old detector history. Old observations do not use
  the new rule.
- A new mute duration applies to the next button press. It does not change a
  mute period that is already active.

The buzzer volume is a software request. The hard switch in the buzzer power
wire stays the final control and can stop all buzzer output.

## Bluetooth service

The device advertises a name in the form `ESPNoise-XXXX`. `XXXX` is the low
four hexadecimal digits of the ESP32 hardware identifier.

| Item | UUID |
| --- | --- |
| Settings service | `3F751B85-D1AC-4699-AEEC-8B5B720B706B` |
| Configuration | `0235A089-40E1-4985-A78B-046EA4D983A9` |
| Status | `214F1B5A-DD35-4626-8247-FA07DA61EE64` |

The configuration value is a 32-byte, little-endian packet.

| Byte | Value |
| ---: | --- |
| 0 | Protocol version, `1` |
| 1 | Flags, `0` |
| 2 | LED brightness percent |
| 3 | Buzzer volume percent |
| 4-5 | Green threshold in signed tenths of one dBFS |
| 6-7 | Orange threshold in signed tenths of one dBFS |
| 8-9 | Red threshold in signed tenths of one dBFS |
| 10-13 | K in milliseconds |
| 14-17 | N in milliseconds |
| 18-21 | Decision window in milliseconds |
| 22 | X in percent |
| 23 | Reserved, `0` |
| 24-27 | Mute duration in seconds |
| 28-31 | Phone revision |

The settings fingerprint is FNV-1a 32 over bytes 0 through 27. The revision is
not part of the fingerprint.

The status value is a 16-byte, little-endian packet. It contains the protocol
version, alarm state, mute/sample/alarm flags, error code, applied revision,
settings fingerprint, and device uptime.

Error code `1` means that the device could not save the settings. The app keeps
the change pending and does not report a successful synchronization.

The app subscribes to notifications before it writes. It uses a write with a
Bluetooth response. The firmware applies a valid packet in its main task, at
a safe detector boundary. The firmware then notifies the app and supplies the
same packet through a configuration read.

## Pairing and background limits

The app uses AccessorySetupKit on iOS 18 or later. A new device accepts a
bonded connection during its first two minutes after startup. It then changes
to slower connectable advertising for lower radio use and known-phone
reconnection.

iOS Bluetooth work is event driven. iOS does not guarantee that the app will
run at a fixed time. The app uses Bluetooth restoration and automatic
reconnection, but synchronization can stop in these cases:

- The user force-quits the app.
- Bluetooth is off or permission is removed.
- The phone is out of range.
- The phone restarted and was not unlocked.
- The app was removed or its development signature expired.

Open the app once after these conditions. The device continues to use its last
saved profile when the app is not available.

## Physical acceptance tests

Bluetooth and AccessorySetupKit need a physical iPhone. Test these cases before
release:

1. Add one device during its startup pairing window.
2. Change a global value and confirm the device applies it.
3. Add an override and confirm that a later global change does not replace it.
4. Change a setting while the device is off. Start the device and confirm an
   immediate synchronization.
5. Move the device out of range and back into range.
6. Add at least three devices and change one device at a time.
7. Remove one device and confirm that the other devices stay connected.
8. Test locked-phone restoration separately from an intentional force-quit.
9. Confirm with a radio scanner that the name and service UUID are present.
10. Confirm that the battery build never drives the LEDs above its safe limit.
