#include "mute_state.h"

#include "config.h"

namespace {

bool timeIsBefore(uint32_t now, uint32_t end) {
  return static_cast<int32_t>(now - end) < 0;
}

}  // namespace

bool MuteState::isMuted(uint32_t now) const {
  return active_ && timeIsBefore(now, muteUntilMs_);
}

MutePressResult MuteState::press(uint32_t now, uint32_t durationSeconds) {
  if (isMuted(now) && doublePressArmed_ &&
      now - lastPressMs_ <= config::kMuteDoublePressWindowMs) {
    active_ = false;
    doublePressArmed_ = false;
    return MutePressResult::kUnmuted;
  }

  const bool wasMuted = isMuted(now);
  muteUntilMs_ = now + durationSeconds * 1000UL;
  active_ = true;
  lastPressMs_ = now;
  doublePressArmed_ = true;
  return wasMuted ? MutePressResult::kMuteExtended
                  : MutePressResult::kMuted;
}

bool MuteState::update(uint32_t now) {
  if (!active_ || timeIsBefore(now, muteUntilMs_)) {
    return false;
  }
  active_ = false;
  doublePressArmed_ = false;
  return true;
}
