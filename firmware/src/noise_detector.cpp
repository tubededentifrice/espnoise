#include "noise_detector.h"

#include "config.h"

void NoiseDetector::setSettings(const RuntimeSettings& settings) {
  settings_ = settings;
  resetHistory();
  beginSample();
}

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
  if (sampleMaximumDbfs_ >= settings_.redThresholdDbfsX10 / 10.0F) {
    return AlarmLevel::kRed;
  }
  if (sampleMaximumDbfs_ >= settings_.orangeThresholdDbfsX10 / 10.0F) {
    return AlarmLevel::kOrange;
  }
  if (sampleMaximumDbfs_ >= settings_.greenThresholdDbfsX10 / 10.0F) {
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
  const size_t historyCapacity = settings_.historySampleCount();
  historyWriteIndex_ = (historyWriteIndex_ + 1) % historyCapacity;
  if (historyCount_ < historyCapacity) {
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
  return historyRatioAtOrAbove(settings_.greenThresholdDbfsX10 / 10.0F);
}

float NoiseDetector::orangeSampleRatio() const {
  return historyRatioAtOrAbove(settings_.orangeThresholdDbfsX10 / 10.0F);
}

float NoiseDetector::redSampleRatio() const {
  return historyRatioAtOrAbove(settings_.redThresholdDbfsX10 / 10.0F);
}

AlarmLevel NoiseDetector::historyAlarmLevel() const {
  if (historyCount_ < settings_.historySampleCount()) {
    return AlarmLevel::kQuiet;
  }
  const float triggerRatio = settings_.triggerSamplePercent / 100.0F;
  if (redSampleRatio() > triggerRatio) {
    return AlarmLevel::kRed;
  }
  if (orangeSampleRatio() > triggerRatio) {
    return AlarmLevel::kOrange;
  }
  if (greenSampleRatio() > triggerRatio) {
    return AlarmLevel::kGreen;
  }
  return AlarmLevel::kQuiet;
}
