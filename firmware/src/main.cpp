#include <Arduino.h>
#include <esp_sleep.h>

#include "alarm_output.h"
#include "audio_input.h"
#include "board_profile.h"
#include "config.h"
#include "mute_button.h"
#include "noise_detector.h"

namespace {

AudioInput audioInput;
NoiseDetector noiseDetector;
MuteButton muteButton;

float currentDbfs = -120.0F;
bool sampleActive = false;
bool alarmActive = false;
AlarmLevel currentAlarmLevel = AlarmLevel::kQuiet;
AlarmLevel currentSampleWarningLevel = AlarmLevel::kQuiet;
uint32_t sampleStartMs = 0;
uint32_t currentSampleDurationMs = config::kSampleDurationMs;
bool sampleForAlarmClear = false;
bool sampleForFastRearm = false;
bool fastRearmActive = false;
uint8_t quietSampleCount = 0;
uint32_t nextSampleStartMs = 0;
uint32_t alarmStartMs = 0;
uint32_t alarmPatternStartMs = 0;
uint32_t fastRearmStartMs = 0;
uint32_t sampleWarningUntilMs = 0;
uint32_t muteUntilMs = 0;
uint32_t lastLevelPrintMs = 0;

bool timeIsBefore(uint32_t now, uint32_t end) {
  return static_cast<int32_t>(now - end) < 0;
}

bool timeIsDue(uint32_t now, uint32_t target) {
  return static_cast<int32_t>(now - target) >= 0;
}

bool isMuted(uint32_t now) {
  return muteUntilMs != 0 && timeIsBefore(now, muteUntilMs);
}

bool isSampleWarningActive(uint32_t now) {
  return currentSampleWarningLevel != AlarmLevel::kQuiet &&
         timeIsBefore(now, sampleWarningUntilMs);
}

const char* levelName(AlarmLevel level) {
  if (level == AlarmLevel::kRed) {
    return "red";
  }
  if (level == AlarmLevel::kOrange) {
    return "orange";
  }
  if (level == AlarmLevel::kGreen) {
    return "green";
  }
  return "quiet";
}

void failMicrophone() {
  Serial.println("ERROR: I2S microphone start failed");
  audioInput.stop();
  while (true) {
    alarm_output::showMicrophoneError(true);
    delay(250);
    alarm_output::showMicrophoneError(false);
    delay(250);
  }
}

void beginSample(uint32_t now) {
  (void)now;
  if (!alarmActive) {
    alarm_output::off();
  }
  alarm_output::silenceBuzzer();
  if (!audioInput.start()) {
    failMicrophone();
  }

  noiseDetector.beginSample();
  currentDbfs = -120.0F;
  sampleStartMs = millis();
  sampleForAlarmClear = alarmActive;
  sampleForFastRearm = !sampleForAlarmClear && fastRearmActive;
  currentSampleDurationMs =
      sampleForAlarmClear || sampleForFastRearm
          ? config::kAlarmClearSampleDurationMs
          : config::kSampleDurationMs;
  sampleActive = true;
  if (sampleForAlarmClear) {
    Serial.println("Alarm clear check started");
  } else if (sampleForFastRearm) {
    Serial.println("Fast rearm check started");
  } else {
    Serial.println("Observation started");
  }
}

void startSampleWarning(AlarmLevel level, uint32_t now) {
  if (level == AlarmLevel::kQuiet) {
    return;
  }
  currentSampleWarningLevel = level;
  sampleWarningUntilMs = now + config::kSampleWarningMs;
  alarm_output::showSampleWarning(level);
  Serial.printf("Sample warning: level=%s duration=%lu ms\n", levelName(level),
                static_cast<unsigned long>(config::kSampleWarningMs));
}

void endSample(uint32_t now) {
  audioInput.stop();
  sampleActive = false;

  if (sampleForAlarmClear) {
    const AlarmLevel sampleLevel = noiseDetector.sampleLevel();
    if (sampleLevel == AlarmLevel::kQuiet) {
      if (quietSampleCount < UINT8_MAX) {
        ++quietSampleCount;
      }
    } else {
      quietSampleCount = 0;
      currentAlarmLevel = sampleLevel;
    }

    if (quietSampleCount >= config::kQuietSamplesToClear) {
      alarmActive = false;
      currentAlarmLevel = AlarmLevel::kQuiet;
      alarmStartMs = 0;
      alarmPatternStartMs = 0;
      quietSampleCount = 0;
      fastRearmActive = true;
      fastRearmStartMs = now;
      nextSampleStartMs = now;
    } else {
      alarmPatternStartMs = now;
      nextSampleStartMs = now + config::kAlarmOutputWindowMs +
                          config::kBuzzerSettleMs;
    }

    Serial.printf(
        "Alarm clear check ended: max=%.1f dBFS sample=%s quiet=%u/%u "
        "alarm=%s\n",
        noiseDetector.sampleMaximumDbfs(), levelName(sampleLevel),
        static_cast<unsigned>(quietSampleCount),
        static_cast<unsigned>(config::kQuietSamplesToClear),
        alarmActive ? "on" : "off");
    return;
  }

  if (sampleForFastRearm) {
    const AlarmLevel sampleLevel = noiseDetector.sampleLevel();
    if (sampleLevel != AlarmLevel::kQuiet) {
      fastRearmActive = false;
      fastRearmStartMs = 0;
      alarmActive = true;
      currentAlarmLevel = sampleLevel;
      alarmStartMs = now;
      alarmPatternStartMs = now;
      quietSampleCount = 0;
      nextSampleStartMs = now + config::kAlarmOutputWindowMs +
                          config::kBuzzerSettleMs;
    } else if (now - fastRearmStartMs >= config::kFastRearmWindowMs) {
      fastRearmActive = false;
      fastRearmStartMs = 0;
      if (config::kResetHistoryAfterAlarmClear) {
        noiseDetector.resetHistory();
      }
      nextSampleStartMs = now + config::kSamplePeriodMs;
    } else {
      nextSampleStartMs = now + config::kFastRearmSampleGapMs;
    }

    Serial.printf(
        "Fast rearm check ended: max=%.1f dBFS sample=%s rearm=%s "
        "alarm=%s\n",
        noiseDetector.sampleMaximumDbfs(), levelName(sampleLevel),
        fastRearmActive ? "on" : "off", alarmActive ? "on" : "off");
    return;
  }

  const AlarmLevel sampleLevel = noiseDetector.sampleLevel();
  noiseDetector.commitSample();
  const AlarmLevel historyLevel = noiseDetector.historyAlarmLevel();
  if (historyLevel != AlarmLevel::kQuiet) {
    alarmActive = true;
    currentAlarmLevel = historyLevel;
    alarmStartMs = now;
    alarmPatternStartMs = now;
    quietSampleCount = 0;
    nextSampleStartMs = now + config::kAlarmOutputWindowMs +
                        config::kBuzzerSettleMs;
  } else {
    alarmActive = false;
    currentAlarmLevel = AlarmLevel::kQuiet;
    startSampleWarning(sampleLevel, now);
    nextSampleStartMs = sampleStartMs + config::kSamplePeriodMs;
    if (timeIsDue(now, nextSampleStartMs)) {
      nextSampleStartMs = now;
    }
  }

  Serial.printf(
      "Observation ended: max=%.1f dBFS history=%u/%u green=%.1f%% "
      "orange=%.1f%% red=%.1f%% alarm=%s level=%s\n",
      noiseDetector.sampleMaximumDbfs(),
      static_cast<unsigned>(noiseDetector.historyCount()),
      static_cast<unsigned>(config::kHistorySampleCount),
      noiseDetector.greenSampleRatio() * 100.0F,
      noiseDetector.orangeSampleRatio() * 100.0F,
      noiseDetector.redSampleRatio() * 100.0F, alarmActive ? "on" : "off",
      levelName(currentAlarmLevel));
}

void updateMute(uint32_t now) {
  if (muteButton.pressed(now)) {
    muteUntilMs = now + config::kMute30Ms;
    alarmActive = false;
    currentAlarmLevel = AlarmLevel::kQuiet;
    alarmStartMs = 0;
    alarmPatternStartMs = 0;
    fastRearmActive = false;
    fastRearmStartMs = 0;
    currentSampleWarningLevel = AlarmLevel::kQuiet;
    sampleWarningUntilMs = 0;
    quietSampleCount = 0;
    noiseDetector.resetHistory();
    if (sampleActive) {
      audioInput.stop();
      sampleActive = false;
    }
    alarm_output::off();
    nextSampleStartMs = muteUntilMs;
    Serial.println("Muted for 30 minutes");
  }

  if (muteUntilMs != 0 && !timeIsBefore(now, muteUntilMs)) {
    muteUntilMs = 0;
    nextSampleStartMs = now;
    Serial.println("Mute ended");
  }
}

void sleepUntilEvent(uint32_t now) {
  if (sampleActive || (alarmActive && !isMuted(now)) ||
      isSampleWarningActive(now)) {
    return;
  }
  if (digitalRead(board_profile::kMuteButtonPin) == LOW) {
    return;
  }

  uint32_t wakeAtMs = nextSampleStartMs;
  if (isMuted(now) && timeIsBefore(muteUntilMs, wakeAtMs)) {
    wakeAtMs = muteUntilMs;
  }
  if (timeIsDue(now, wakeAtMs)) {
    return;
  }

  const uint32_t sleepMs = wakeAtMs - now;
  alarm_output::off();
  esp_sleep_enable_timer_wakeup(static_cast<uint64_t>(sleepMs) * 1000ULL);
  esp_sleep_enable_ext0_wakeup(board_profile::kMuteButtonPin, 0);
  esp_light_sleep_start();
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(300);

  if (config::kSampleDurationMs == 0 ||
      config::kSampleDurationMs > config::kSamplePeriodMs ||
      config::kTriggerSampleRatio < 0.0F ||
      config::kTriggerSampleRatio > 1.0F ||
      config::kHistorySampleCount == 0 ||
      config::kMinimumHistorySamples == 0 ||
      config::kMinimumHistorySamples > config::kHistorySampleCount ||
      config::kAlarmClearSampleDurationMs == 0 ||
      config::kSampleWarningMs == 0 ||
      config::kFastRearmWindowMs < config::kAlarmClearSampleDurationMs ||
      config::kQuietSamplesToClear == 0 ||
      (config::kQuietSamplesToClear + 1UL) *
                      (config::kAlarmClearSampleDurationMs +
                       config::kMicrophoneWarmupMs) +
                  config::kQuietSamplesToClear *
                      (config::kAlarmOutputWindowMs +
                       config::kBuzzerSettleMs) >
          5000UL ||
      config::kGreenThresholdDbfs >= config::kOrangeThresholdDbfs ||
      config::kOrangeThresholdDbfs >= config::kRedThresholdDbfs ||
      config::kEscalateToOrangeMs > config::kEscalateToRedMs ||
      config::buzzerPatternDurationMs(config::kOrangeStyle) >
          config::kAlarmOutputWindowMs ||
      config::buzzerPatternDurationMs(config::kRedStyle) >
          config::kAlarmOutputWindowMs) {
    Serial.println("ERROR: Invalid sample settings");
    while (true) {
      delay(1000);
    }
  }

  muteButton.begin();
  alarm_output::begin();
  nextSampleStartMs = millis();
  Serial.println("ESPNoise started");
}

void loop() {
  uint32_t now = millis();
  updateMute(now);

  if (!isMuted(now) && !sampleActive && timeIsDue(now, nextSampleStartMs)) {
    beginSample(now);
  }

  if (sampleActive && audioInput.readFrame(currentDbfs)) {
    noiseDetector.addFrame(currentDbfs);
  }

  now = millis();
  if (sampleActive && now - sampleStartMs >= currentSampleDurationMs) {
    endSample(now);
  }

  const uint32_t alarmAgeMs = alarmActive ? now - alarmStartMs : 0;
  const uint32_t patternAgeMs = alarmActive ? now - alarmPatternStartMs : 0;
  if (isSampleWarningActive(now) && !isMuted(now)) {
    alarm_output::silenceBuzzer();
  } else {
    currentSampleWarningLevel = AlarmLevel::kQuiet;
    sampleWarningUntilMs = 0;
    alarm_output::update(now, alarmActive, sampleActive, isMuted(now),
                         currentAlarmLevel, alarmAgeMs, patternAgeMs);
  }

  if (sampleActive && now - lastLevelPrintMs >= 1000) {
    lastLevelPrintMs = now;
    Serial.printf("level=%.1f dBFS max=%.1f dBFS frames=%u mute=%s\n",
                  currentDbfs, noiseDetector.sampleMaximumDbfs(),
                  static_cast<unsigned>(noiseDetector.frameCount()),
                  isMuted(now) ? "on" : "off");
  }

  sleepUntilEvent(now);
}
