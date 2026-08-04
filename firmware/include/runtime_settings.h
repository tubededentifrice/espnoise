#pragma once

#include <cstddef>
#include <cstdint>

#include "config.h"

struct RuntimeSettings {
  uint8_t ledBrightnessPercent = config::kDefaultLedBrightnessPercent;
  uint8_t buzzerVolumePercent = config::kBuzzerVolumePercent;
  int16_t greenThresholdDbfsX10 = config::kGreenThresholdDbfsX10;
  int16_t orangeThresholdDbfsX10 = config::kOrangeThresholdDbfsX10;
  int16_t redThresholdDbfsX10 = config::kRedThresholdDbfsX10;
  uint32_t sampleDurationMs = config::kSampleDurationMs;
  uint32_t samplePeriodMs = config::kSamplePeriodMs;
  uint32_t decisionWindowMs = config::kDecisionWindowMs;
  uint8_t triggerSamplePercent = ESPNOISE_TRIGGER_SAMPLE_PERCENT;
  uint32_t muteDurationSeconds = config::kDefaultMuteDurationSeconds;

  size_t historySampleCount() const {
    return samplePeriodMs == 0 ? 0 : decisionWindowMs / samplePeriodMs;
  }

  size_t requiredTriggerSampleCount() const {
    return (historySampleCount() * triggerSamplePercent + 99U) / 100U;
  }
};
