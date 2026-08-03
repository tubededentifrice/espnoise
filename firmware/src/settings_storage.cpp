#include "settings_storage.h"

#include <Preferences.h>

namespace settings_storage {
namespace {

constexpr char kNamespace[] = "espnoise";
constexpr char kPacketKey[] = "config";
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

}  // namespace settings_storage
