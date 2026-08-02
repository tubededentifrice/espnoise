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
float lastHighRatio = 0.0F;
bool sampleActive = false;
bool alarmActive = false;
uint32_t sampleStartMs = 0;
uint32_t nextSampleStartMs = 0;
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
  alarm_output::off();
  if (!audioInput.start()) {
    failMicrophone();
  }

  noiseDetector.beginWindow();
  currentDbfs = -120.0F;
  sampleStartMs = now;
  sampleActive = true;
  Serial.println("Sample started");
}

void endSample(uint32_t now) {
  audioInput.stop();
  sampleActive = false;
  lastHighRatio = noiseDetector.highRatio();
  alarmActive = noiseDetector.alarmRequired();

  Serial.printf("Sample ended: high=%.1f%% alarm=%s\n",
                lastHighRatio * 100.0F, alarmActive ? "on" : "off");

  nextSampleStartMs = sampleStartMs + config::kSamplePeriodMs;
  if (timeIsDue(now, nextSampleStartMs)) {
    nextSampleStartMs = now;
  }
}

void updateMute(uint32_t now) {
  if (muteButton.pressed(now)) {
    muteUntilMs = now + config::kMute30Ms;
    alarmActive = false;
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
  if (sampleActive || (alarmActive && !isMuted(now))) {
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
      config::kHighFrameRatio < 0.0F || config::kHighFrameRatio > 1.0F) {
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
  if (sampleActive && now - sampleStartMs >= config::kSampleDurationMs) {
    endSample(now);
  }

  alarm_output::update(now, alarmActive, sampleActive, isMuted(now),
                       lastHighRatio);

  if (sampleActive && now - lastLevelPrintMs >= 1000) {
    lastLevelPrintMs = now;
    Serial.printf("level=%.1f dBFS high=%u/%u mute=%s\n", currentDbfs,
                  static_cast<unsigned>(noiseDetector.highFrameCount()),
                  static_cast<unsigned>(noiseDetector.frameCount()),
                  isMuted(now) ? "on" : "off");
  }

  sleepUntilEvent(now);
}
