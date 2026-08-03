#pragma once

#include <array>
#include <cstddef>

#include "alarm_level.h"
#include "config.h"

class NoiseDetector {
 public:
  void beginSample();
  void addFrame(float dbfs);

  float sampleMaximumDbfs() const;
  AlarmLevel sampleLevel() const;
  size_t frameCount() const;

  void commitSample();
  void resetHistory();
  size_t historyCount() const;
  float greenSampleRatio() const;
  float orangeSampleRatio() const;
  float redSampleRatio() const;
  AlarmLevel historyAlarmLevel() const;

 private:
  float historyRatioAtOrAbove(float thresholdDbfs) const;

  size_t frameCount_ = 0;
  float sampleMaximumDbfs_ = -120.0F;
  std::array<float, config::kHistorySampleCount> history_ = {};
  size_t historyCount_ = 0;
  size_t historyWriteIndex_ = 0;
};
