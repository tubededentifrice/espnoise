#pragma once

#include <Arduino.h>

#include <cstddef>

class CalibrationSession {
 public:
  static constexpr size_t kSecondCount = 10;

  void start(char target, uint32_t now);
  void cancel();
  void addFrame(float dbfs);
  bool update(uint32_t now);

  bool active() const;
  bool complete() const;
  char target() const;
  size_t completedSecondCount() const;
  float lastSecondMaximumDbfs() const;
  float minimumDbfs() const;
  float medianDbfs() const;
  float maximumDbfs() const;

 private:
  float sortedValue(size_t index) const;

  float secondMaximumDbfs_ = -120.0F;
  float secondMaximaDbfs_[kSecondCount] = {};
  uint32_t secondStartMs_ = 0;
  size_t completedSecondCount_ = 0;
  size_t frameCount_ = 0;
  char target_ = '\0';
  bool active_ = false;
  bool complete_ = false;
};
