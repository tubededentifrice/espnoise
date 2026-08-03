# ESPNoise

ESPNoise is a room noise warning sign. An ESP32 reads an INMP441 digital
microphone. If enough recent observations are above a set level, the sign
flashes `NOISE`. An optional buzzer can also give a short warning.

The product is for a coworking space. It helps participants notice when they
are too loud for a sustained time. They can then lower their volume or move to
another place. A sporadic cough, dropped object, or other short sound must not
start the warning by itself.

This repository contains the first hardware design and a firmware base. The
3D case will follow after the parts are measured.

## First build

The first build uses the full-size USB-C ESP32 without a battery. USB supplies
the board, 10 SK6812 pixels, and the optional buzzer. The WEMOS battery option
stays available as a later module, but it is not part of the first build.

Read the [modular build stages](docs/modular-build.md) before assembly. Each
stage has a separate test. Connectors keep the microphone, sign, controls,
buzzer, and future power system replaceable.

The first build uses a separate two-wire USB-C power module. The external
USB-C connector supplies 5 V only. The ESP32 USB-C connector stays inside the
case as a service connector for firmware upload and the serial monitor.

## Available controller options

Both controller options use the same module interfaces and detector settings.

| Option | Controller | Power | Battery |
| --- | --- | --- | --- |
| USB power | Full-size ESP32 board with USB-C | USB-C, 5 V | None |
| Battery | WEMOS LOLIN32 Lite V1.0.0 | USB-C panel cable to Micro-USB | Internal protected 3.7 V LiPo |

The normal firmware build target is now `esp32dev`. The optional WEMOS build
target adds the switched 5 V power module only when it is selected.

## Current design

- Microphone: INMP441 I2S module at 16 kHz
- Sign light: ten SK6812 RGB plus warm-white pixels from a 60-pixel/m strip
- Light levels: green, orange, and red from separate sound thresholds
- Controls: one 30-minute mute button and one hard buzzer switch
- Sound: tested passive piezo buzzer with a 5 V, 2N3904 driver; the hard
  switch cuts its 5 V supply
- External power: one USB-C connector
- Battery option: internal protected 10,000 mAh 1S LiPo pack
- Privacy: the firmware does not record or save audio

Some sellers call this strip `RGBWW`. For this project, this name means red,
green, blue, and one warm-white channel. It is a four-channel, 32-bit SK6812
pixel. It is not a five-channel RGB plus two-white strip.

The default rule listens for one second every ten seconds. It saves the maximum
level from each observation. At least four of the last six observations must
cross a threshold before the alarm starts. Thus, one sporadic loud sound does
not start the warning. Two consecutive quiet one-second checks clear an active
alarm within the configured five-second limit. The thresholds, ratios, timing,
colors, and buzzer patterns are in one configuration file.

## Start here

1. Read the [bill of materials](docs/bom.md).
2. Follow the [modular build stages](docs/modular-build.md).
3. Read the [wiring instructions](docs/wiring.md).
4. Read the [power and battery limits](docs/power-and-battery.md).
5. Build and upload the [firmware](firmware/README.md).
6. Use the [test and adjustment procedure](docs/detection.md).
7. Measure the parts before you make the [3D case](cad/README.md).

## Repository map

```text
cad/                 Case requirements and measurements
docs/                Design, wiring, parts, and test information
firmware/            PlatformIO firmware for the ESP32
```

## Important limits

- The set level is in dBFS until you calibrate the microphone. It is not a
  certified dBA sound level.
- Do not connect a battery to the full-size USB-C ESP32 board.
- Use the WEMOS battery socket only with one protected 3.7 V LiPo pack.
- Confirm the battery plug polarity with a multimeter before connection.
- Do not use the 6 V to 30 V buck converters. Their minimum input voltage is
  too high for a 3.7 V battery or a 5 V USB supply.
- Keep the LED brightness at 25% or less until power tests are complete.

## Project status

The firmware is a first working base and builds for both controller options.
The electrical design is ready for a breadboard test. The case design needs
photos and exact dimensions of the selected parts.

No project license is selected yet.
