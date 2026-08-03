#pragma once

#include <cstdint>

enum class MutePressResult : uint8_t {
  kMuted,
  kMuteExtended,
  kUnmuted,
};

class MuteState {
 public:
  bool isMuted(uint32_t now) const;
  MutePressResult press(uint32_t now, uint32_t durationSeconds);
  bool update(uint32_t now);

 private:
  uint32_t muteUntilMs_ = 0;
  uint32_t lastPressMs_ = 0;
  bool active_ = false;
  bool doublePressArmed_ = false;
};
