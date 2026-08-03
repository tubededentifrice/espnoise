# Noise detection and adjustment

## Definition of noise

When there is no alarm, the detector listens for K seconds in each N-second
period. It saves the maximum dBFS frame level from that observation. The
default history contains the six observation maxima from the last minute.

```text
level ratio = observations at or above the level threshold / saved observations
```

The detector requires a complete history before it can start an alarm. It
checks red first, then orange, then green. A level starts when more than X of
the saved maxima are at or above that level threshold. With six observations
and X set to 50%, at least four observations must cross a threshold.

When the alarm is active, a separate quiet rule lets it stop quickly. Two
consecutive one-second checks must have maxima below the green threshold. The
firmware then stops the alarm and starts a 10-second fast-rearm window. During
this window, one new noisy check restarts the alarm. Ten seconds of quiet
clears the old history and returns the detector to the normal schedule.

Each normal observation that crosses a threshold gives one 500 ms flash in
the level color. This sample warning does not use the buzzer. If the rolling
history starts the alarm, the alarm output takes control instead.

## Default values

| Parameter | Meaning | Default |
| --- | --- | ---: |
| K | Observation time | 1 second |
| N | Time from one observation start to the next | 10 seconds |
| Decision window | Saved observation history | 60 seconds |
| History size | Decision window divided by N | 6 observations |
| Minimum history | Observations required before an alarm | 6 observations |
| X | Saved maxima required to start | More than 50%, or 4 of 6 |
| Green threshold | Noise, but not very loud | -55 dBFS |
| Orange threshold | Loud noise | -48 dBFS |
| Red threshold | Very loud noise | -42 dBFS |
| Saved statistic | Value from each observation | Maximum dBFS |
| Microphone settling time | Ignored time before each observation | 300 ms |
| Quiet clear rule | Consecutive maxima below green | 2 observations |
| Alarm clear observation | Active-alarm listening time | 1 second |
| Output window | Time for the buzzer pattern | 250 ms |
| Buzzer settling gap | Silence before microphone start | 100 ms |
| Sample warning | One silent level-color flash | 500 ms |
| Fast-rearm window | Fast checks after an alarm stops | 10 seconds |
| Fast-rearm gap | Time between fast checks | 250 ms |
| Orange time escalation | Persistent alarm becomes at least orange | 15 seconds |
| Red time escalation | Persistent alarm becomes red | 30 seconds |
| Frame | One I2S read block | About 8 ms |

The device takes its first observation immediately after startup. It then
takes one observation every ten seconds. The lights and buzzer stay off during
normal observations. When the rolling history starts an alarm, the firmware
repeats this active-alarm cycle:

1. Give the level-specific output for 250 ms.
2. Listen for one second with the buzzer off.
3. Keep the lights flashing during the check.
4. Clear the quiet counter if the one-second maximum reaches green.
5. Stop after two consecutive quiet checks.
6. Start a 10-second fast-rearm window.
7. Restart the alarm after one noisy fast-rearm check.
8. After 10 seconds of quiet, clear the six-value trigger history and return
   to the normal schedule.

The conservative configured worst time to stop the output is 4.6 seconds after
continuous noise stops. This includes the rest of a possibly contaminated
check, the 300 ms microphone settling periods, two quiet checks, and two
possible 250 ms output windows with 100 ms buzzer settling gaps. The device
then stays ready for a fast restart for 10 seconds.

The firmware never commands the buzzer on while an audio check is active. It
adds the 100 ms settling gap after each buzzer window, starts the microphone,
and discards another 300 ms of warm-up audio before it measures a sample. This
prevents the louder buzzer and its short case vibration from entering the
noise result.

## Alarm levels and patterns

The highest rolling threshold with at least four of six observations sets the
initial alarm level. During an active alarm, each one-second maximum updates
the measured level when it reaches green, orange, or red.

| Level | Light | Buzzer pattern |
| --- | --- | --- |
| Green | Green, slow blink | Silent |
| Orange | Orange, medium blink | Two notes at 1,500 Hz |
| Red | Red, fast blink | Three faster notes at 2,400 Hz |

The alarm also becomes more urgent with time. After 15 seconds, its minimum
level is orange. After 30 seconds, its level is red. A loud sound can select
orange or red immediately. The buzzer uses the configured 50% electrical tone
amplitude. The physical switch can disable all buzzer sounds.

## Configuration values

All detection, release, color, blink, and buzzer-pattern values are in
`firmware/include/config.h`. The main values are:

```cpp
constexpr float kGreenThresholdDbfs = -55.0F;
constexpr float kOrangeThresholdDbfs = -48.0F;
constexpr float kRedThresholdDbfs = -42.0F;
constexpr uint32_t kMicrophoneWarmupMs = 300;
constexpr uint32_t kSampleDurationMs = 1UL * 1000UL;    // K
constexpr uint32_t kSamplePeriodMs = 10UL * 1000UL;     // N
constexpr uint32_t kDecisionWindowMs = 60UL * 1000UL;
constexpr float kTriggerSampleRatio = 0.50F;            // X
constexpr size_t kHistorySampleCount = 6;
constexpr size_t kMinimumHistorySamples = 6;
constexpr uint32_t kAlarmClearSampleDurationMs = 1000;
constexpr uint32_t kAlarmOutputWindowMs = 250;
constexpr uint32_t kBuzzerSettleMs = 100;
constexpr uint8_t kQuietSamplesToClear = 2;
constexpr bool kResetHistoryAfterAlarmClear = true;
constexpr uint32_t kSampleWarningMs = 500;
constexpr uint32_t kFastRearmWindowMs = 10UL * 1000UL;
constexpr uint32_t kFastRearmSampleGapMs = 250;
constexpr uint32_t kEscalateToOrangeMs = 15UL * 1000UL;
constexpr uint32_t kEscalateToRedMs = 30UL * 1000UL;
constexpr uint8_t kBuzzerVolumePercent = 50;
```

K must be greater than zero and must not be greater than N. The decision window
must be a multiple of N. X must be from zero to one. The thresholds must
increase from green to orange to red. The firmware checks these limits, the
buzzer pattern duration, and the five-second clear-time limit at startup.

## Why this rule helps

A short event can make one saved maximum high. It cannot start the alarm by
itself because four of six saved maxima must be high. Sustained loud speech or
other repeated noise is more likely to affect four observations and start the
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
7. Make sustained coworking noise through at least four observations.
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
one short peak because at least four of six observations must cross a
threshold. Check the levels again during a normal coworking test.

## Mute and buzzer controls

- Press the mute button to stop the alarm and sound sampling for 30 minutes.
- Press it again to start a new 30-minute period.
- The detector takes a new sample when the mute time ends.
- Turn the buzzer switch off to cut buzzer power at any time.
- The buzzer switch does not change the light alarm.

## Privacy

The firmware does not save, send, or classify speech. It changes each audio
frame into one energy value and then discards the audio samples.
