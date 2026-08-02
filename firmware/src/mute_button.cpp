#include "mute_button.h"

#include "board_profile.h"
#include "config.h"

void MuteButton::begin() {
  pinMode(board_profile::kMuteButtonPin, INPUT_PULLUP);
}

bool MuteButton::pressed(uint32_t now) {
  const bool rawPressed =
      digitalRead(board_profile::kMuteButtonPin) == LOW;
  if (rawPressed != lastRawPressed_) {
    lastRawPressed_ = rawPressed;
    lastChangeMs_ = now;
  }

  if (now - lastChangeMs_ < config::kButtonDebounceMs ||
      rawPressed == stablePressed_) {
    return false;
  }

  stablePressed_ = rawPressed;
  return stablePressed_;
}
