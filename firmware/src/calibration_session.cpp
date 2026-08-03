#include "calibration_session.h"

#include <algorithm>

void CalibrationSession::start(char target, uint32_t now) {
  target_ = target;
  secondStartMs_ = now;
  completedSecondCount_ = 0;
  frameCount_ = 0;
  secondMaximumDbfs_ = -120.0F;
  active_ = true;
  complete_ = false;
}

void CalibrationSession::cancel() {
  active_ = false;
  complete_ = false;
  target_ = '\0';
}

void CalibrationSession::addFrame(float dbfs) {
  if (!active_) {
    return;
  }
  ++frameCount_;
  if (dbfs > secondMaximumDbfs_) {
    secondMaximumDbfs_ = dbfs;
  }
}

bool CalibrationSession::update(uint32_t now) {
  if (!active_ || now - secondStartMs_ < 1000UL) {
    return false;
  }

  if (frameCount_ == 0) {
    secondMaximumDbfs_ = -120.0F;
  }
  secondMaximaDbfs_[completedSecondCount_] = secondMaximumDbfs_;
  ++completedSecondCount_;
  frameCount_ = 0;
  secondMaximumDbfs_ = -120.0F;
  secondStartMs_ = now;

  if (completedSecondCount_ == kSecondCount) {
    active_ = false;
    complete_ = true;
  }
  return true;
}

bool CalibrationSession::active() const { return active_; }

bool CalibrationSession::complete() const { return complete_; }

char CalibrationSession::target() const { return target_; }

size_t CalibrationSession::completedSecondCount() const {
  return completedSecondCount_;
}

float CalibrationSession::lastSecondMaximumDbfs() const {
  if (completedSecondCount_ == 0) {
    return -120.0F;
  }
  return secondMaximaDbfs_[completedSecondCount_ - 1];
}

float CalibrationSession::sortedValue(size_t index) const {
  float sorted[kSecondCount];
  std::copy(secondMaximaDbfs_, secondMaximaDbfs_ + kSecondCount, sorted);
  std::sort(sorted, sorted + kSecondCount);
  return sorted[index];
}

float CalibrationSession::minimumDbfs() const { return sortedValue(0); }

float CalibrationSession::medianDbfs() const {
  if (kSecondCount % 2 == 0) {
    return (sortedValue(kSecondCount / 2 - 1) +
            sortedValue(kSecondCount / 2)) /
           2.0F;
  }
  return sortedValue(kSecondCount / 2);
}

float CalibrationSession::maximumDbfs() const {
  return sortedValue(kSecondCount - 1);
}
