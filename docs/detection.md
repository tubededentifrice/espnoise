# Noise detection and adjustment

## Definition of noise

When there is no alarm, the detector listens for K seconds in each N-second
period. It saves the maximum dBFS frame level from that observation. The
default history contains the six observation maxima from the last minute.

```text
level ratio = observations at or above the level threshold / saved observations
```

The detector requires a complete history before it can start an alarm. It
checks red first, then orange, then green. A level starts when at least X
percent of the saved maxima are at or above that level threshold. With six
observations and X set to 50%, at least three observations must cross a
threshold.

When the alarm is active, the detector makes frequent one-second observations.
It saves each maximum in the same six-value rolling history. After each
observation, it checks the Green, Orange, and Red counts again. The highest
threshold with at least three values sets the output. No single observation
can change the output to a higher level.

One normal observation cannot start a light or buzzer warning. Only the
rolling decision can start a warning. Thus, one cough, dropped object, or other
sporadic sound does not make the sign flash.

## Default values

| Parameter | Meaning | Default |
| --- | --- | ---: |
| K | Observation time | 1 second |
| N | Time from one observation start to the next | 10 seconds |
| Decision window | Saved observation history | 60 seconds |
| History size | Decision window divided by N | 6 observations |
| Minimum history | Observations required before an alarm | 6 observations |
| X | Saved maxima required to start | At least 50%, or 3 of 6 |
| Green threshold | Noise, but not very loud | -55 dBFS |
| Orange threshold | Loud noise | -48 dBFS |
| Red threshold | Very loud noise | -42 dBFS |
| Saved statistic | Value from each observation | Maximum dBFS |
| Microphone settling time | Ignored time before each observation | 300 ms |
| Active-alarm observation | Listening time during an alarm | 1 second |
| Output window | Time for the buzzer pattern | 250 ms |
| Buzzer settling gap | Silence before microphone start | 100 ms |
| Frame | One I2S read block | About 8 ms |

The device takes its first observation immediately after startup. It then
takes one observation every ten seconds. The lights and buzzer stay off during
normal observations. When the rolling history starts an alarm, the firmware
repeats this active-alarm cycle:

1. Give the level-specific output for 250 ms.
2. Listen for one second with the buzzer off.
3. Keep the lights flashing during the check.
4. Save the maximum and remove the oldest value from the six-value history.
5. Set the output to the highest threshold that has at least three values.
6. Stop the alarm when fewer than three values reach Green.
7. Return to the normal N-second schedule after the alarm stops.

The firmware never commands the buzzer on while an audio check is active. It
adds the 100 ms settling gap after each buzzer window, starts the microphone,
and discards another 300 ms of warm-up audio before it measures a sample. This
prevents the louder buzzer and its short case vibration from entering the
noise result.

## Alarm levels and patterns

The highest rolling threshold with at least three of six observations always
sets the alarm level. During an active alarm, each one-second maximum replaces
the oldest value before the firmware calculates the three counts again.

| Level | Light | Buzzer pattern |
| --- | --- | --- |
| Green | Green, slow blink | Silent |
| Orange | Orange, medium blink | Two notes at 1,500 Hz |
| Red | Red, fast blink | Three faster notes at 2,400 Hz |

The alarm output uses the rolling level. A Green alarm stays Green while the
Orange and Red counts stay below the trigger count. The buzzer uses the 50%
electrical tone amplitude. The physical switch can disable all buzzer sounds.

## Configuration values

All default detection, release, color, blink, and buzzer-pattern values are in
`firmware/include/config.h`. The phone app can replace the main runtime values.
The firmware validates and saves the complete profile before it uses it. The
main values are:

```cpp
constexpr int16_t kGreenThresholdDbfsX10 = -550;
constexpr int16_t kOrangeThresholdDbfsX10 = -480;
constexpr int16_t kRedThresholdDbfsX10 = -420;
constexpr uint32_t kMicrophoneWarmupMs = 300;
constexpr uint32_t kSampleDurationMs = 1UL * 1000UL;    // K
constexpr uint32_t kSamplePeriodMs = 10UL * 1000UL;     // N
constexpr uint32_t kDecisionWindowMs = 60UL * 1000UL;
constexpr float kTriggerSampleRatio = 0.50F;            // X
constexpr size_t kHistorySampleCount = 6;
constexpr size_t kMinimumHistorySamples = 6;
constexpr uint32_t kAlarmActiveSampleDurationMs = 1000;
constexpr uint32_t kAlarmOutputWindowMs = 250;
constexpr uint32_t kBuzzerSettleMs = 100;
constexpr uint8_t kBuzzerVolumePercent = 50;
```

K must be greater than zero and must not be greater than N. The decision window
must be a multiple of N. The compiled X ratio is from zero through one. The
runtime X value is an integer percent from 1 through 99. The thresholds must
increase from green to orange to red. The firmware checks these limits and the
buzzer pattern duration at startup.

## Why this rule helps

A short event can make one saved maximum high. It cannot start the alarm by
itself because three of six saved maxima must be high. Sustained loud speech or
other repeated noise is more likely to affect three observations and start the
warning.

The default schedule observes only one second in every ten seconds. It can miss
sound that occurs in the nine-second gaps. If the prototype misses real
coworking conversations, first change N from ten seconds to five seconds. This
gives 12 observations per minute and 20% time coverage.

An absolute maximum is also sensitive to a cough, chair movement, or dropped
object during an observation. The rolling majority limits this effect. If
sporadic events still affect too many observations, a later test can compare
the maximum with a 90th-percentile observation value.

## First test

1. Build the microphone and ESP32 only.
2. Upload the firmware.
3. Open the serial monitor at 115200 bit/s.
4. Read the level during a quiet sample.
5. Record six observations in a normal quiet room.
6. Make one short loud sound and confirm that it does not start the alarm.
7. Make sustained coworking noise through at least three observations.
8. Compare the saved green, orange, and red percentages.
9. Adjust the thresholds, observation period, and X.
10. Connect the LED circuit and repeat the test.
11. Connect the buzzer last.

The serial output gives the maximum dBFS value from each observation. It also
gives the history count, green, orange, and red observation percentages, alarm
state, and selected level.

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

## Production case adjustment

The production case adjustment on 2026-08-03 used one 10-second target sample
for each alarm level. Each result was the median of ten consecutive one-second
maxima. This method used the installed microphone and case.

| Target | Median | One-second range |
| --- | ---: | ---: |
| Green | -50.7 dBFS | -53.9 to -43.7 dBFS |
| Orange | -48.3 dBFS | -53.0 to -45.5 dBFS |
| Red | -40.5 dBFS | -45.6 to -35.0 dBFS |

After review of the test, the selected thresholds are -55 dBFS for green,
-48 dBFS for orange, and -42 dBFS for red.

The green and orange ranges overlap. The rolling decision limits the effect of
one short peak because at least three of six observations must cross a
threshold. Check the levels again during a normal coworking test.

## Mute and buzzer controls

- Press the mute button to stop the alarm outputs for 30 minutes.
- Sound observations and Bluetooth history continue at the normal interval.
- Press the button a second time within 750 ms to end mute.
- A single press after 750 ms starts a new 30-minute period.
- When mute ends, a saved history above a threshold starts the alarm again.
- Turn the buzzer switch off to cut buzzer power at any time.
- The buzzer switch does not change the light alarm.

## Privacy

The firmware does not save, send, or classify speech. It changes each audio
frame into one energy value and then discards the audio samples.
