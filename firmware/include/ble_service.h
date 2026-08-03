#pragma once

#include <cstdint>

#include "config_packet.h"

namespace ble_service {

constexpr char kServiceUuid[] = "3F751B85-D1AC-4699-AEEC-8B5B720B706B";
constexpr char kConfigUuid[] = "0235A089-40E1-4985-A78B-046EA4D983A9";
constexpr char kStatusUuid[] = "214F1B5A-DD35-4626-8247-FA07DA61EE64";

struct Status {
  uint8_t alarmState = 0;
  bool muted = false;
  bool sampling = false;
  bool alarmActive = false;
  uint8_t errorCode = 0;
  uint32_t appliedRevision = 0;
  uint32_t fingerprint = 0;
  uint32_t uptimeSeconds = 0;
};

void begin(const config_packet::Bytes& appliedPacket);
void update(uint32_t nowMs);
bool takePending(config_packet::Bytes& packet, RuntimeSettings& settings,
                 uint32_t& phoneRevision);
void acknowledge(const config_packet::Bytes& appliedPacket,
                 const Status& status);
void setStatus(const Status& status);

}  // namespace ble_service
