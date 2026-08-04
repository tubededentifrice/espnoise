#include "config_packet.h"

#include <algorithm>

#include "config.h"

namespace config_packet {
namespace {

uint16_t readU16(const uint8_t* data) {
  return static_cast<uint16_t>(data[0]) |
         static_cast<uint16_t>(data[1]) << 8;
}

uint32_t readU32(const uint8_t* data) {
  return static_cast<uint32_t>(data[0]) |
         static_cast<uint32_t>(data[1]) << 8 |
         static_cast<uint32_t>(data[2]) << 16 |
         static_cast<uint32_t>(data[3]) << 24;
}

void writeU16(uint8_t* data, uint16_t value) {
  data[0] = static_cast<uint8_t>(value);
  data[1] = static_cast<uint8_t>(value >> 8);
}

void writeU32(uint8_t* data, uint32_t value) {
  data[0] = static_cast<uint8_t>(value);
  data[1] = static_cast<uint8_t>(value >> 8);
  data[2] = static_cast<uint8_t>(value >> 16);
  data[3] = static_cast<uint8_t>(value >> 24);
}

}  // namespace

Bytes encode(const RuntimeSettings& settings, uint32_t phoneRevision) {
  Bytes packet{};
  packet[0] = kVersion;
  packet[2] = settings.ledBrightnessPercent;
  packet[3] = settings.buzzerVolumePercent;
  writeU16(&packet[4], static_cast<uint16_t>(settings.greenThresholdDbfsX10));
  writeU16(&packet[6], static_cast<uint16_t>(settings.orangeThresholdDbfsX10));
  writeU16(&packet[8], static_cast<uint16_t>(settings.redThresholdDbfsX10));
  writeU32(&packet[10], settings.sampleDurationMs);
  writeU32(&packet[14], settings.samplePeriodMs);
  writeU32(&packet[18], settings.decisionWindowMs);
  packet[22] = settings.triggerSamplePercent;
  writeU32(&packet[24], settings.muteDurationSeconds);
  writeU32(&packet[28], phoneRevision);
  return packet;
}

ValidationResult decode(const uint8_t* data, size_t size,
                        RuntimeSettings& settings, uint32_t& phoneRevision) {
  if (size != kSize) {
    return ValidationResult::kWrongSize;
  }
  if (data[0] != kVersion) {
    return ValidationResult::kWrongVersion;
  }
  if (data[1] != 0 || data[23] != 0) {
    return ValidationResult::kBadFlags;
  }

  RuntimeSettings candidate;
  candidate.ledBrightnessPercent = data[2];
  candidate.buzzerVolumePercent = data[3];
  candidate.greenThresholdDbfsX10 = static_cast<int16_t>(readU16(&data[4]));
  candidate.orangeThresholdDbfsX10 = static_cast<int16_t>(readU16(&data[6]));
  candidate.redThresholdDbfsX10 = static_cast<int16_t>(readU16(&data[8]));
  candidate.sampleDurationMs = readU32(&data[10]);
  candidate.samplePeriodMs = readU32(&data[14]);
  candidate.decisionWindowMs = readU32(&data[18]);
  candidate.triggerSamplePercent = data[22];
  candidate.muteDurationSeconds = readU32(&data[24]);

  if (candidate.ledBrightnessPercent > 100) {
    return ValidationResult::kBadBrightness;
  }
  if (candidate.buzzerVolumePercent > 100) {
    return ValidationResult::kBadVolume;
  }
  if (candidate.greenThresholdDbfsX10 < config::kMinimumThresholdDbfsX10 ||
      candidate.redThresholdDbfsX10 > config::kMaximumThresholdDbfsX10 ||
      candidate.greenThresholdDbfsX10 >= candidate.orangeThresholdDbfsX10 ||
      candidate.orangeThresholdDbfsX10 >= candidate.redThresholdDbfsX10) {
    return ValidationResult::kBadThresholds;
  }
  if (candidate.sampleDurationMs == 0 || candidate.samplePeriodMs == 0 ||
      candidate.sampleDurationMs > candidate.samplePeriodMs ||
      candidate.decisionWindowMs < candidate.samplePeriodMs ||
      candidate.decisionWindowMs % candidate.samplePeriodMs != 0) {
    return ValidationResult::kBadSampleTiming;
  }
  const size_t historyCount = candidate.historySampleCount();
  if (historyCount == 0 ||
      historyCount > config::kMaximumHistorySampleCount) {
    return ValidationResult::kTooManyHistorySamples;
  }
  if (candidate.triggerSamplePercent <
          config::kMinimumTriggerSamplePercent ||
      candidate.triggerSamplePercent >
          config::kMaximumTriggerSamplePercent) {
    return ValidationResult::kBadTriggerPercent;
  }
  if (candidate.requiredTriggerSampleCount() < 2) {
    return ValidationResult::kTooFewRequiredSamples;
  }
  if (candidate.muteDurationSeconds <
          config::kMinimumMuteDurationSeconds ||
      candidate.muteDurationSeconds >
          config::kMaximumMuteDurationSeconds) {
    return ValidationResult::kBadMuteDuration;
  }

  settings = candidate;
  phoneRevision = readU32(&data[28]);
  return ValidationResult::kValid;
}

uint32_t fingerprint(const uint8_t* data, size_t size) {
  uint32_t hash = 2166136261UL;
  for (size_t index = 0; index < size; ++index) {
    hash ^= data[index];
    hash *= 16777619UL;
  }
  return hash;
}

uint32_t fingerprint(const Bytes& packet) {
  return fingerprint(packet.data(), kFingerprintSize);
}

bool effectiveDataEqual(const Bytes& left, const Bytes& right) {
  return std::equal(left.begin(), left.begin() + kFingerprintSize,
                    right.begin());
}

}  // namespace config_packet
