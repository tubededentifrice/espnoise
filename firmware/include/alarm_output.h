#pragma once

#include <Arduino.h>

namespace alarm_output {

void begin();
void update(uint32_t now, bool alarmActive, bool sampleActive, bool muted,
            float highRatio);
void off();
void showMicrophoneError(bool on);

}  // namespace alarm_output
