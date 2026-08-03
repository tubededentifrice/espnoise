#include <Arduino.h>
#include <WiFi.h>
#include <esp_bt.h>

#include <algorithm>
#include <cmath>

#include "alarm_output.h"
#include "audio_input.h"
#include "ble_service.h"
#include "board_profile.h"
#include "config_packet.h"
#include "config.h"
#include "device_name.h"
#include "mute_button.h"
#include "noise_detector.h"
#include "settings_storage.h"

namespace {

AudioInput audioInput;
NoiseDetector noiseDetector;
MuteButton muteButton;
RuntimeSettings runtimeSettings;
config_packet::Bytes appliedPacket{};
device_name::Value appliedDeviceName;
uint32_t appliedRevision = 0;

float currentDbfs = -120.0F;
bool sampleActive = false;
bool alarmActive = false;
AlarmLevel currentAlarmLevel = AlarmLevel::kQuiet;
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
uint32_t muteUntilMs = 0;
uint32_t lastLevelPrintMs = 0;
uint8_t settingsErrorCode = 0;
uint16_t measurementSequence = 0;

device_name::Value defaultDeviceName() {
  device_name::Value name;
  char text[19] = {};
  const uint64_t chipId = ESP.getEfuseMac();
  const int length = snprintf(text, sizeof(text), "Device %04X",
                              static_cast<unsigned>(chipId & 0xFFFFU));
  name.length = static_cast<uint8_t>(std::max(0, length));
  std::copy(text, text + name.length, name.bytes.begin());
  return name;
}

bool timeIsBefore(uint32_t now, uint32_t end) {
  return static_cast<int32_t>(now - end) < 0;
}

bool timeIsDue(uint32_t now, uint32_t target) {
  return static_cast<int32_t>(now - target) >= 0;
}

bool isMuted(uint32_t now) {
  return muteUntilMs != 0 && timeIsBefore(now, muteUntilMs);
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
          : runtimeSettings.sampleDurationMs;
  sampleActive = true;
  if (sampleForAlarmClear) {
    Serial.println("Alarm clear check started");
  } else if (sampleForFastRearm) {
    Serial.println("Fast rearm check started");
  } else {
    Serial.println("Observation started");
  }
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
      nextSampleStartMs = now + runtimeSettings.samplePeriodMs;
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
    // Do not show a warning for one observation. Only the complete decision
    // history can start an alarm.
    nextSampleStartMs = sampleStartMs + runtimeSettings.samplePeriodMs;
    if (timeIsDue(now, nextSampleStartMs)) {
      nextSampleStartMs = now;
    }
  }

  Serial.printf(
      "Observation ended: max=%.1f dBFS history=%u/%u green=%.1f%% "
      "orange=%.1f%% red=%.1f%% alarm=%s level=%s\n",
      noiseDetector.sampleMaximumDbfs(),
      static_cast<unsigned>(noiseDetector.historyCount()),
      static_cast<unsigned>(runtimeSettings.historySampleCount()),
      noiseDetector.greenSampleRatio() * 100.0F,
      noiseDetector.orangeSampleRatio() * 100.0F,
      noiseDetector.redSampleRatio() * 100.0F, alarmActive ? "on" : "off",
      levelName(currentAlarmLevel));
}

void updateMute(uint32_t now) {
  if (muteButton.pressed(now)) {
    muteUntilMs = now + runtimeSettings.muteDurationSeconds * 1000UL;
    alarmActive = false;
    currentAlarmLevel = AlarmLevel::kQuiet;
    alarmStartMs = 0;
    alarmPatternStartMs = 0;
    fastRearmActive = false;
    fastRearmStartMs = 0;
    quietSampleCount = 0;
    noiseDetector.resetHistory();
    if (sampleActive) {
      audioInput.stop();
      sampleActive = false;
    }
    alarm_output::off();
    nextSampleStartMs = muteUntilMs;
    Serial.printf("Muted for %lu seconds\n",
                  static_cast<unsigned long>(
                      runtimeSettings.muteDurationSeconds));
  }

  if (muteUntilMs != 0 && !timeIsBefore(now, muteUntilMs)) {
    muteUntilMs = 0;
    nextSampleStartMs = now;
    Serial.println("Mute ended");
  }
}

ble_service::Status makeBleStatus(uint32_t now) {
  ble_service::Status status;
  status.alarmState = static_cast<uint8_t>(currentAlarmLevel);
  status.muted = isMuted(now);
  status.sampling = sampleActive;
  status.alarmActive = alarmActive;
  status.errorCode = settingsErrorCode;
  status.appliedRevision = appliedRevision;
  status.fingerprint = config_packet::fingerprint(appliedPacket);
  status.measurementValid = noiseDetector.frameCount() > 0;
  const float maximumDbfs = std::max(
      -120.0F, std::min(0.0F, noiseDetector.sampleMaximumDbfs()));
  status.observationMaximumDbfsX10 =
      static_cast<int16_t>(std::lround(maximumDbfs * 10.0F));
  status.measurementSequence = measurementSequence;
  status.historyCount = static_cast<uint8_t>(noiseDetector.historyCount());
  status.greenSampleCount =
      static_cast<uint8_t>(noiseDetector.greenSampleCount());
  status.orangeSampleCount =
      static_cast<uint8_t>(noiseDetector.orangeSampleCount());
  status.redSampleCount =
      static_cast<uint8_t>(noiseDetector.redSampleCount());
  return status;
}

void clearRuntimeState(uint32_t now) {
  alarmActive = false;
  currentAlarmLevel = AlarmLevel::kQuiet;
  alarmStartMs = 0;
  alarmPatternStartMs = 0;
  fastRearmActive = false;
  fastRearmStartMs = 0;
  quietSampleCount = 0;
  noiseDetector.resetHistory();
  alarm_output::off();
  nextSampleStartMs = isMuted(now) ? muteUntilMs : now;
}

void applyPendingSettings(uint32_t now) {
  if (sampleActive) {
    return;
  }

  config_packet::Bytes candidate{};
  RuntimeSettings candidateSettings;
  uint32_t candidateRevision = 0;
  if (!ble_service::takePending(candidate, candidateSettings,
                                candidateRevision)) {
    return;
  }

  const bool packetChanged = candidate != appliedPacket;
  if (packetChanged && !settings_storage::save(candidate)) {
    Serial.println("ERROR: Settings save failed; update rejected");
    settingsErrorCode = 1;
    ble_service::Status status = makeBleStatus(now);
    ble_service::acknowledge(appliedPacket, status);
    return;
  }

  settingsErrorCode = 0;
  runtimeSettings = candidateSettings;
  appliedPacket = candidate;
  appliedRevision = candidateRevision;
  noiseDetector.setSettings(runtimeSettings);
  alarm_output::setSettings(runtimeSettings);
  clearRuntimeState(now);
  ble_service::acknowledge(appliedPacket, makeBleStatus(now));
  Serial.printf("Settings applied: revision=%lu fingerprint=%08lX\n",
                static_cast<unsigned long>(appliedRevision),
                static_cast<unsigned long>(
                    config_packet::fingerprint(appliedPacket)));
}

void applyPendingName() {
  if (sampleActive) {
    return;
  }
  device_name::Value candidate;
  if (!ble_service::takePendingName(candidate)) {
    return;
  }
  if (candidate != appliedDeviceName &&
      !settings_storage::saveName(candidate)) {
    Serial.println("ERROR: Device name save failed; update rejected");
    ble_service::acknowledgeName(appliedDeviceName);
    return;
  }
  appliedDeviceName = candidate;
  ble_service::acknowledgeName(appliedDeviceName);
  Serial.println("Device name applied");
}

void answerNameReadRequest() {
  if (ble_service::takeNameReadRequest()) {
    ble_service::notifyName(appliedDeviceName);
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(300);

  WiFi.mode(WIFI_OFF);
  esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT);

  appliedPacket = config_packet::encode(runtimeSettings, 0);
  appliedDeviceName = defaultDeviceName();
  if (!settings_storage::begin()) {
    Serial.println("ERROR: Settings storage start failed; defaults active");
  } else {
    if (!settings_storage::load(appliedPacket)) {
      appliedPacket = config_packet::encode(runtimeSettings, 0);
      Serial.println("Saved settings are absent or invalid; defaults active");
    }
    if (!settings_storage::loadName(appliedDeviceName)) {
      appliedDeviceName = defaultDeviceName();
    }
  }
  if (config_packet::decode(appliedPacket.data(), appliedPacket.size(),
                            runtimeSettings, appliedRevision) !=
      config_packet::ValidationResult::kValid) {
    runtimeSettings = RuntimeSettings{};
    appliedRevision = 0;
    appliedPacket = config_packet::encode(runtimeSettings, appliedRevision);
  }

  if (config::kSampleDurationMs == 0 ||
      config::kSampleDurationMs > config::kSamplePeriodMs ||
      config::kTriggerSampleRatio < 0.0F ||
      config::kTriggerSampleRatio > 1.0F ||
      config::kHistorySampleCount == 0 ||
      config::kMinimumHistorySamples == 0 ||
      config::kMinimumHistorySamples > config::kHistorySampleCount ||
      config::kAlarmClearSampleDurationMs == 0 ||
      config::kFastRearmWindowMs < config::kAlarmClearSampleDurationMs ||
      config::kQuietSamplesToClear == 0 ||
      (config::kQuietSamplesToClear + 1UL) *
                      (config::kAlarmClearSampleDurationMs +
                       config::kMicrophoneWarmupMs) +
                  config::kQuietSamplesToClear *
                      (config::kAlarmOutputWindowMs +
                       config::kBuzzerSettleMs) >
          5000UL ||
      config::kGreenThresholdDbfsX10 >=
          config::kOrangeThresholdDbfsX10 ||
      config::kOrangeThresholdDbfsX10 >= config::kRedThresholdDbfsX10 ||
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
  noiseDetector.setSettings(runtimeSettings);
  alarm_output::setSettings(runtimeSettings);
  alarm_output::begin();
  ble_service::begin(appliedPacket, appliedDeviceName);
  nextSampleStartMs = millis();
  Serial.println("ESPNoise started");
}

void loop() {
  uint32_t now = millis();
  ble_service::update(now);
  updateMute(now);
  answerNameReadRequest();
  applyPendingName();
  applyPendingSettings(now);

  if (!isMuted(now) && !sampleActive && timeIsDue(now, nextSampleStartMs)) {
    beginSample(now);
  }

  if (sampleActive && audioInput.readFrame(currentDbfs)) {
    noiseDetector.addFrame(currentDbfs);
    ++measurementSequence;
  }

  now = millis();
  if (sampleActive && now - sampleStartMs >= currentSampleDurationMs) {
    endSample(now);
  }

  const uint32_t alarmAgeMs = alarmActive ? now - alarmStartMs : 0;
  const uint32_t patternAgeMs = alarmActive ? now - alarmPatternStartMs : 0;
  alarm_output::update(now, alarmActive, sampleActive, isMuted(now),
                       currentAlarmLevel, alarmAgeMs, patternAgeMs);

  if (sampleActive && now - lastLevelPrintMs >= 1000) {
    lastLevelPrintMs = now;
    Serial.printf("level=%.1f dBFS max=%.1f dBFS frames=%u mute=%s\n",
                  currentDbfs, noiseDetector.sampleMaximumDbfs(),
                  static_cast<unsigned>(noiseDetector.frameCount()),
                  isMuted(now) ? "on" : "off");
  }

  ble_service::setStatus(makeBleStatus(now));

  // Let the BLE and Arduino tasks run. NimBLE manages its radio sleep.
  delay(1);
}
