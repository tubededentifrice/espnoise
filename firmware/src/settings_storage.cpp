#include "settings_storage.h"

#include <Preferences.h>

namespace settings_storage {
namespace {

constexpr char kNamespace[] = "espnoise";
constexpr char kPacketKey[] = "config";
constexpr char kNameKey[] = "name_v1";
Preferences preferences;
bool ready = false;

}  // namespace

bool begin() {
  ready = preferences.begin(kNamespace, false);
  return ready;
}

bool load(config_packet::Bytes& packet) {
  if (!ready || preferences.getBytesLength(kPacketKey) != packet.size()) {
    return false;
  }
  config_packet::Bytes candidate{};
  if (preferences.getBytes(kPacketKey, candidate.data(), candidate.size()) !=
      candidate.size()) {
    return false;
  }
  RuntimeSettings settings;
  uint32_t revision = 0;
  if (config_packet::decode(candidate.data(), candidate.size(), settings,
                            revision) !=
      config_packet::ValidationResult::kValid) {
    return false;
  }
  packet = candidate;
  return true;
}

bool save(const config_packet::Bytes& packet) {
  return ready &&
         preferences.putBytes(kPacketKey, packet.data(), packet.size()) ==
             packet.size();
}

bool loadName(device_name::Value& name) {
  if (!ready || preferences.getBytesLength(kNameKey) !=
                    device_name::kPacketLength) {
    return false;
  }
  device_name::Packet packet{};
  if (preferences.getBytes(kNameKey, packet.data(), packet.size()) !=
      packet.size()) {
    return false;
  }
  device_name::Value candidate;
  if (device_name::decode(packet.data(), packet.size(), candidate) !=
          device_name::ValidationResult::kValid ||
      candidate.length == 0) {
    return false;
  }
  name = candidate;
  return true;
}

bool saveName(const device_name::Value& name) {
  if (!ready) {
    return false;
  }
  const auto packet = device_name::encode(name);
  return preferences.putBytes(kNameKey, packet.data(), packet.size()) ==
         packet.size();
}

}  // namespace settings_storage
