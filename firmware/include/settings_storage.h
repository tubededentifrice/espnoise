#pragma once

#include "config_packet.h"
#include "device_name.h"

namespace settings_storage {

bool begin();
bool load(config_packet::Bytes& packet);
bool save(const config_packet::Bytes& packet);
bool loadName(device_name::Value& name);
bool saveName(const device_name::Value& name);

}  // namespace settings_storage
