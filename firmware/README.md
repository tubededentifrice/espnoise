# Firmware

## Requirements

- PlatformIO Core or the PlatformIO IDE extension
- A USB data cable
- The `esp32dev` board definition for the full-size USB-C board
- The `lolin32_lite` board definition for the WEMOS battery board

The environment uses the Arduino framework. It pins the ESP32 PlatformIO
package and the LED library so that later builds use the same base.

## Build

From this directory, run:

```sh
pio run
```

This command builds the first USB-powered board. The battery board stays an
optional environment. Build it only when you start the battery stage:

```sh
pio run --environment esp32dev
pio run --environment lolin32_lite
```

Use the temporary LED-test environment to show red, green, blue, and
warm-white for one second each after startup:

```sh
pio run --environment esp32dev_led_test --target upload
```

For a one-pixel bench test, use the fast profile. It listens for 3 seconds in
each 5-second period, uses a 30% high-frame ratio, and uses full LED
brightness. It also plays a short buzzer chime after the LED test:

```sh
pio run --environment esp32dev_fast_test --target upload
```

The tested passive piezo buzzer uses a 2N3904 low-side driver. GPIO23 connects
to its base through 5.1 kohm. The firmware drives it with 2.4 kHz PWM. The
hard switch stays in the buzzer 5 V wire.

## Firmware modules

| Module | Files | Responsibility |
| --- | --- | --- |
| Board profile | `include/board_profile.h` | GPIO pins and optional switched power |
| User settings | `include/config.h` | K, N, X, threshold, colors, and timing |
| Audio input | `include/audio_input.h`, `src/audio_input.cpp` | INMP441 and dBFS frames |
| Detector | `include/noise_detector.h`, `src/noise_detector.cpp` | High-frame count and X decision |
| Alarm output | `include/alarm_output.h`, `src/alarm_output.cpp` | SK6812, buzzer, and optional power switch |
| Mute control | `include/mute_button.h`, `src/mute_button.cpp` | Button filtering |
| Scheduler | `src/main.cpp` | Sample, wait, alarm, mute, and sleep states |

The `esp32dev` environment uses permanent USB peripheral power. The
`lolin32_lite` environment adds
`ESPNOISE_SWITCHED_PERIPHERAL_POWER=1`. Detection code does not change between
the two power systems.

## Upload

The full-size board was found at `/dev/cu.usbserial-0001` during the first
inspection. The path can change after a reconnect.

```sh
pio run --environment esp32dev --target upload --upload-port /dev/cu.usbserial-0001
pio device monitor --port /dev/cu.usbserial-0001 --baud 115200
```

For the WEMOS, connect the external USB-C panel cable to a computer. Then find
its port with `pio device list` and use the `lolin32_lite` environment.

Do not upload firmware until the user asks for an upload. A build does not
change a connected board.

## Settings

Edit `include/config.h` for the first adjustment. The main values are:

- `kNoiseThresholdDbfs`: sound set point
- `kSampleDurationMs`: listening time K
- `kSamplePeriodMs`: period N
- `kHighFrameRatio`: high-frame ratio X
- `kOrangeRatioMargin` and `kRedRatioMargin`: alarm color limits
- `kLedCount`: number of pixels in the data chain
- `kLedBrightness`: global power and brightness limit
- `kPeripheralPowerEnablePin`: battery-build boost control
- `kBuzzerEnabled`: optional buzzer output

The firmware is set for 10 SK6812 RGB plus warm-white pixels with the `GRBW`
data order. Some sellers call these pixels `RGBWW`. If a one-pixel test gives
wrong colors, change `NEO_GRBW` in `src/main.cpp` to the order for the strip.

Change GPIO pins in `include/board_profile.h`. If you change a pin, also change
`../docs/wiring.md`.

## Serial output

The firmware prints one line each second while it takes a sound sample:

```text
level=-53.2 dBFS high=12/62 mute=off
```

It prints the final high-frame percentage after each sample. The ESP32 uses
light sleep between samples when the alarm is off. In the battery build, the
firmware also turns off the 5 V boost when the alarm is off.
