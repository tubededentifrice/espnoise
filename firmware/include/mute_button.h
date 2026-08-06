#pragma once

#include <Arduino.h>

enum class MuteButtonEvent : uint8_t {
  kNone = 0,
  kShortPress,
  kLongPress,
};

class MuteButton {
 public:
  void begin();
  MuteButtonEvent update(uint32_t now);

 private:
  bool stablePressed_ = false;
  bool lastRawPressed_ = false;
  bool longPressSent_ = false;
  uint32_t lastChangeMs_ = 0;
  uint32_t pressedSinceMs_ = 0;
};
