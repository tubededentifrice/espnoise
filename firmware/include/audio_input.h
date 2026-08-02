#pragma once

#include <Arduino.h>

#include <cstddef>
#include <cstdint>

#include "config.h"

class AudioInput {
 public:
  bool start();
  void stop();
  bool readFrame(float& dbfs);
  bool isRunning() const;

 private:
  int32_t audioBlock_[config::kAudioBlockSamples] = {};
  double previousInput_[2] = {0.0, 0.0};
  double previousFiltered_[2] = {0.0, 0.0};
  bool running_ = false;
};
