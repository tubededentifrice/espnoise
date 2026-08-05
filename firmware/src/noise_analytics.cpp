#include "noise_analytics.h"

#include <algorithm>
#include <cstring>

namespace noise_analytics {
namespace {

constexpr uint8_t kStorageMagic[] = {'E', 'N', 'A', '1'};
constexpr uint8_t kBucketsPerPersistence = 4;

void put16(uint16_t value, size_t offset, uint8_t* bytes) {
  bytes[offset] = static_cast<uint8_t>(value);
  bytes[offset + 1] = static_cast<uint8_t>(value >> 8);
}

void put32(uint32_t value, size_t offset, uint8_t* bytes) {
  for (size_t index = 0; index < 4; ++index) {
    bytes[offset + index] =
        static_cast<uint8_t>(value >> (index * 8));
  }
}

uint16_t get16(const uint8_t* bytes, size_t offset) {
  return static_cast<uint16_t>(bytes[offset]) |
         static_cast<uint16_t>(bytes[offset + 1]) << 8;
}

uint32_t get32(const uint8_t* bytes, size_t offset) {
  uint32_t value = 0;
  for (size_t index = 0; index < 4; ++index) {
    value |= static_cast<uint32_t>(bytes[offset + index]) << (index * 8);
  }
  return value;
}

bool bucketIsValid(const Bucket& bucket) {
  const uint32_t coloredSeconds =
      static_cast<uint32_t>(bucket.greenSeconds) + bucket.orangeSeconds +
      bucket.redSeconds;
  return bucket.sequence != 0 &&
         bucket.durationSeconds <= kBucketDurationSeconds &&
         bucket.meanPositiveLevelX10 <= 1200 &&
         bucket.peakPositiveLevelX10 <= 1200 &&
         bucket.meanPositiveLevelX10 <= bucket.peakPositiveLevelX10 &&
         coloredSeconds <= bucket.durationSeconds;
}

void encodeBucket(const Bucket& bucket, uint8_t* bytes) {
  put32(bucket.sequence, 0, bytes);
  put16(bucket.durationSeconds, 4, bytes);
  put16(bucket.meanPositiveLevelX10, 6, bytes);
  put16(bucket.peakPositiveLevelX10, 8, bytes);
  put16(bucket.greenSeconds, 10, bytes);
  put16(bucket.orangeSeconds, 12, bytes);
  put16(bucket.redSeconds, 14, bytes);
}

Bucket decodeBucket(const uint8_t* bytes) {
  Bucket bucket;
  bucket.sequence = get32(bytes, 0);
  bucket.durationSeconds = get16(bytes, 4);
  bucket.meanPositiveLevelX10 = get16(bytes, 6);
  bucket.peakPositiveLevelX10 = get16(bytes, 8);
  bucket.greenSeconds = get16(bytes, 10);
  bucket.orangeSeconds = get16(bytes, 12);
  bucket.redSeconds = get16(bytes, 14);
  return bucket;
}

Packet encodePacket(const Bucket& bucket, uint8_t flags,
                    uint16_t ageBuckets) {
  Packet packet{};
  packet[0] = kProtocolVersion;
  packet[1] = flags;
  put32(bucket.sequence, 2, packet.data());
  put16(ageBuckets, 6, packet.data());
  put16(bucket.durationSeconds, 8, packet.data());
  put16(bucket.meanPositiveLevelX10, 10, packet.data());
  put16(bucket.peakPositiveLevelX10, 12, packet.data());
  put16(bucket.greenSeconds, 14, packet.data());
  put16(bucket.orangeSeconds, 16, packet.data());
  put16(bucket.redSeconds, 18, packet.data());
  return packet;
}

}  // namespace

void History::addSecond(AlarmLevel level, int16_t dbfsX10,
                        bool measurementValid) {
  if (measurementValid) {
    const int positiveLevel =
        std::max(0, std::min(1200, static_cast<int>(dbfsX10) + 1200));
    positiveLevelSumX10_ += static_cast<uint16_t>(positiveLevel);
    peakPositiveLevelX10_ = std::max(
        peakPositiveLevelX10_, static_cast<uint16_t>(positiveLevel));
    ++validMeasurementSeconds_;
  }

  if (level == AlarmLevel::kGreen) {
    ++greenSeconds_;
  } else if (level == AlarmLevel::kOrange) {
    ++orangeSeconds_;
  } else if (level == AlarmLevel::kRed) {
    ++redSeconds_;
  }
  ++currentDurationSeconds_;
  if (currentDurationSeconds_ >= kBucketDurationSeconds) {
    finishCurrentBucket();
  }
}

size_t History::recordCount() const { return recordCount_; }

bool History::recordAt(size_t index, Bucket& bucket) const {
  if (index >= recordCount_) {
    return false;
  }
  bucket = records_[(firstRecord_ + index) % records_.size()];
  return true;
}

uint32_t History::currentSequence() const { return nextSequence_; }

Packet History::currentPacket() const {
  return encodePacket(makeCurrentBucket(), kPartialFlag, 0);
}

Packet History::packetFor(const Bucket& bucket) const {
  const uint32_t difference = nextSequence_ - bucket.sequence;
  const uint16_t age = static_cast<uint16_t>(
      std::min<uint32_t>(difference, UINT16_MAX));
  return encodePacket(bucket, 0, age);
}

bool History::persistenceIsDue() const {
  return completedSincePersistence_ >= kBucketsPerPersistence;
}

void History::markPersisted() { completedSincePersistence_ = 0; }

bool History::sequencePersistenceIsDue() const {
  return sequencePersistenceIsDue_;
}

void History::markSequencePersisted() {
  sequencePersistenceIsDue_ = false;
}

bool History::restoreCurrentSequence(uint32_t sequence) {
  if (sequence == 0 ||
      (recordCount_ > 0 &&
       !sequenceIsAfter(
           sequence,
           records_[(firstRecord_ + recordCount_ - 1) % records_.size()]
               .sequence))) {
    return false;
  }
  if (sequenceIsAfter(sequence, nextSequence_)) {
    nextSequence_ = sequence;
  }
  return true;
}

size_t History::encodeStorage(Storage& storage) const {
  storage.fill(0);
  std::copy(std::begin(kStorageMagic), std::end(kStorageMagic),
            storage.begin());
  put32(nextSequence_, 4, storage.data());
  put16(static_cast<uint16_t>(recordCount_), 8, storage.data());
  size_t offset = kStorageHeaderLength;
  for (size_t index = 0; index < recordCount_; ++index) {
    Bucket bucket;
    recordAt(index, bucket);
    encodeBucket(bucket, storage.data() + offset);
    offset += kStoredRecordLength;
  }
  return offset;
}

bool History::decodeStorage(const uint8_t* data, size_t length) {
  if (data == nullptr || length < kStorageHeaderLength ||
      !std::equal(std::begin(kStorageMagic), std::end(kStorageMagic), data)) {
    return false;
  }
  const size_t count = get16(data, 8);
  if (count > kRetentionBucketCount ||
      length != kStorageHeaderLength + count * kStoredRecordLength) {
    return false;
  }
  size_t offset = kStorageHeaderLength;
  uint32_t previousSequence = 0;
  for (size_t index = 0; index < count; ++index) {
    const Bucket bucket = decodeBucket(data + offset);
    if (!bucketIsValid(bucket)) {
      return false;
    }
    if (index > 0 && !sequenceIsAfter(bucket.sequence, previousSequence)) {
      return false;
    }
    previousSequence = bucket.sequence;
    offset += kStoredRecordLength;
  }
  const uint32_t candidateNextSequence = get32(data, 4);
  if (candidateNextSequence == 0 ||
      (count > 0 &&
       !sequenceIsAfter(candidateNextSequence, previousSequence))) {
    return false;
  }
  offset = kStorageHeaderLength;
  for (size_t index = 0; index < count; ++index) {
    records_[index] = decodeBucket(data + offset);
    offset += kStoredRecordLength;
  }
  firstRecord_ = 0;
  recordCount_ = count;
  nextSequence_ = candidateNextSequence;
  completedSincePersistence_ = 0;
  sequencePersistenceIsDue_ = false;
  return true;
}

bool History::decodeRequest(const uint8_t* data, size_t length,
                            uint32_t& afterSequence) {
  if (data == nullptr || length != kRequestLength ||
      data[0] != kProtocolVersion || data[1] != 1 || data[6] != 0 ||
      data[7] != 0) {
    return false;
  }
  afterSequence = get32(data, 2);
  return true;
}

bool History::sequenceIsAfter(uint32_t sequence, uint32_t reference) {
  return sequence != reference &&
         static_cast<int32_t>(sequence - reference) > 0;
}

void History::finishCurrentBucket() {
  append(makeCurrentBucket());
  ++nextSequence_;
  if (nextSequence_ == 0) {
    nextSequence_ = 1;
  }
  currentDurationSeconds_ = 0;
  validMeasurementSeconds_ = 0;
  positiveLevelSumX10_ = 0;
  peakPositiveLevelX10_ = 0;
  greenSeconds_ = 0;
  orangeSeconds_ = 0;
  redSeconds_ = 0;
  if (completedSincePersistence_ < UINT8_MAX) {
    ++completedSincePersistence_;
  }
  sequencePersistenceIsDue_ = true;
}

void History::append(const Bucket& bucket) {
  if (recordCount_ < records_.size()) {
    records_[(firstRecord_ + recordCount_) % records_.size()] = bucket;
    ++recordCount_;
    return;
  }
  records_[firstRecord_] = bucket;
  firstRecord_ = (firstRecord_ + 1) % records_.size();
}

Bucket History::makeCurrentBucket() const {
  Bucket bucket;
  bucket.sequence = nextSequence_;
  bucket.durationSeconds = currentDurationSeconds_;
  bucket.meanPositiveLevelX10 =
      validMeasurementSeconds_ == 0
          ? 0
          : static_cast<uint16_t>(
                positiveLevelSumX10_ / validMeasurementSeconds_);
  bucket.peakPositiveLevelX10 = peakPositiveLevelX10_;
  bucket.greenSeconds = greenSeconds_;
  bucket.orangeSeconds = orangeSeconds_;
  bucket.redSeconds = redSeconds_;
  return bucket;
}

}  // namespace noise_analytics
