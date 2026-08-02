# Noise detection and adjustment

## Definition of noise

The detector takes one sound sample of K seconds in each N-second period. It
divides the K-second sample into short frames. It calculates the sound level of
each frame. A frame is high when its level is at or above the threshold.

After the sample ends, the detector calculates:

```text
high ratio = high frames / all frames
```

The `NOISE` alarm starts when the high ratio is more than X. The result stays in
effect until the next complete sample gives a new result.

## Default values

| Parameter | Meaning | Default |
| --- | --- | ---: |
| K | Sound sample time | 10 seconds |
| N | Time from one sample start to the next sample start | 60 seconds |
| X | Required high-frame ratio | 50% |
| Threshold | High-frame sound level | -48 dBFS |
| Frame | One I2S read block | About 16 ms |

The device takes a sample immediately after startup. When the result is high,
the sign flashes until the next sample starts. The sign and buzzer stay off
during each sample so that they cannot change the microphone result. The new
result controls the alarm when the sample ends. The buzzer gives a short pulse
during each flash cycle when its physical switch is on.

The light color shows how far the final result is above X:

| Result with the default X of 50% | Alarm color |
| --- | --- |
| More than 50%, up to 65% | Yellow |
| More than 65%, up to 80% | Orange |
| More than 80% | Red |

The color uses the result from the complete K-second sample. It does not change
for each short audio frame. The sign stays off at 50% or less.

All four main values are in `firmware/include/config.h`:

```cpp
constexpr float kNoiseThresholdDbfs = -48.0F;
constexpr uint32_t kSampleDurationMs = 10UL * 1000UL;  // K
constexpr uint32_t kSamplePeriodMs = 60UL * 1000UL;    // N
constexpr float kHighFrameRatio = 0.50F;               // X
constexpr float kOrangeRatioMargin = 0.15F;
constexpr float kRedRatioMargin = 0.30F;
```

K must be greater than zero and must not be greater than N. X must be from zero
to one. The firmware checks these limits at startup.

## Why this rule helps

A short clap can make one or two frames high, but it will not make 50% of a
10-second sample high. Sustained voices, music, tools, or other long sounds can
make enough frames high to start the alarm.

Sampling reduces battery use, but it can miss a sound that starts and ends
between two samples. Decrease N or increase K if missed sounds are not
acceptable. This change reduces battery time.

## First test

1. Build the microphone and ESP32 only.
2. Upload the firmware.
3. Open the serial monitor at 115200 bit/s.
4. Read the level during a quiet sample.
5. Make normal room noise during a complete sample.
6. Make the sustained noise that must cause a warning during a complete sample.
7. Compare the high-frame percentages.
8. Adjust the threshold and X.
9. Connect the LED circuit and repeat the test.
10. Connect the buzzer last.

The serial output gives the current dBFS level and frame counts during each
sample. It gives the final percentage when the sample ends.

## Calibration to dBA

The nominal INMP441 sensitivity is -26 dBFS at 94 dB SPL. This gives a rough
conversion of `dB SPL = dBFS + 120`. Thus, -48 dBFS can be near 72 dB SPL. The
module, case, microphone direction, and frequency response cause error. Do not
call this value dBA until you calibrate it.

Use a sound level meter next to the case microphone hole. Use a steady sound.
Do not use speech for calibration.

1. Record the sound level meter value.
2. Record the ESPNoise dBFS value at the same time.
3. Calculate `offset = meter dBA - ESPNoise dBFS`.
4. Repeat at three sound levels.
5. Use the average offset only if the three offsets are close.

The firmware does not contain a full A-weighting filter. The offset is a room
adjustment, not a laboratory calibration.

## Mute and buzzer controls

- Press the mute button to stop the alarm and sound sampling for 30 minutes.
- Press it again to start a new 30-minute period.
- The detector takes a new sample when the mute time ends.
- Turn the buzzer switch off to cut buzzer power at any time.
- The buzzer switch does not change the light alarm.

## Privacy

The firmware does not save, send, or classify speech. It changes each audio
frame into one energy value and then discards the audio samples.
