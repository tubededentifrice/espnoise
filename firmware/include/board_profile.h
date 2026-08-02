#pragma once

#include <Arduino.h>

#ifndef ESPNOISE_SWITCHED_PERIPHERAL_POWER
#define ESPNOISE_SWITCHED_PERIPHERAL_POWER 0
#endif

namespace board_profile {

// INMP441 I2S pins.
constexpr gpio_num_t kMicClockPin = GPIO_NUM_26;
constexpr gpio_num_t kMicWordSelectPin = GPIO_NUM_25;
constexpr gpio_num_t kMicDataPin = GPIO_NUM_32;

// Outputs and controls.
constexpr uint8_t kLedDataPin = 18;
constexpr uint8_t kBuzzerPin = 23;
constexpr gpio_num_t kMuteButtonPin = GPIO_NUM_27;

// This pin controls the optional battery-build boost module. It is not
// connected in the USB-powered build.
constexpr uint8_t kPeripheralPowerEnablePin = 13;
constexpr bool kHasSwitchedPeripheralPower =
    ESPNOISE_SWITCHED_PERIPHERAL_POWER != 0;

}  // namespace board_profile
