#pragma once

#include <cstdint>

enum class AlarmLevel : uint8_t {
  kQuiet = 0,
  kGreen = 1,
  kOrange = 2,
  kRed = 3,
};
