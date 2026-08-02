#pragma once

#include <cstddef>

class NoiseDetector {
 public:
  void beginWindow();
  void addFrame(float dbfs);

  float highRatio() const;
  bool alarmRequired() const;
  size_t frameCount() const;
  size_t highFrameCount() const;

 private:
  size_t frameCount_ = 0;
  size_t highFrameCount_ = 0;
};
