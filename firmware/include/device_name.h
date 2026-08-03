#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace device_name {

constexpr size_t kPacketLength = 20;
constexpr size_t kMaximumUtf8Bytes = 18;

using Packet = std::array<uint8_t, kPacketLength>;

struct Value {
  uint8_t length = 0;
  std::array<uint8_t, kMaximumUtf8Bytes> bytes{};

  bool operator==(const Value& other) const;
  bool operator!=(const Value& other) const { return !(*this == other); }
};

enum class ValidationResult {
  kValid,
  kBadLength,
  kBadVersion,
  kBadUtf8,
  kBadPadding,
};

Packet encode(const Value& value);
ValidationResult decode(const uint8_t* data, size_t length, Value& value);

}  // namespace device_name
