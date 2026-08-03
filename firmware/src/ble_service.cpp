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
NimBLECharacteristic* nameCharacteristic = nullptr;
config_packet::Bytes currentPacket{};
config_packet::Bytes pendingPacket{};
device_name::Value currentName;
device_name::Value pendingName;
RuntimeSettings pendingSettings;
uint32_t pendingRevision = 0;
portMUX_TYPE pendingMutex = portMUX_INITIALIZER_UNLOCKED;
bool hasPending = false;
bool hasPendingName = false;
bool hasNameReadRequest = false;
volatile bool connected = false;
volatile bool slowAdvertising = false;
uint32_t advertisingStartMs = 0;
std::array<uint8_t, 20> lastStatusPacket{};
bool haveStatus = false;
bool firstPairingPending = false;
uint32_t lastStatusSentMs = 0;
constexpr uint32_t kStatusHeartbeatMs = 10UL * 1000UL;
constexpr uint32_t kLiveStatusIntervalMs = 250;

bool pairingOpen() {
  return firstPairingPending ||
         millis() - advertisingStartMs < kFastAdvertisingDurationMs;
}

std::string advertisedName(const device_name::Value& name) {
  std::string result = "ESPNoise-";
  result.append(reinterpret_cast<const char*>(name.bytes.data()),
                name.length);
  return result;
}

void setAdvertisingIntervals(bool slow);

void updateAdvertisedName(const device_name::Value& name) {
  const std::string fullName = advertisedName(name);
  NimBLEDevice::setDeviceName(fullName);
  const bool restart = advertising != nullptr && advertising->isAdvertising();
  if (restart) {
    advertising->stop();
  }
  NimBLEAdvertisementData scanResponseData;
  scanResponseData.setName(fullName);
  advertising->setScanResponseData(scanResponseData);
  if (restart) {
    setAdvertisingIntervals(slowAdvertising);
    advertising->start();
  }
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
    if (!description->sec_state.encrypted && !knownBond && !pairingOpen()) {
      Serial.printf(
          "[BLE] Rejected new phone outside pairing window; bonds=%u\n",
          static_cast<unsigned>(NimBLEDevice::getNumBonds()));
      connected = false;
      source->disconnect(description->conn_handle);
      return;
    }
    if (!description->sec_state.encrypted) {
      if (!knownBond &&
          NimBLEDevice::getNumBonds() >= CONFIG_BT_NIMBLE_MAX_BONDS) {
        Serial.println("[BLE] Rejected new phone because bond storage is full");
        connected = false;
        source->disconnect(description->conn_handle);
        return;
      }
      Serial.printf(
          "[BLE] Starting security; known_bond=%s pairing_open=%s bonds=%u\n",
          knownBond ? "yes" : "no", pairingOpen() ? "yes" : "no",
          static_cast<unsigned>(NimBLEDevice::getNumBonds()));
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
      Serial.println("[BLE] Authentication failed");
      connected = false;
      if (description != nullptr) {
        server->disconnect(description->conn_handle);
      }
      return;
    }
    firstPairingPending = false;
    Serial.printf("[BLE] Authentication complete; bonds=%u\n",
                  static_cast<unsigned>(NimBLEDevice::getNumBonds()));
  }
};

class ConfigCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic) override {
    const std::string value = characteristic->getValue();

    if (value.size() == device_name::kPacketLength) {
      device_name::Value candidate;
      const auto result = device_name::decode(
          reinterpret_cast<const uint8_t*>(value.data()), value.size(),
          candidate);
      config_packet::Bytes readback{};
      portENTER_CRITICAL(&pendingMutex);
      readback = currentPacket;
      portEXIT_CRITICAL(&pendingMutex);
      characteristic->setValue(readback.data(), readback.size());
      if (result != device_name::ValidationResult::kValid) {
        return;
      }
      portENTER_CRITICAL(&pendingMutex);
      if (candidate.length == 0) {
        hasNameReadRequest = true;
      } else {
        pendingName = candidate;
        hasPendingName = true;
      }
      portEXIT_CRITICAL(&pendingMutex);
      return;
    }

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

class NameCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic) override {
    const std::string value = characteristic->getValue();
    device_name::Value candidate;
    const auto result = device_name::decode(
        reinterpret_cast<const uint8_t*>(value.data()), value.size(),
        candidate);

    device_name::Value readback;
    portENTER_CRITICAL(&pendingMutex);
    readback = currentName;
    portEXIT_CRITICAL(&pendingMutex);
    const auto readbackPacket = device_name::encode(readback);
    characteristic->setValue(readbackPacket.data(), readbackPacket.size());
    if (result != device_name::ValidationResult::kValid ||
        candidate.length == 0) {
      return;
    }

    portENTER_CRITICAL(&pendingMutex);
    pendingName = candidate;
    hasPendingName = true;
    portEXIT_CRITICAL(&pendingMutex);
  }
};

ServerCallbacks serverCallbacks;
ConfigCallbacks configCallbacks;
NameCallbacks nameCallbacks;

}  // namespace

void begin(const config_packet::Bytes& appliedPacket,
           const device_name::Value& appliedName) {
  currentPacket = appliedPacket;
  currentName = appliedName;
  const std::string name = advertisedName(currentName);

  NimBLEDevice::init(name);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  NimBLEDevice::setSecurityAuth(true, false, true);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
  firstPairingPending = NimBLEDevice::getNumBonds() == 0;

  server = NimBLEDevice::createServer();
  server->setCallbacks(&serverCallbacks);
  NimBLEService* service = server->createService(kServiceUuid);
  configCharacteristic = service->createCharacteristic(
      kConfigUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE |
                       NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::NOTIFY);
  statusCharacteristic = service->createCharacteristic(
      kStatusUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  nameCharacteristic = service->createCharacteristic(
      kNameUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE |
                     NIMBLE_PROPERTY::READ_ENC |
                     NIMBLE_PROPERTY::WRITE_ENC |
                     NIMBLE_PROPERTY::NOTIFY);
  configCharacteristic->setCallbacks(&configCallbacks);
  nameCharacteristic->setCallbacks(&nameCallbacks);
  configCharacteristic->setValue(currentPacket.data(), currentPacket.size());
  const auto initialNamePacket = device_name::encode(currentName);
  nameCharacteristic->setValue(initialNamePacket.data(),
                               initialNamePacket.size());
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
  NimBLEAdvertisementData advertisementData;
  advertisementData.setFlags(BLE_HS_ADV_F_DISC_GEN |
                             BLE_HS_ADV_F_BREDR_UNSUP);
  advertisementData.setCompleteServices(NimBLEUUID(kServiceUuid));
  advertisementData.setPreferredParams(kFastAdvertisingMinInterval,
                                       kFastAdvertisingMaxInterval);
  NimBLEAdvertisementData scanResponseData;
  scanResponseData.setName(name);
  advertising->setAdvertisementData(advertisementData);
  advertising->setScanResponseData(scanResponseData);
  advertising->setScanResponse(true);
  setAdvertisingIntervals(false);
  advertisingStartMs = millis();
  const bool started = advertising->start();
  Serial.printf(
      "[BLE] Advertising start=%s name=%s service=%s bonds=%u "
      "first_pairing_open=%s\n",
      started ? "yes" : "no", name.c_str(), kServiceUuid,
      static_cast<unsigned>(NimBLEDevice::getNumBonds()),
      pairingOpen() ? "yes" : "no");
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

bool takePendingName(device_name::Value& name) {
  bool available = false;
  portENTER_CRITICAL(&pendingMutex);
  if (hasPendingName) {
    name = pendingName;
    hasPendingName = false;
    available = true;
  }
  portEXIT_CRITICAL(&pendingMutex);
  return available;
}

bool takeNameReadRequest() {
  bool requested = false;
  portENTER_CRITICAL(&pendingMutex);
  if (hasNameReadRequest) {
    hasNameReadRequest = false;
    requested = true;
  }
  portEXIT_CRITICAL(&pendingMutex);
  return requested;
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

void acknowledgeName(const device_name::Value& appliedName) {
  portENTER_CRITICAL(&pendingMutex);
  currentName = appliedName;
  portEXIT_CRITICAL(&pendingMutex);
  const auto packet = device_name::encode(currentName);
  updateAdvertisedName(currentName);
  notifyName(currentName);
}

void notifyName(const device_name::Value& appliedName) {
  const auto packet = device_name::encode(appliedName);
  nameCharacteristic->setValue(packet.data(), packet.size());
  nameCharacteristic->notify();
  configCharacteristic->setValue(packet.data(), packet.size());
  configCharacteristic->notify();
  config_packet::Bytes readback{};
  portENTER_CRITICAL(&pendingMutex);
  readback = currentPacket;
  portEXIT_CRITICAL(&pendingMutex);
  configCharacteristic->setValue(readback.data(), readback.size());
}

void setStatus(const Status& status) {
  const auto packet = encodeStatus(status);
  const uint32_t nowMs = millis();
  if (haveStatus) {
    const bool controlIsUnchanged =
        std::equal(packet.begin(), packet.begin() + 12,
                   lastStatusPacket.begin());
    if (controlIsUnchanged) {
      const bool measurementIsUnchanged =
          std::equal(packet.begin() + 12, packet.end(),
                     lastStatusPacket.begin() + 12);
      const uint32_t minimumInterval =
          measurementIsUnchanged ? kStatusHeartbeatMs
                                 : kLiveStatusIntervalMs;
      if (nowMs - lastStatusSentMs < minimumInterval) {
        return;
      }
    }
  }
  lastStatusPacket = packet;
  haveStatus = true;
  lastStatusSentMs = nowMs;
  statusCharacteristic->setValue(packet.data(), packet.size());
  statusCharacteristic->notify();
}

}  // namespace ble_service
