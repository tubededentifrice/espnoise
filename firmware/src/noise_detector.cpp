#include "noise_detector.h"

#include "config.h"

void NoiseDetector::beginWindow() {
  frameCount_ = 0;
  highFrameCount_ = 0;
}

void NoiseDetector::addFrame(float dbfs) {
  ++frameCount_;
  if (dbfs >= config::kNoiseThresholdDbfs) {
    ++highFrameCount_;
  }
}

float NoiseDetector::highRatio() const {
  return frameCount_ == 0
             ? 0.0F
             : static_cast<float>(highFrameCount_) / frameCount_;
}

bool NoiseDetector::alarmRequired() const {
  return highRatio() > config::kHighFrameRatio;
}

size_t NoiseDetector::frameCount() const { return frameCount_; }

size_t NoiseDetector::highFrameCount() const { return highFrameCount_; }
