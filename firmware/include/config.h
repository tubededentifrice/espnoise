#pragma once

#include <Arduino.h>

#ifndef ESPNOISE_SAMPLE_DURATION_MS
#define ESPNOISE_SAMPLE_DURATION_MS (10UL * 1000UL)
#endif

#ifndef ESPNOISE_SAMPLE_PERIOD_MS
#define ESPNOISE_SAMPLE_PERIOD_MS (60UL * 1000UL)
#endif

#ifndef ESPNOISE_HIGH_FRAME_PERCENT
#define ESPNOISE_HIGH_FRAME_PERCENT 50
#endif

#ifndef ESPNOISE_LED_BRIGHTNESS
#define ESPNOISE_LED_BRIGHTNESS 64
#endif

namespace config {

// Sign output.
constexpr uint8_t kLedCount = 10;
constexpr uint8_t kLedBrightness = ESPNOISE_LED_BRIGHTNESS;

// Audio and decision values.
constexpr uint32_t kSampleRateHz = 16000;
constexpr float kNoiseThresholdDbfs = -48.0F;
constexpr float kDcBlockFactor = 0.995F;
constexpr size_t kAudioBlockSamples = 256;

// Listen for K seconds in each N-second period. Start the alarm when more than
// X of the audio frames in the K-second sample are above the threshold.
constexpr uint32_t kSampleDurationMs = ESPNOISE_SAMPLE_DURATION_MS;  // K
constexpr uint32_t kSamplePeriodMs = ESPNOISE_SAMPLE_PERIOD_MS;      // N
constexpr float kHighFrameRatio =
    static_cast<float>(ESPNOISE_HIGH_FRAME_PERCENT) / 100.0F;         // X

// Alarm color bands. The ratio is the result from the last complete sample.
// X to X + 15% is yellow, the next 15% is orange, and higher is red.
constexpr float kOrangeRatioMargin = 0.15F;
constexpr float kRedRatioMargin = 0.30F;

// User controls.
constexpr uint32_t kMute30Ms = 30UL * 60UL * 1000UL;
constexpr uint32_t kButtonDebounceMs = 35;

// Alarm outputs.
constexpr bool kBuzzerEnabled = true;
constexpr uint32_t kBuzzerFrequencyHz = 2400;
constexpr uint8_t kBuzzerDuty = 128;  // 50% of an 8-bit PWM period.
constexpr uint32_t kAlarmHalfPeriodMs = 500;
constexpr uint32_t kBuzzerOnMs = 100;
constexpr uint32_t kPeripheralPowerWarmupMs = 5;

}  // namespace config
