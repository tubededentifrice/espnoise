#pragma once

#include "config_packet.h"

namespace settings_storage {

bool begin();
bool load(config_packet::Bytes& packet);
bool save(const config_packet::Bytes& packet);

}  // namespace settings_storage
