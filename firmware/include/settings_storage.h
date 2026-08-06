#pragma once

#include "config_packet.h"
#include "device_name.h"
#include "noise_analytics.h"

namespace settings_storage {

bool begin();
bool load(config_packet::Bytes& packet);
bool save(const config_packet::Bytes& packet);
bool loadName(device_name::Value& name);
bool saveName(const device_name::Value& name);
bool loadBluetoothEnabled(bool& enabled);
bool saveBluetoothEnabled(bool enabled);
bool loadAnalytics(noise_analytics::History& history);
bool saveAnalytics(const noise_analytics::History& history);
bool saveAnalyticsSequence(uint32_t sequence);
bool clearAnalytics();

}  // namespace settings_storage
