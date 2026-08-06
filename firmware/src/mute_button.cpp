#include "mute_button.h"

#include "board_profile.h"
#include "config.h"

void MuteButton::begin() {
  pinMode(board_profile::kMuteButtonPin, INPUT_PULLUP);
}

MuteButtonEvent MuteButton::update(uint32_t now) {
  const bool rawPressed =
      digitalRead(board_profile::kMuteButtonPin) == LOW;
  if (rawPressed != lastRawPressed_) {
    lastRawPressed_ = rawPressed;
    lastChangeMs_ = now;
  }

  if (now - lastChangeMs_ < config::kButtonDebounceMs ||
      rawPressed == stablePressed_) {
    if (stablePressed_ && !longPressSent_ &&
        now - pressedSinceMs_ >= config::kBluetoothButtonHoldMs) {
      longPressSent_ = true;
      return MuteButtonEvent::kLongPress;
    }
    return MuteButtonEvent::kNone;
  }

  stablePressed_ = rawPressed;
  if (stablePressed_) {
    pressedSinceMs_ = now;
    longPressSent_ = false;
    return MuteButtonEvent::kNone;
  }
  return longPressSent_ ? MuteButtonEvent::kNone
                        : MuteButtonEvent::kShortPress;
}
