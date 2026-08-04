#include "alarm_output.h"

#include <Adafruit_NeoPixel.h>

#include <cmath>
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

#ifndef ESPNOISE_PRODUCTION_STARTUP_CHECK
#define ESPNOISE_PRODUCTION_STARTUP_CHECK 0
#endif

namespace alarm_output {
namespace {

constexpr uint8_t kBuzzerPwmChannel = 0;

Adafruit_NeoPixel pixels(config::kLedCount, board_profile::kLedDataPin,
                         NEO_GRBW + NEO_KHZ800);

bool peripheralPowerOn = false;
uint32_t displayedColor = UINT32_MAX;
uint32_t currentBuzzerFrequencyHz = 0;
RuntimeSettings runtimeSettings;

uint8_t buzzerDutyForVolume() {
  const uint8_t volume = runtimeSettings.buzzerVolumePercent;
  if (volume == 0) {
    return 0;
  }

  // A passive piezo responds to the fundamental part of the PWM waveform.
  // Map the requested electrical tone amplitude to the short PWM pulse that
  // produces it. A 100% setting gives the maximum 50% PWM duty.
  constexpr float kPi = 3.14159265F;
  const float amplitude = static_cast<float>(volume) / 100.0F;
  const float duty = asinf(amplitude) / kPi;
  return static_cast<uint8_t>(lroundf(duty * 255.0F));
}

void setBuzzer(bool on) {
  ledcWrite(kBuzzerPwmChannel, on ? buzzerDutyForVolume() : 0);
}

void setBuzzerFrequency(uint32_t frequencyHz) {
  if (frequencyHz == currentBuzzerFrequencyHz) {
    return;
  }
  setBuzzer(false);
  ledcSetup(kBuzzerPwmChannel, frequencyHz, 8);
  currentBuzzerFrequencyHz = frequencyHz;
}

void playTestMelody() {
  constexpr uint16_t frequencies[] = {523, 659, 784, 1047, 784, 1047};
  constexpr uint16_t durationsMs[] = {160, 160, 160, 320, 160, 420};

  for (size_t index = 0;
       index < sizeof(frequencies) / sizeof(frequencies[0]); ++index) {
    setBuzzerFrequency(frequencies[index]);
    setBuzzer(true);
    delay(durationsMs[index]);
    setBuzzer(false);
    delay(60);
  }

  setBuzzerFrequency(config::kRedStyle.buzzerFrequencyHz);
}

void setAllPixels(uint32_t color) {
  for (uint8_t index = 0; index < config::kLedCount; ++index) {
    pixels.setPixelColor(index, color);
  }
  pixels.show();
  displayedColor = color;
}

void playProductionStartupCheck() {
  constexpr uint16_t frequencies[] = {523, 659, 784};
  constexpr uint16_t durationsMs[] = {90, 90, 140};
  const uint32_t colors[] = {
      pixels.Color(0, 255, 0, 0),
      pixels.Color(255, 50, 0, 0),
      pixels.Color(255, 0, 0, 24),
  };

  for (size_t index = 0;
       index < sizeof(frequencies) / sizeof(frequencies[0]); ++index) {
    setAllPixels(colors[index]);
    setBuzzerFrequency(frequencies[index]);
    setBuzzer(config::kBuzzerEnabled);
    delay(durationsMs[index]);
    setBuzzer(false);
    setAllPixels(0);
    delay(25);
  }

  setBuzzerFrequency(config::kRedStyle.buzzerFrequencyHz);
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

const config::AlarmStyle& styleForLevel(AlarmLevel level) {
  if (level == AlarmLevel::kRed) {
    return config::kRedStyle;
  }
  if (level == AlarmLevel::kOrange) {
    return config::kOrangeStyle;
  }
  return config::kGreenStyle;
}

bool buzzerPulseActive(const config::AlarmStyle& style,
                       uint32_t patternAgeMs) {
  if (style.buzzerPulseCount == 0 || style.buzzerPulseMs == 0) {
    return false;
  }
  const uint32_t stepMs = style.buzzerPulseMs + style.buzzerGapMs;
  const uint32_t pulseIndex = patternAgeMs / stepMs;
  return pulseIndex < style.buzzerPulseCount &&
         patternAgeMs % stepMs < style.buzzerPulseMs;
}

}  // namespace

void begin() {
  setBuzzerFrequency(config::kRedStyle.buzzerFrequencyHz);
  ledcAttachPin(board_profile::kBuzzerPin, kBuzzerPwmChannel);
  setBuzzer(false);

  if (board_profile::kHasSwitchedPeripheralPower) {
    pinMode(board_profile::kPeripheralPowerEnablePin, OUTPUT);
    digitalWrite(board_profile::kPeripheralPowerEnablePin, LOW);
  }

  pixels.begin();
  setSettings(runtimeSettings);
  enablePeripheralPower();
  setAllPixels(0);

  if (ESPNOISE_PRODUCTION_STARTUP_CHECK != 0) {
    playProductionStartupCheck();
  }

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

void setSettings(const RuntimeSettings& settings) {
  runtimeSettings = settings;
  const uint16_t brightness =
      static_cast<uint16_t>(config::kLedBrightnessMaximum) *
      runtimeSettings.ledBrightnessPercent / 100;
  pixels.setBrightness(static_cast<uint8_t>(brightness));
  displayedColor = UINT32_MAX;
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
            AlarmLevel measuredLevel, uint32_t alarmAgeMs,
            uint32_t patternAgeMs) {
  (void)now;
  if (muted || !alarmActive) {
    off();
    return;
  }

  enablePeripheralPower();
  const config::AlarmStyle& style = styleForLevel(measuredLevel);
  const uint32_t lightPhase =
      alarmAgeMs % (2 * style.blinkHalfPeriodMs);
  const bool lightOn = lightPhase < style.blinkHalfPeriodMs;
  const uint32_t wantedColor =
      lightOn ? pixels.Color(style.red, style.green, style.blue,
                             style.warmWhite)
              : 0;
  if (wantedColor != displayedColor) {
    setAllPixels(wantedColor);
  }

  // Keep the buzzer off during every microphone check. The scheduler also
  // adds a settling gap before it starts I2S and ignores the I2S warm-up data.
  // The lights can continue to flash during a check.
  setBuzzerFrequency(style.buzzerFrequencyHz);
  const bool buzzerOn = config::kBuzzerEnabled && !sampleActive &&
                        buzzerPulseActive(style, patternAgeMs);
  setBuzzer(buzzerOn);
}

void silenceBuzzer() { setBuzzer(false); }

void showMicrophoneError(bool on) {
  enablePeripheralPower();
  setAllPixels(on ? pixels.Color(32, 0, 32, 0) : 0);
  setBuzzer(false);
}

void showSampleWarning(AlarmLevel level) {
  enablePeripheralPower();
  const config::AlarmStyle& style = styleForLevel(level);
  setAllPixels(
      pixels.Color(style.red, style.green, style.blue, style.warmWhite));
  setBuzzer(false);
}

void showCalibrationTarget(AlarmLevel level) { showSampleWarning(level); }

}  // namespace alarm_output
