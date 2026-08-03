#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "runtime_settings.h"

namespace config_packet {

constexpr uint8_t kVersion = 1;
constexpr size_t kSize = 32;
constexpr size_t kFingerprintSize = 28;
using Bytes = std::array<uint8_t, kSize>;

enum class ValidationResult : uint8_t {
  kValid = 0,
  kWrongSize,
  kWrongVersion,
  kBadFlags,
  kBadBrightness,
  kBadVolume,
  kBadThresholds,
  kBadSampleTiming,
  kTooManyHistorySamples,
  kBadTriggerPercent,
  kTooFewRequiredSamples,
  kBadMuteDuration,
};

Bytes encode(const RuntimeSettings& settings, uint32_t phoneRevision);
ValidationResult decode(const uint8_t* data, size_t size,
                        RuntimeSettings& settings, uint32_t& phoneRevision);
uint32_t fingerprint(const uint8_t* data, size_t size = kFingerprintSize);
uint32_t fingerprint(const Bytes& packet);
bool effectiveDataEqual(const Bytes& left, const Bytes& right);

}  // namespace config_packet
