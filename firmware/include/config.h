#pragma once

#include <Arduino.h>

#ifndef ESPNOISE_SAMPLE_DURATION_MS
#define ESPNOISE_SAMPLE_DURATION_MS (1UL * 1000UL)
#endif

#ifndef ESPNOISE_SAMPLE_PERIOD_MS
#define ESPNOISE_SAMPLE_PERIOD_MS (10UL * 1000UL)
#endif

#ifndef ESPNOISE_TRIGGER_SAMPLE_PERCENT
#define ESPNOISE_TRIGGER_SAMPLE_PERCENT 50
#endif

#ifndef ESPNOISE_DECISION_WINDOW_MS
#define ESPNOISE_DECISION_WINDOW_MS (60UL * 1000UL)
#endif

#ifndef ESPNOISE_LED_BRIGHTNESS
#define ESPNOISE_LED_BRIGHTNESS 64
#endif

namespace config {

struct AlarmStyle {
  uint8_t red;
  uint8_t green;
  uint8_t blue;
  uint8_t warmWhite;
  uint32_t blinkHalfPeriodMs;
  uint32_t buzzerFrequencyHz;
  uint16_t buzzerPulseMs;
  uint16_t buzzerGapMs;
  uint8_t buzzerPulseCount;
};

constexpr uint32_t buzzerPatternDurationMs(const AlarmStyle& style) {
  return style.buzzerPulseCount == 0
             ? 0
             : style.buzzerPulseCount * style.buzzerPulseMs +
                   (style.buzzerPulseCount - 1) * style.buzzerGapMs;
}

// Sign output.
constexpr uint8_t kLedCount = 10;
constexpr uint8_t kLedBrightness = ESPNOISE_LED_BRIGHTNESS;

// Audio and decision values. Levels are dBFS until the microphone is
// calibrated against a sound level meter.
constexpr uint32_t kSampleRateHz = 16000;
constexpr float kGreenThresholdDbfs = -55.0F;
constexpr float kOrangeThresholdDbfs = -48.0F;
constexpr float kRedThresholdDbfs = -42.0F;
constexpr float kDcBlockFactor = 0.995F;
constexpr size_t kAudioBlockSamples = 256;
// Ignore microphone startup data after the I2S clock starts. This prevents a
// wake transient from becoming the maximum value of an observation.
constexpr uint32_t kMicrophoneWarmupMs = 300;

// Listen for K seconds in each N-second period. Save the maximum frame level
// from each K-second observation. Start the alarm when more than X of the
// saved observations in the decision window are above a level threshold.
constexpr uint32_t kSampleDurationMs = ESPNOISE_SAMPLE_DURATION_MS;  // K
constexpr uint32_t kSamplePeriodMs = ESPNOISE_SAMPLE_PERIOD_MS;      // N
constexpr uint32_t kDecisionWindowMs = ESPNOISE_DECISION_WINDOW_MS;
static_assert(kSamplePeriodMs > 0, "The sample period must be greater than 0");
static_assert(kDecisionWindowMs >= kSamplePeriodMs,
              "The decision window must contain at least one sample period");
static_assert(kDecisionWindowMs % kSamplePeriodMs == 0,
              "The decision window must be a multiple of the sample period");

constexpr float kTriggerSampleRatio =
    static_cast<float>(ESPNOISE_TRIGGER_SAMPLE_PERCENT) / 100.0F;     // X
constexpr size_t kHistorySampleCount =
    kDecisionWindowMs / kSamplePeriodMs;
constexpr size_t kMinimumHistorySamples = kHistorySampleCount;
static_assert(kHistorySampleCount > 0,
              "The decision history must contain at least one observation");

// Use consecutive one-second quiet checks to stop the active alarm. Clear the
// rolling history after the later fast-rearm window stays quiet.
constexpr uint32_t kAlarmClearSampleDurationMs = 1000;
constexpr uint32_t kAlarmOutputWindowMs = 250;
constexpr uint32_t kBuzzerSettleMs = 100;
constexpr uint8_t kQuietSamplesToClear = 2;
constexpr bool kResetHistoryAfterAlarmClear = true;

// Give one silent color flash after a normal observation crosses a threshold.
constexpr uint32_t kSampleWarningMs = 500;

// After an alarm clears, keep making short checks for this time. Noise can
// restart the alarm after one check without a new full decision history.
constexpr uint32_t kFastRearmWindowMs = 10UL * 1000UL;
constexpr uint32_t kFastRearmSampleGapMs = 250;

// A persistent alarm becomes more urgent even when its measured level stays
// green. Set a value to zero to apply that escalation immediately.
constexpr uint32_t kEscalateToOrangeMs = 15UL * 1000UL;
constexpr uint32_t kEscalateToRedMs = 30UL * 1000UL;

// User controls.
constexpr uint32_t kMute30Ms = 30UL * 60UL * 1000UL;
constexpr uint32_t kButtonDebounceMs = 35;

// Alarm outputs.
constexpr bool kBuzzerEnabled = true;
constexpr uint8_t kBuzzerVolumePercent = 50;
constexpr uint32_t kPeripheralPowerWarmupMs = 5;

// Light and buzzer styles. Green is light only. Orange gives two warning
// notes. Red gives three faster, higher notes.
constexpr AlarmStyle kGreenStyle = {
    0, 255, 0, 0, 500, 900, 0, 0, 0,
};
constexpr AlarmStyle kOrangeStyle = {
    255, 50, 0, 0, 300, 1500, 70, 55, 2,
};
constexpr AlarmStyle kRedStyle = {
    255, 0, 0, 24, 150, 2400, 50, 35, 3,
};

}  // namespace config
