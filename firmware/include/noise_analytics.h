#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "alarm_level.h"

namespace noise_analytics {

constexpr uint16_t kBucketDurationSeconds = 15U * 60U;
constexpr size_t kRetentionBucketCount = 3U * 24U * 4U;
constexpr size_t kPacketLength = 20;
constexpr size_t kRequestLength = 12;
constexpr size_t kStorageHeaderLength = 12;
constexpr size_t kStoredRecordLength = 20;
constexpr size_t kMaximumStorageLength =
    kStorageHeaderLength + kRetentionBucketCount * kStoredRecordLength;
constexpr uint8_t kProtocolVersion = 2;
constexpr uint8_t kPartialFlag = 0x01;
constexpr uint8_t kStateTimeUnitSeconds = 5;
constexpr uint32_t kMinimumUtcTime = 1577836800UL;

using Packet = std::array<uint8_t, kPacketLength>;
using Storage = std::array<uint8_t, kMaximumStorageLength>;

struct Bucket {
  uint32_t sequence = 0;
  uint32_t startUtcSeconds = 0;
  uint16_t durationSeconds = 0;
  uint16_t meanPositiveLevelX10 = 0;
  uint16_t peakPositiveLevelX10 = 0;
  uint16_t greenSeconds = 0;
  uint16_t orangeSeconds = 0;
  uint16_t redSeconds = 0;
};

class History {
 public:
  void addSecond(AlarmLevel level, int16_t dbfsX10,
                 bool measurementValid);

  size_t recordCount() const;
  bool recordAt(size_t index, Bucket& bucket) const;
  uint32_t currentSequence() const;
  Packet currentPacket() const;
  Packet packetFor(const Bucket& bucket) const;
  bool syncUtcTime(uint32_t currentUtcSeconds);

  bool persistenceIsDue() const;
  void markPersisted();
  bool sequencePersistenceIsDue() const;
  void markSequencePersisted();
  bool restoreCurrentSequence(uint32_t sequence);
  size_t encodeStorage(Storage& storage) const;
  bool decodeStorage(const uint8_t* data, size_t length);

  static bool decodeRequest(const uint8_t* data, size_t length,
                            uint32_t& afterSequence,
                            uint32_t& currentUtcSeconds);
  static bool sequenceIsAfter(uint32_t sequence, uint32_t reference);

 private:
  void finishCurrentBucket();
  void append(const Bucket& bucket);
  Bucket makeCurrentBucket() const;

  std::array<Bucket, kRetentionBucketCount> records_{};
  size_t firstRecord_ = 0;
  size_t recordCount_ = 0;
  uint32_t nextSequence_ = 1;

  uint32_t currentStartUtcSeconds_ = 0;
  uint16_t currentDurationSeconds_ = 0;
  uint16_t validMeasurementSeconds_ = 0;
  uint32_t positiveLevelSumX10_ = 0;
  uint16_t peakPositiveLevelX10_ = 0;
  uint16_t greenSeconds_ = 0;
  uint16_t orangeSeconds_ = 0;
  uint16_t redSeconds_ = 0;
  uint8_t completedSincePersistence_ = 0;
  bool sequencePersistenceIsDue_ = false;
};

}  // namespace noise_analytics
