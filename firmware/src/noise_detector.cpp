#include "noise_detector.h"

#include "config.h"

void NoiseDetector::beginSample() {
  frameCount_ = 0;
  sampleMaximumDbfs_ = -120.0F;
}

void NoiseDetector::addFrame(float dbfs) {
  ++frameCount_;
  if (dbfs > sampleMaximumDbfs_) {
    sampleMaximumDbfs_ = dbfs;
  }
}

float NoiseDetector::sampleMaximumDbfs() const {
  return sampleMaximumDbfs_;
}

AlarmLevel NoiseDetector::sampleLevel() const {
  if (sampleMaximumDbfs_ >= config::kRedThresholdDbfs) {
    return AlarmLevel::kRed;
  }
  if (sampleMaximumDbfs_ >= config::kOrangeThresholdDbfs) {
    return AlarmLevel::kOrange;
  }
  if (sampleMaximumDbfs_ >= config::kGreenThresholdDbfs) {
    return AlarmLevel::kGreen;
  }
  return AlarmLevel::kQuiet;
}

size_t NoiseDetector::frameCount() const { return frameCount_; }

void NoiseDetector::commitSample() {
  if (frameCount_ == 0) {
    return;
  }
  history_[historyWriteIndex_] = sampleMaximumDbfs_;
  historyWriteIndex_ =
      (historyWriteIndex_ + 1) % config::kHistorySampleCount;
  if (historyCount_ < config::kHistorySampleCount) {
    ++historyCount_;
  }
}

void NoiseDetector::resetHistory() {
  historyCount_ = 0;
  historyWriteIndex_ = 0;
}

size_t NoiseDetector::historyCount() const { return historyCount_; }

float NoiseDetector::historyRatioAtOrAbove(float thresholdDbfs) const {
  if (historyCount_ == 0) {
    return 0.0F;
  }
  size_t highCount = 0;
  for (size_t index = 0; index < historyCount_; ++index) {
    if (history_[index] >= thresholdDbfs) {
      ++highCount;
    }
  }
  return static_cast<float>(highCount) / historyCount_;
}

float NoiseDetector::greenSampleRatio() const {
  return historyRatioAtOrAbove(config::kGreenThresholdDbfs);
}

float NoiseDetector::orangeSampleRatio() const {
  return historyRatioAtOrAbove(config::kOrangeThresholdDbfs);
}

float NoiseDetector::redSampleRatio() const {
  return historyRatioAtOrAbove(config::kRedThresholdDbfs);
}

AlarmLevel NoiseDetector::historyAlarmLevel() const {
  if (historyCount_ < config::kMinimumHistorySamples) {
    return AlarmLevel::kQuiet;
  }
  if (redSampleRatio() > config::kTriggerSampleRatio) {
    return AlarmLevel::kRed;
  }
  if (orangeSampleRatio() > config::kTriggerSampleRatio) {
    return AlarmLevel::kOrange;
  }
  if (greenSampleRatio() > config::kTriggerSampleRatio) {
    return AlarmLevel::kGreen;
  }
  return AlarmLevel::kQuiet;
}
