# Firmware

## Requirements

- `uv` 0.12 or later, or the PlatformIO IDE extension
- A USB data cable
- The `esp32dev` board definition for the full-size USB-C board
- The `lolin32_lite` board definition for the WEMOS battery board

The repository accepts a dependency only after it is seven weeks old. The
`uv.lock` file pins PlatformIO Core and all Python packages with SHA-256
hashes. The PlatformIO configuration pins the platform, framework, build
tools, and libraries to exact versions. Git tags and version ranges are not
permitted.

Run the fail-closed policy check before an install or dependency update. The
check verifies the `uv.lock` hashes and dates against PyPI. It reads PlatformIO
and Git commit dates from their services. It also rejects a missing hash, a
version range, a Git tag, or a short Git commit.

```sh
python3 tools/check_dependency_age.py
```

Use `tools/pio.py` for each PlatformIO command. The wrapper runs the same
policy check before PlatformIO can install a package.

The same check runs in GitHub Actions. Protect `main` and require the
`Dependency age / check` result so that a change cannot bypass the check. An
urgent security fix that is less than seven weeks old needs an explicit policy
change and review. Do not silently remove the cooldown.

From the repository root, install the locked Python tools:

```sh
uv sync --locked
```

## Build

From the repository root, run:

```sh
uv run --locked python tools/pio.py run
```

This command builds the first USB-powered board. Its ten-pixel power test
passed, so this profile uses 100% LED brightness. The battery board stays an
optional environment and keeps the 25% limit. Build it only when you start the
battery stage:

```sh
uv run --locked python tools/pio.py run --environment esp32dev
uv run --locked python tools/pio.py run --environment lolin32_lite
```

At each USB production startup, all ten pixels show green, orange, and red in
quick succession. The buzzer plays one short rising note with each color. The
check takes less than half a second. The detector starts after it finishes.
The hard buzzer switch can disable the notes without disabling the light check.

Use the temporary LED-test environment to show red, green, blue, and
warm-white for one second each after startup:

```sh
uv run --locked python tools/pio.py run --environment esp32dev_led_test --target upload
```

For a one-pixel bench test, use the fast profile. It listens for 3 seconds in
each 5-second period, keeps a 15-second history, requires at least 50% of the
saved maxima, and uses full LED brightness. It also plays a short buzzer chime
after the LED test:

```sh
uv run --locked python tools/pio.py run --environment esp32dev_fast_test --target upload
```

Use the calibration profile with the assembled USB-powered product. Send `g`,
`o`, or `r` over the serial monitor. The strip shows the selected solid color
while the firmware measures one 10-second sample. The result is the median of
ten one-second maxima. The buzzer stays off. The calibration profile does not
save raw microphone audio.

```sh
uv run --locked python tools/pio.py run --environment esp32dev_calibration --target upload
uv run --locked python tools/pio.py device monitor --baud 115200
```

The tested passive piezo buzzer uses a 2N3904 low-side driver. GPIO23 connects
to its base through 5.1 kohm. The firmware drives it with 2.4 kHz PWM. The
hard switch stays in the buzzer 5 V wire.

The runtime buzzer-volume value sets the electrical tone amplitude. The
firmware maps this value to the PWM waveform for the passive piezo. Acoustic
loudness is not linear and depends on the buzzer and its enclosure, so adjust
the value after the case is assembled.

## Firmware modules

| Module | Files | Responsibility |
| --- | --- | --- |
| Board profile | `include/board_profile.h` | GPIO pins and optional switched power |
| User settings | `include/config.h` | K, N, X, threshold, colors, and timing |
| Audio input | `include/audio_input.h`, `src/audio_input.cpp` | INMP441 and dBFS frames |
| Detector | `include/noise_detector.h`, `src/noise_detector.cpp` | Observation maximum, rolling history, and X decision |
| Alarm output | `include/alarm_output.h`, `src/alarm_output.cpp` | SK6812, buzzer, and optional power switch |
| Mute control | `include/mute_button.h`, `src/mute_button.cpp`, `include/mute_state.h`, `src/mute_state.cpp` | Button filtering, mute timer, and double-press control |
| BLE service | `include/ble_service.h`, `src/ble_service.cpp` | Encrypted settings writes, readback, and status |
| Settings packet | `include/config_packet.h`, `src/config_packet.cpp` | 32-byte packet, limits, and fingerprint |
| Device name | `include/device_name.h`, `src/device_name.cpp` | 20-byte UTF-8 name packet and validation |
| Settings storage | `include/settings_storage.h`, `src/settings_storage.cpp` | Valid settings and device name in NVS |
| Scheduler | `src/main.cpp` | Sample, wait, alarm, mute, and safe settings apply states |

The `esp32dev` environment uses permanent USB peripheral power and the tested
100% LED brightness. The `lolin32_lite` environment keeps the 25% brightness
limit and adds
`ESPNOISE_SWITCHED_PERIPHERAL_POWER=1`. Detection code does not change between
the two power systems.

## Upload

The full-size board was found at `/dev/cu.usbserial-0001` during the first
inspection. The path can change after a reconnect.

```sh
uv run --locked python tools/pio.py run --environment esp32dev --target upload --upload-port /dev/cu.usbserial-0001
uv run --locked python tools/pio.py device monitor --port /dev/cu.usbserial-0001 --baud 115200
```

For the WEMOS, connect the external USB-C panel cable to a computer. Then find
its port with `uv run --locked python tools/pio.py device list` and use the
`lolin32_lite` environment.

Do not upload firmware until the user asks for an upload. A build does not
change a connected board.

## Runtime settings

`include/config.h` contains the compiled defaults and limits. A bonded BLE
client can change the LED brightness, buzzer volume, three thresholds, K, N,
the decision window, X, and mute time. The firmware validates the complete
32-byte packet before it applies a change. It applies the related values after
an observation ends. It then clears the detector history and alarm state.

The firmware saves a valid packet in NVS only when the complete packet changes.
Thus, a reconnect with the same revision does not make another flash write. A
bad saved record does not start. The firmware uses the compiled defaults
instead. The default device name is `ESPNoise-Device XXXX`, where `XXXX` is
the chip suffix. A synchronized custom suffix replaces `Device XXXX`. The
firmware saves it in a separate NVS record and keeps the `ESPNoise-` prefix.
Fast advertising lasts two minutes. A device with no saved bond keeps first
pairing available. After the first bond succeeds, new-phone pairing lasts two
minutes after startup. Slow connectable advertising continues after this time
for a bonded phone. Wi-Fi stays off.

The encrypted 20-byte status notification sends the current observation
maximum and the saved Green, Orange, and Red threshold counts. Live status is
limited to four measurement notifications each second. A control state change
can send an immediate notification. It sends scalar levels only. It does not
send or save raw microphone audio.

The main compiled values are:

- `kGreenThresholdDbfsX10`: alarm trigger sound set point in signed tenths
  of dBFS
- `kOrangeThresholdDbfsX10` and `kRedThresholdDbfsX10`: louder sound bands
- `kSampleDurationMs`: observation time K
- `kSamplePeriodMs`: observation period N
- `kDecisionWindowMs`: rolling history time
- `kTriggerSampleRatio`: saved maxima ratio X
- `kHistorySampleCount` and `kMinimumHistorySamples`: history requirements
- `kAlarmActiveSampleDurationMs` and `kAlarmOutputWindowMs`: active-alarm
  observation and output timing
- `kBuzzerSettleMs`: silent time between a buzzer pattern and microphone start
- `kGreenStyle`, `kOrangeStyle`, and `kRedStyle`: colors, blink rates, and
  buzzer patterns
- `kLedCount`: number of pixels in the data chain
- `kLedBrightnessMaximum`: board power and brightness limit
- `kPeripheralPowerEnablePin`: battery-build boost control
- `kBuzzerEnabled` and `kBuzzerVolumePercent`: buzzer output
- `kMicrophoneWarmupMs`: ignored microphone settling time after each wake

The firmware is set for 10 SK6812 RGB plus warm-white pixels with the `GRBW`
data order. Some sellers call these pixels `RGBWW`. If a one-pixel test gives
wrong colors, change `NEO_GRBW` in `src/alarm_output.cpp` to the order for the
strip.

Change GPIO pins in `include/board_profile.h`. If you change a pin, also change
`../docs/wiring.md`.

## Serial output

The firmware prints the current and maximum levels during an observation:

```text
level=-53.2 dBFS max=-41.7 dBFS frames=63 mute=off
```

It prints the saved-history count and green, orange, and red observation
percentages after each observation. One high observation does not show a
warning or change the alarm to a higher level. The complete decision history
controls the alarm. The firmware keeps the normal observation interval and
Bluetooth history active during mute. A second mute-button press within 750 ms
ends mute. A later single press restarts the complete mute period. The firmware
does not use application light sleep while BLE is active. This keeps
advertising and connected control available. The NimBLE controller can use its
own modem sleep. The battery profile also turns off the 5 V boost when the
alarm is off.
