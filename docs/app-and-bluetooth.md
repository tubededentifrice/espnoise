# iPhone app and Bluetooth settings

The ESPNoise iPhone app manages one or more ESPNoise devices. The app uses
Bluetooth Low Energy. It does not need Wi-Fi, an Internet service, an account,
location data, or analytics.

The firmware does not send or save raw microphone audio. It sends only the
current observation maximum, rolling threshold counts, alarm state, and
settings status.

## Settings model

The app keeps one global profile. Each device uses this profile by default.
A device can override these values:

- LED brightness
- Buzzer volume
- Green, orange, and red positive relative-level thresholds
- Mute-button duration

Observation time K, observation period N, decision-window time, and sample
ratio X are global values. A device cannot override them.

Each device page shows the inherited or overridden state of each applicable
value. A reset action removes the override. It does not copy the current
global value into a new override.

The Global Settings page has a reset button. It puts the compiled default
values in the draft. The user must select **Save Global Settings** to apply
them. This action does not remove device overrides or device names.

A custom device name is saved on the phone and in ESP32 nonvolatile storage.
It uses a separate synchronization state from the measurement settings. A
new phone adopts the name that it reads from the device. A normal firmware
upload keeps the saved name. If a full flash erase removes the name, a phone
that previously confirmed the name restores it. The name can use no more
than 18 UTF-8 bytes. Names in the form `Device XXXX`, where `XXXX` is four
hexadecimal digits, are reserved for the hardware default name.

The firmware keeps thresholds as signed dBFS values. The app presents them as
a positive relative level from 0 through 120. It adds 120 to the dBFS value,
so louder sound has a larger displayed number. This value is not calibrated
dB SPL.

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
reconnects last can replace the settings from the other phone. A phone does
not write a device name only because it connects. It adopts a different valid
name from the device unless it has a pending user edit.

## Device page and fleet status

The home page shows these important values for each device:

- Device name
- In range or out of range
- Current alarm state when the value is fresh
- Synced, pending, or error state
- Time of the last successful settings synchronization

Each device has a separate page for its live measurement graph, rolling alarm
counts, overrides, effective values, manual synchronization, and removal. The
graph uses the same positive 0-through-120 scale as the threshold controls.
It keeps up to five minutes of observation maxima in app memory. It does not
save this history or raw audio.

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
- Mute stops the light and buzzer alarm outputs. It does not stop sound
  observations or Bluetooth history updates.
- A second mute-button press within 750 ms ends mute. A later single press
  restarts the complete mute period.

The buzzer volume is a software request. The hard switch in the buzzer power
wire stays the final control and can stop all buzzer output.

## Bluetooth service

The device advertises a name in the form `ESPNoise-<name>`. The default name
is `Device XXXX`, where `XXXX` is the low four hexadecimal digits of the ESP32
hardware identifier. The `ESPNoise-` prefix stays present after a name change,
so AccessorySetupKit discovery continues to work.

| Item | UUID |
| --- | --- |
| Settings service | `3F751B85-D1AC-4699-AEEC-8B5B720B706B` |
| Configuration | `0235A089-40E1-4985-A78B-046EA4D983A9` |
| Status | `214F1B5A-DD35-4626-8247-FA07DA61EE64` |
| Device name | `AC1D60EF-369C-4640-8055-506A1514BD49` |

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

The device-name value is a 20-byte packet. Reads and writes require an
encrypted connection. The app normally uses the separate device-name
characteristic. It can also write this packet to the configuration
characteristic. This fallback lets an iPhone with an old Bluetooth service
cache synchronize the name without a new pairing.

| Byte | Value |
| ---: | --- |
| 0 | Name protocol version, `1` |
| 1 | UTF-8 name length, from `1` through `18`; `0` requests a readback |
| 2-19 | Name bytes and zero padding |

The BLE callback validates and queues a nonempty name. A packet with a zero
length requests the current name. The main loop saves a new name before the
firmware changes the advertised name and sends an exact readback. A BLE write
response alone is not a successful name synchronization.

The current status value is a 20-byte, little-endian packet.

| Byte | Value |
| ---: | --- |
| 0 | Status protocol version, `2` |
| 1 | Alarm state |
| 2 | Mute, sampling, alarm-active, and measurement-valid flags |
| 3 | Error code |
| 4-7 | Applied phone revision |
| 8-11 | Settings fingerprint |
| 12-13 | Current observation maximum in signed tenths of one dBFS |
| 14-15 | Measurement sequence |
| 16 | Saved observation count |
| 17 | Saved observations at or above Green |
| 18 | Saved observations at or above Orange |
| 19 | Saved observations at or above Red |

The 20-byte value fits the default Bluetooth LE notification payload. Live
measurement changes are limited to four notifications each second. A control
state change can send an immediate notification. An unchanged status has a
ten-second heartbeat. The app can also read the old 16-byte status version,
but that version has no measurement graph data.

Error code `1` means that the device could not save the settings. The app keeps
the change pending and does not report a successful synchronization.

The app subscribes to notifications before it writes. It uses a write with a
Bluetooth response. The firmware applies a valid packet in its main task, at
a safe detector boundary. The firmware then notifies the app and supplies the
same packet through a configuration read.

## Pairing and background limits

The app uses AccessorySetupKit on iOS 18 or later. A device with no saved bond
keeps first pairing available. After the first bond succeeds, a different
phone can pair during the first two minutes after device startup. The device
then changes to slower connectable advertising for lower radio use and
known-phone reconnection.

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
10. Confirm that live maxima and threshold counts update during observations.
11. Confirm that the battery build never drives the LEDs above its safe limit.
