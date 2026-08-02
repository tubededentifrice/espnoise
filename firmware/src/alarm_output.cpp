#include "alarm_output.h"

#include <Adafruit_NeoPixel.h>

#include <cstdint>

#include "board_profile.h"
#include "config.h"

#ifndef ESPNOISE_LED_STARTUP_TEST
#define ESPNOISE_LED_STARTUP_TEST 0
#endif

#ifndef ESPNOISE_BUZZER_STARTUP_TEST
#define ESPNOISE_BUZZER_STARTUP_TEST 0
#endif

#ifndef ESPNOISE_BUZZER_MELODY_TEST
#define ESPNOISE_BUZZER_MELODY_TEST 0
#endif

namespace alarm_output {
namespace {

constexpr uint8_t kBuzzerPwmChannel = 0;

Adafruit_NeoPixel pixels(config::kLedCount, board_profile::kLedDataPin,
                         NEO_GRBW + NEO_KHZ800);

bool peripheralPowerOn = false;
uint32_t displayedColor = UINT32_MAX;

void setBuzzer(bool on) {
  ledcWrite(kBuzzerPwmChannel, on ? config::kBuzzerDuty : 0);
}

void playTestMelody() {
  constexpr uint16_t frequencies[] = {523, 659, 784, 1047, 784, 1047};
  constexpr uint16_t durationsMs[] = {160, 160, 160, 320, 160, 420};

  for (size_t index = 0;
       index < sizeof(frequencies) / sizeof(frequencies[0]); ++index) {
    ledcSetup(kBuzzerPwmChannel, frequencies[index], 8);
    setBuzzer(true);
    delay(durationsMs[index]);
    setBuzzer(false);
    delay(60);
  }

  ledcSetup(kBuzzerPwmChannel, config::kBuzzerFrequencyHz, 8);
}

void setAllPixels(uint32_t color) {
  for (uint8_t index = 0; index < config::kLedCount; ++index) {
    pixels.setPixelColor(index, color);
  }
  pixels.show();
  displayedColor = color;
}

void enablePeripheralPower() {
  if (!board_profile::kHasSwitchedPeripheralPower) {
    peripheralPowerOn = true;
    return;
  }
  if (peripheralPowerOn) {
    return;
  }

  digitalWrite(board_profile::kPeripheralPowerEnablePin, HIGH);
  delay(config::kPeripheralPowerWarmupMs);
  peripheralPowerOn = true;
  displayedColor = UINT32_MAX;
}

uint32_t colorForRatio(float highRatio) {
  if (highRatio > config::kHighFrameRatio + config::kRedRatioMargin) {
    return pixels.Color(255, 0, 0, 24);
  }
  if (highRatio > config::kHighFrameRatio + config::kOrangeRatioMargin) {
    return pixels.Color(255, 50, 0, 0);
  }
  return pixels.Color(180, 120, 0, 0);
}

}  // namespace

void begin() {
  ledcSetup(kBuzzerPwmChannel, config::kBuzzerFrequencyHz, 8);
  ledcAttachPin(board_profile::kBuzzerPin, kBuzzerPwmChannel);
  setBuzzer(false);

  if (board_profile::kHasSwitchedPeripheralPower) {
    pinMode(board_profile::kPeripheralPowerEnablePin, OUTPUT);
    digitalWrite(board_profile::kPeripheralPowerEnablePin, LOW);
  }

  pixels.begin();
  pixels.setBrightness(config::kLedBrightness);
  enablePeripheralPower();
  setAllPixels(0);

  if (ESPNOISE_LED_STARTUP_TEST != 0) {
    setAllPixels(pixels.Color(255, 0, 0, 0));
    delay(1000);
    setAllPixels(pixels.Color(0, 255, 0, 0));
    delay(1000);
    setAllPixels(pixels.Color(0, 0, 255, 0));
    delay(1000);
    setAllPixels(pixels.Color(0, 0, 0, 255));
    delay(1000);
    setAllPixels(0);
  }

  if (ESPNOISE_BUZZER_STARTUP_TEST != 0) {
    setBuzzer(true);
    delay(1000);
    setBuzzer(false);
  }

  if (ESPNOISE_BUZZER_MELODY_TEST != 0) {
    playTestMelody();
  }

  off();
}

void off() {
  setBuzzer(false);

  if (!peripheralPowerOn) {
    return;
  }
  if (displayedColor != 0) {
    setAllPixels(0);
  }

  if (board_profile::kHasSwitchedPeripheralPower) {
    delayMicroseconds(100);
    digitalWrite(board_profile::kPeripheralPowerEnablePin, LOW);
    digitalWrite(board_profile::kLedDataPin, LOW);
    peripheralPowerOn = false;
  }
}

void update(uint32_t now, bool alarmActive, bool sampleActive, bool muted,
            float highRatio) {
  // Keep the local outputs off during a sample. This prevents feedback into
  // the microphone result.
  if (muted || sampleActive || !alarmActive) {
    off();
    return;
  }

  enablePeripheralPower();
  const uint32_t phase = now % (2 * config::kAlarmHalfPeriodMs);
  const bool lightOn = phase < config::kAlarmHalfPeriodMs;
  const uint32_t wantedColor = lightOn ? colorForRatio(highRatio) : 0;
  if (wantedColor != displayedColor) {
    setAllPixels(wantedColor);
  }

  const bool buzzerOn = config::kBuzzerEnabled && phase < config::kBuzzerOnMs;
  setBuzzer(buzzerOn);
}

void showMicrophoneError(bool on) {
  enablePeripheralPower();
  setAllPixels(on ? pixels.Color(32, 0, 32, 0) : 0);
  setBuzzer(false);
}

}  // namespace alarm_output
