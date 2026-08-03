#include "ble_service.h"

namespace ble_service {
namespace {

void writeU32(uint8_t* data, uint32_t value) {
  data[0] = static_cast<uint8_t>(value);
  data[1] = static_cast<uint8_t>(value >> 8);
  data[2] = static_cast<uint8_t>(value >> 16);
  data[3] = static_cast<uint8_t>(value >> 24);
}

void writeU16(uint8_t* data, uint16_t value) {
  data[0] = static_cast<uint8_t>(value);
  data[1] = static_cast<uint8_t>(value >> 8);
}

}  // namespace

StatusPacket encodeStatus(const Status& status) {
  StatusPacket packet{};
  packet[0] = 2;
  packet[1] = status.alarmState;
  packet[2] = (status.muted ? 1U : 0U) |
              (status.sampling ? 2U : 0U) |
              (status.alarmActive ? 4U : 0U) |
              (status.measurementValid ? 8U : 0U);
  packet[3] = status.errorCode;
  writeU32(&packet[4], status.appliedRevision);
  writeU32(&packet[8], status.fingerprint);
  writeU16(&packet[12],
           static_cast<uint16_t>(status.observationMaximumDbfsX10));
  writeU16(&packet[14], status.measurementSequence);
  packet[16] = status.historyCount;
  packet[17] = status.greenSampleCount;
  packet[18] = status.orangeSampleCount;
  packet[19] = status.redSampleCount;
  return packet;
}

}  // namespace ble_service
