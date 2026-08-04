#include "settings_storage.h"

#include <Preferences.h>

namespace settings_storage {
namespace {

constexpr char kNamespace[] = "espnoise";
constexpr char kPacketKey[] = "config";
constexpr char kNameKey[] = "name_v1";
constexpr char kAnalyticsKey[] = "analytics_v1";
constexpr char kAnalyticsSequenceKey[] = "analytics_seq";
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

bool loadAnalytics(noise_analytics::History& history) {
  if (!ready) {
    return false;
  }
  const size_t length = preferences.getBytesLength(kAnalyticsKey);
  bool historyWasLoaded = false;
  if (length >= noise_analytics::kStorageHeaderLength &&
      length <= noise_analytics::kMaximumStorageLength) {
    noise_analytics::Storage storage{};
    historyWasLoaded =
        preferences.getBytes(kAnalyticsKey, storage.data(), length) == length &&
        history.decodeStorage(storage.data(), length);
  }
  const uint32_t savedSequence =
      preferences.getUInt(kAnalyticsSequenceKey, 0);
  const bool sequenceWasLoaded =
      savedSequence != 0 && history.restoreCurrentSequence(savedSequence);
  return historyWasLoaded || sequenceWasLoaded;
}

bool saveAnalytics(const noise_analytics::History& history) {
  if (!ready) {
    return false;
  }
  noise_analytics::Storage storage{};
  const size_t length = history.encodeStorage(storage);
  return preferences.putBytes(kAnalyticsKey, storage.data(), length) == length;
}

bool saveAnalyticsSequence(uint32_t sequence) {
  return ready && sequence != 0 &&
         preferences.putUInt(kAnalyticsSequenceKey, sequence) ==
             sizeof(sequence);
}

}  // namespace settings_storage
