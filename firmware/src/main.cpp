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
#include "mute_state.h"
#include "noise_detector.h"
#include "noise_analytics.h"
#include "settings_storage.h"

namespace {

AudioInput audioInput;
NoiseDetector noiseDetector;
noise_analytics::History analyticsHistory;
MuteButton muteButton;
MuteState muteState;
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
uint32_t nextSampleStartMs = 0;
uint32_t alarmStartMs = 0;
uint32_t alarmPatternStartMs = 0;
uint32_t lastLevelPrintMs = 0;
uint8_t settingsErrorCode = 0;
uint16_t measurementSequence = 0;
uint32_t lastAnalyticsSecondMs = 0;
uint32_t lastAnalyticsNotifyMs = 0;
uint32_t analyticsAfterSequence = 0;
size_t analyticsSyncCursor = 0;
bool analyticsCurrentIsPending = false;
bool analyticsSyncIsActive = false;

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

bool timeIsDue(uint32_t now, uint32_t target) {
  return static_cast<int32_t>(now - target) >= 0;
}

bool isMuted(uint32_t now) {
  return muteState.isMuted(now);
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

void printActiveSettings() {
  Serial.printf(
      "Settings active: green=%.1f orange=%.1f red=%.1f dBFS "
      "K=%lu ms N=%lu ms window=%lu ms X=%u%% required=%u/%u\n",
      runtimeSettings.greenThresholdDbfsX10 / 10.0F,
      runtimeSettings.orangeThresholdDbfsX10 / 10.0F,
      runtimeSettings.redThresholdDbfsX10 / 10.0F,
      static_cast<unsigned long>(runtimeSettings.sampleDurationMs),
      static_cast<unsigned long>(runtimeSettings.samplePeriodMs),
      static_cast<unsigned long>(runtimeSettings.decisionWindowMs),
      static_cast<unsigned>(runtimeSettings.triggerSamplePercent),
      static_cast<unsigned>(runtimeSettings.requiredTriggerSampleCount()),
      static_cast<unsigned>(runtimeSettings.historySampleCount()));
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
  currentSampleDurationMs =
      alarmActive ? config::kAlarmActiveSampleDurationMs
                  : runtimeSettings.sampleDurationMs;
  sampleActive = true;
  Serial.println(alarmActive ? "Alarm observation started"
                             : "Observation started");
}

void endSample(uint32_t now) {
  audioInput.stop();
  sampleActive = false;

  const bool alarmWasActive = alarmActive;
  noiseDetector.commitSample();
  const AlarmLevel historyLevel = noiseDetector.historyAlarmLevel();
  if (historyLevel != AlarmLevel::kQuiet && !isMuted(now)) {
    alarmActive = true;
    currentAlarmLevel = historyLevel;
    if (!alarmWasActive) {
      alarmStartMs = now;
    }
    alarmPatternStartMs = now;
    nextSampleStartMs = now + config::kAlarmOutputWindowMs +
                        config::kBuzzerSettleMs;
  } else {
    alarmActive = false;
    currentAlarmLevel = isMuted(now) ? historyLevel : AlarmLevel::kQuiet;
    alarmStartMs = 0;
    alarmPatternStartMs = 0;
    nextSampleStartMs = sampleStartMs + runtimeSettings.samplePeriodMs;
    if (timeIsDue(now, nextSampleStartMs)) {
      nextSampleStartMs = now;
    }
  }

  Serial.printf(
      "%s ended: max=%.1f dBFS history=%u/%u green=%.1f%% "
      "orange=%.1f%% red=%.1f%% alarm=%s level=%s\n",
      alarmWasActive ? "Alarm observation" : "Observation",
      noiseDetector.sampleMaximumDbfs(),
      static_cast<unsigned>(noiseDetector.historyCount()),
      static_cast<unsigned>(runtimeSettings.historySampleCount()),
      noiseDetector.greenSampleRatio() * 100.0F,
      noiseDetector.orangeSampleRatio() * 100.0F,
      noiseDetector.redSampleRatio() * 100.0F, alarmActive ? "on" : "off",
      levelName(currentAlarmLevel));
}

void resumeAlarmFromHistory(uint32_t now) {
  const AlarmLevel historyLevel = noiseDetector.historyAlarmLevel();
  currentAlarmLevel = historyLevel;
  if (historyLevel == AlarmLevel::kQuiet) {
    alarmActive = false;
    alarmStartMs = 0;
    alarmPatternStartMs = 0;
    return;
  }
  alarmActive = true;
  alarmStartMs = now;
  alarmPatternStartMs = now;
  nextSampleStartMs = now + config::kAlarmOutputWindowMs +
                      config::kBuzzerSettleMs;
}

void updateMute(uint32_t now) {
  if (muteButton.pressed(now)) {
    const bool alarmWasActive = alarmActive;
    const MutePressResult result =
        muteState.press(now, runtimeSettings.muteDurationSeconds);
    if (result == MutePressResult::kUnmuted) {
      resumeAlarmFromHistory(now);
      Serial.println("Mute ended by double press");
      return;
    }

    alarmActive = false;
    currentAlarmLevel = AlarmLevel::kQuiet;
    alarmStartMs = 0;
    alarmPatternStartMs = 0;
    if (sampleActive) {
      currentSampleDurationMs = runtimeSettings.sampleDurationMs;
    } else if (alarmWasActive) {
      nextSampleStartMs = now;
    }
    alarm_output::off();
    Serial.printf(
        result == MutePressResult::kMuteExtended
            ? "Mute restarted for %lu seconds\n"
            : "Muted for %lu seconds\n",
        static_cast<unsigned long>(runtimeSettings.muteDurationSeconds));
  }

  if (muteState.update(now)) {
    resumeAlarmFromHistory(now);
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
  noiseDetector.resetHistory();
  alarm_output::off();
  nextSampleStartMs = now;
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
  printActiveSettings();
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

void updateAnalytics(uint32_t now) {
  while (now - lastAnalyticsSecondMs >= 1000) {
    lastAnalyticsSecondMs += 1000;
    const float maximumDbfs = std::max(
        -120.0F, std::min(0.0F, noiseDetector.sampleMaximumDbfs()));
    analyticsHistory.addSecond(
        currentAlarmLevel,
        static_cast<int16_t>(std::lround(maximumDbfs * 10.0F)),
        noiseDetector.frameCount() > 0);
  }

  if (!sampleActive && analyticsHistory.persistenceIsDue()) {
    if (settings_storage::saveAnalytics(analyticsHistory)) {
      analyticsHistory.markPersisted();
      Serial.println("Analytics history saved");
    } else {
      Serial.println("ERROR: Analytics history save failed");
    }
  }
  if (analyticsHistory.sequencePersistenceIsDue()) {
    if (settings_storage::saveAnalyticsSequence(
            analyticsHistory.currentSequence())) {
      analyticsHistory.markSequencePersisted();
    } else {
      Serial.println("ERROR: Analytics sequence save failed");
    }
  }
}

void updateAnalyticsSync(uint32_t now) {
  uint32_t requestedAfterSequence = 0;
  if (ble_service::takeAnalyticsRequest(requestedAfterSequence)) {
    analyticsAfterSequence = requestedAfterSequence;
    analyticsSyncCursor = 0;
    analyticsCurrentIsPending = true;
    analyticsSyncIsActive = true;
  }
  if (!analyticsSyncIsActive || now - lastAnalyticsNotifyMs < 60) {
    return;
  }

  if (analyticsCurrentIsPending) {
    if (ble_service::notifyAnalytics(analyticsHistory.currentPacket())) {
      analyticsCurrentIsPending = false;
      lastAnalyticsNotifyMs = now;
    }
    return;
  }

  noise_analytics::Bucket bucket;
  while (analyticsSyncCursor < analyticsHistory.recordCount()) {
    if (!analyticsHistory.recordAt(analyticsSyncCursor++, bucket) ||
        !noise_analytics::History::sequenceIsAfter(
            bucket.sequence, analyticsAfterSequence)) {
      continue;
    }
    if (ble_service::notifyAnalytics(analyticsHistory.packetFor(bucket))) {
      lastAnalyticsNotifyMs = now;
    } else {
      --analyticsSyncCursor;
    }
    return;
  }
  analyticsSyncIsActive = false;
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
    if (!settings_storage::loadAnalytics(analyticsHistory)) {
      Serial.println("Saved analytics history is absent or invalid");
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
      config::kAlarmActiveSampleDurationMs == 0 ||
      config::kGreenThresholdDbfsX10 >=
          config::kOrangeThresholdDbfsX10 ||
      config::kOrangeThresholdDbfsX10 >= config::kRedThresholdDbfsX10 ||
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
  lastAnalyticsSecondMs = nextSampleStartMs;
  printActiveSettings();
  Serial.println("ESPNoise started");
}

void loop() {
  uint32_t now = millis();
  ble_service::update(now);
  updateMute(now);
  answerNameReadRequest();
  applyPendingName();
  applyPendingSettings(now);

  if (!sampleActive && timeIsDue(now, nextSampleStartMs)) {
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
  updateAnalytics(now);
  updateAnalyticsSync(now);

  // Let the BLE and Arduino tasks run. NimBLE manages its radio sleep.
  delay(1);
}
