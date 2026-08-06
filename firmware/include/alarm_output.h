#pragma once

#include <Arduino.h>

#include "alarm_level.h"
#include "runtime_settings.h"

namespace alarm_output {

void begin();
void setSettings(const RuntimeSettings& settings);
void update(uint32_t now, bool alarmActive, bool sampleActive, bool muted,
            AlarmLevel alarmLevel, uint32_t alarmAgeMs,
            uint32_t patternAgeMs);
void silenceBuzzer();
void off();
void startBluetoothTransition(uint32_t now, bool enabled);
void showMicrophoneError(bool on);
void showSampleWarning(AlarmLevel level);
void showCalibrationTarget(AlarmLevel level);

}  // namespace alarm_output
