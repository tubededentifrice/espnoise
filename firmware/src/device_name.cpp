#include "device_name.h"

#include <algorithm>

namespace device_name {
namespace {

bool validUtf8(const uint8_t* data, size_t length) {
  size_t index = 0;
  while (index < length) {
    const uint8_t first = data[index++];
    uint32_t codePoint = 0;
    size_t continuationCount = 0;
    uint32_t minimumValue = 0;
    if (first <= 0x7F) {
      codePoint = first;
    } else if ((first & 0xE0) == 0xC0) {
      codePoint = first & 0x1F;
      continuationCount = 1;
      minimumValue = 0x80;
    } else if ((first & 0xF0) == 0xE0) {
      codePoint = first & 0x0F;
      continuationCount = 2;
      minimumValue = 0x800;
    } else if ((first & 0xF8) == 0xF0) {
      codePoint = first & 0x07;
      continuationCount = 3;
      minimumValue = 0x10000;
    } else {
      return false;
    }
    if (index + continuationCount > length) {
      return false;
    }
    for (size_t count = 0; count < continuationCount; ++count) {
      const uint8_t next = data[index++];
      if ((next & 0xC0) != 0x80) {
        return false;
      }
      codePoint = (codePoint << 6) | (next & 0x3F);
    }
    if (codePoint < minimumValue || codePoint > 0x10FFFF ||
        (codePoint >= 0xD800 && codePoint <= 0xDFFF) ||
        codePoint <= 0x1F || (codePoint >= 0x7F && codePoint <= 0x9F)) {
      return false;
    }
  }
  return true;
}

}  // namespace

bool Value::operator==(const Value& other) const {
  return length <= kMaximumUtf8Bytes &&
         other.length <= kMaximumUtf8Bytes && length == other.length &&
         std::equal(bytes.begin(), bytes.begin() + length,
                    other.bytes.begin());
}

Packet encode(const Value& value) {
  Packet packet{};
  const size_t length =
      std::min<size_t>(value.length, kMaximumUtf8Bytes);
  packet[0] = 1;
  packet[1] = static_cast<uint8_t>(length);
  std::copy(value.bytes.begin(), value.bytes.begin() + length,
            packet.begin() + 2);
  return packet;
}

ValidationResult decode(const uint8_t* data, size_t length, Value& value) {
  if (data == nullptr || length != kPacketLength) {
    return ValidationResult::kBadLength;
  }
  if (data[0] != 1) {
    return ValidationResult::kBadVersion;
  }
  const uint8_t nameLength = data[1];
  if (nameLength > kMaximumUtf8Bytes) {
    return ValidationResult::kBadLength;
  }
  if (!validUtf8(&data[2], nameLength)) {
    return ValidationResult::kBadUtf8;
  }
  for (size_t index = 2 + nameLength; index < kPacketLength; ++index) {
    if (data[index] != 0) {
      return ValidationResult::kBadPadding;
    }
  }
  Value candidate;
  candidate.length = nameLength;
  std::copy(&data[2], &data[2 + nameLength], candidate.bytes.begin());
  value = candidate;
  return ValidationResult::kValid;
}

}  // namespace device_name
