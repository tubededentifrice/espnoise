#include "ble_service.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include <algorithm>
#include <array>
#include <cstring>

namespace ble_service {
namespace {

constexpr uint32_t kFastAdvertisingDurationMs = 2UL * 60UL * 1000UL;
constexpr uint16_t kFastAdvertisingMinInterval = 160;
constexpr uint16_t kFastAdvertisingMaxInterval = 240;
constexpr uint16_t kSlowAdvertisingMinInterval = 1600;
constexpr uint16_t kSlowAdvertisingMaxInterval = 2000;

NimBLEServer* server = nullptr;
NimBLEAdvertising* advertising = nullptr;
NimBLECharacteristic* configCharacteristic = nullptr;
NimBLECharacteristic* statusCharacteristic = nullptr;
config_packet::Bytes currentPacket{};
config_packet::Bytes pendingPacket{};
RuntimeSettings pendingSettings;
uint32_t pendingRevision = 0;
portMUX_TYPE pendingMutex = portMUX_INITIALIZER_UNLOCKED;
bool hasPending = false;
volatile bool connected = false;
volatile bool slowAdvertising = false;
uint32_t advertisingStartMs = 0;
std::array<uint8_t, 16> lastStatusPacket{};
bool haveStatus = false;
constexpr uint32_t kStatusHeartbeatSeconds = 10;

void writeU32(uint8_t* data, uint32_t value) {
  data[0] = static_cast<uint8_t>(value);
  data[1] = static_cast<uint8_t>(value >> 8);
  data[2] = static_cast<uint8_t>(value >> 16);
  data[3] = static_cast<uint8_t>(value >> 24);
}

std::array<uint8_t, 16> encodeStatus(const Status& status) {
  std::array<uint8_t, 16> packet{};
  packet[0] = 1;
  packet[1] = status.alarmState;
  packet[2] = (status.muted ? 1U : 0U) |
              (status.sampling ? 2U : 0U) |
              (status.alarmActive ? 4U : 0U);
  packet[3] = status.errorCode;
  writeU32(&packet[4], status.appliedRevision);
  writeU32(&packet[8], status.fingerprint);
  writeU32(&packet[12], status.uptimeSeconds);
  return packet;
}

void setAdvertisingIntervals(bool slow) {
  advertising->setMinInterval(slow ? kSlowAdvertisingMinInterval
                                   : kFastAdvertisingMinInterval);
  advertising->setMaxInterval(slow ? kSlowAdvertisingMaxInterval
                                   : kFastAdvertisingMaxInterval);
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* source,
                 ble_gap_conn_desc* description) override {
    connected = true;
    if (description == nullptr) {
      return;
    }

    const bool knownBond = NimBLEDevice::isBonded(
        NimBLEAddress(description->peer_id_addr));
    const bool pairingOpen =
        millis() - advertisingStartMs < kFastAdvertisingDurationMs;
    if (!description->sec_state.encrypted && !knownBond && !pairingOpen) {
      connected = false;
      source->disconnect(description->conn_handle);
      return;
    }
    if (!description->sec_state.encrypted) {
      NimBLEDevice::startSecurity(description->conn_handle);
    }
  }

  void onDisconnect(NimBLEServer* source) override {
    (void)source;
    connected = false;
    setAdvertisingIntervals(slowAdvertising);
    advertising->start();
  }

  void onAuthenticationComplete(ble_gap_conn_desc* description) override {
    if (description == nullptr ||
        !description->sec_state.encrypted ||
        !description->sec_state.bonded) {
      connected = false;
      if (description != nullptr) {
        server->disconnect(description->conn_handle);
      }
    }
  }
};

class ConfigCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic) override {
    const std::string value = characteristic->getValue();
    RuntimeSettings settings;
    uint32_t revision = 0;
    const auto result = config_packet::decode(
        reinterpret_cast<const uint8_t*>(value.data()), value.size(), settings,
        revision);

    // Keep reads at the last applied value until the main loop applies all
    // related values at one safe boundary.
    config_packet::Bytes readback{};
    portENTER_CRITICAL(&pendingMutex);
    readback = currentPacket;
    portEXIT_CRITICAL(&pendingMutex);
    characteristic->setValue(readback.data(), readback.size());
    if (result != config_packet::ValidationResult::kValid) {
      return;
    }

    config_packet::Bytes candidate{};
    std::memcpy(candidate.data(), value.data(), candidate.size());
    portENTER_CRITICAL(&pendingMutex);
    pendingPacket = candidate;
    pendingSettings = settings;
    pendingRevision = revision;
    hasPending = true;
    portEXIT_CRITICAL(&pendingMutex);
  }
};

ServerCallbacks serverCallbacks;
ConfigCallbacks configCallbacks;

}  // namespace

void begin(const config_packet::Bytes& appliedPacket) {
  currentPacket = appliedPacket;
  const uint64_t chipId = ESP.getEfuseMac();
  char name[18] = {};
  snprintf(name, sizeof(name), "ESPNoise-%04X",
           static_cast<unsigned>(chipId & 0xFFFFU));

  NimBLEDevice::init(name);
  NimBLEDevice::setSecurityAuth(true, false, true);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

  server = NimBLEDevice::createServer();
  server->setCallbacks(&serverCallbacks);
  NimBLEService* service = server->createService(kServiceUuid);
  configCharacteristic = service->createCharacteristic(
      kConfigUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE |
                       NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::NOTIFY);
  statusCharacteristic = service->createCharacteristic(
      kStatusUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  configCharacteristic->setCallbacks(&configCallbacks);
  configCharacteristic->setValue(currentPacket.data(), currentPacket.size());
  Status initialStatus;
  initialStatus.appliedRevision =
      static_cast<uint32_t>(currentPacket[28]) |
      static_cast<uint32_t>(currentPacket[29]) << 8 |
      static_cast<uint32_t>(currentPacket[30]) << 16 |
      static_cast<uint32_t>(currentPacket[31]) << 24;
  initialStatus.fingerprint = config_packet::fingerprint(currentPacket);
  lastStatusPacket = encodeStatus(initialStatus);
  haveStatus = true;
  statusCharacteristic->setValue(lastStatusPacket.data(),
                                 lastStatusPacket.size());
  service->start();

  advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUuid);
  advertising->setScanResponse(true);
  setAdvertisingIntervals(false);
  advertisingStartMs = millis();
  advertising->start();
}

void update(uint32_t nowMs) {
  if (!slowAdvertising && nowMs - advertisingStartMs >=
                              kFastAdvertisingDurationMs) {
    slowAdvertising = true;
    if (!connected) {
      advertising->stop();
      setAdvertisingIntervals(true);
      advertising->start();
    }
  }
}

bool takePending(config_packet::Bytes& packet, RuntimeSettings& settings,
                 uint32_t& phoneRevision) {
  bool available = false;
  portENTER_CRITICAL(&pendingMutex);
  if (hasPending) {
    packet = pendingPacket;
    settings = pendingSettings;
    phoneRevision = pendingRevision;
    hasPending = false;
    available = true;
  }
  portEXIT_CRITICAL(&pendingMutex);
  return available;
}

void acknowledge(const config_packet::Bytes& appliedPacket,
                 const Status& status) {
  portENTER_CRITICAL(&pendingMutex);
  currentPacket = appliedPacket;
  portEXIT_CRITICAL(&pendingMutex);
  configCharacteristic->setValue(currentPacket.data(), currentPacket.size());
  configCharacteristic->notify();
  setStatus(status);
}

void setStatus(const Status& status) {
  const auto packet = encodeStatus(status);
  if (haveStatus) {
    const bool stateIsUnchanged =
        std::equal(packet.begin(), packet.begin() + 12,
                   lastStatusPacket.begin());
    const uint32_t lastUptime =
        static_cast<uint32_t>(lastStatusPacket[12]) |
        static_cast<uint32_t>(lastStatusPacket[13]) << 8 |
        static_cast<uint32_t>(lastStatusPacket[14]) << 16 |
        static_cast<uint32_t>(lastStatusPacket[15]) << 24;
    if (stateIsUnchanged &&
        status.uptimeSeconds - lastUptime < kStatusHeartbeatSeconds) {
      return;
    }
  }
  lastStatusPacket = packet;
  haveStatus = true;
  statusCharacteristic->setValue(packet.data(), packet.size());
  statusCharacteristic->notify();
}

}  // namespace ble_service
