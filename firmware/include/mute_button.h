#pragma once

#include <Arduino.h>

class MuteButton {
 public:
  void begin();
  bool pressed(uint32_t now);

 private:
  bool stablePressed_ = false;
  bool lastRawPressed_ = false;
  uint32_t lastChangeMs_ = 0;
};
