#include <unity.h>

#include "ble_service.h"
#include "config_packet.h"
#include "device_name.h"
#include "mute_state.h"
#include "noise_detector.h"
#include "noise_analytics.h"

namespace {

void testPacketLayoutAndDecode() {
  RuntimeSettings settings;
  settings.ledBrightnessPercent = 25;
  settings.buzzerVolumePercent = 75;
  const auto packet = config_packet::encode(settings, 0x78563412UL);

  constexpr uint8_t expected[] = {
      0x01, 0x00, 0x19, 0x4B, 0xDA, 0xFD, 0x20, 0xFE,
      0x5C, 0xFE, 0xE8, 0x03, 0x00, 0x00, 0x10, 0x27,
      0x00, 0x00, 0x60, 0xEA, 0x00, 0x00, 0x32, 0x00,
      0x08, 0x07, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78,
  };
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, packet.data(), packet.size());

  TEST_ASSERT_EQUAL_UINT8(1, packet[0]);
  TEST_ASSERT_EQUAL_UINT8(0, packet[1]);
  TEST_ASSERT_EQUAL_UINT8(25, packet[2]);
  TEST_ASSERT_EQUAL_UINT8(75, packet[3]);
  TEST_ASSERT_EQUAL_UINT8(0x12, packet[28]);
  TEST_ASSERT_EQUAL_UINT8(0x34, packet[29]);
  TEST_ASSERT_EQUAL_UINT8(0x56, packet[30]);
  TEST_ASSERT_EQUAL_UINT8(0x78, packet[31]);

  RuntimeSettings decoded;
  uint32_t revision = 0;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(config_packet::ValidationResult::kValid),
      static_cast<int>(config_packet::decode(packet.data(), packet.size(),
                                              decoded, revision)));
  TEST_ASSERT_EQUAL_UINT32(0x78563412UL, revision);
  TEST_ASSERT_EQUAL_INT16(settings.greenThresholdDbfsX10,
                          decoded.greenThresholdDbfsX10);
  TEST_ASSERT_EQUAL_UINT32(settings.decisionWindowMs,
                           decoded.decisionWindowMs);
}

void testFingerprintDoesNotIncludeRevision() {
  constexpr uint8_t hello[] = {'h', 'e', 'l', 'l', 'o'};
  TEST_ASSERT_EQUAL_HEX32(0x4F9F2CABUL,
                          config_packet::fingerprint(hello, sizeof(hello)));

  RuntimeSettings settings;
  const auto first = config_packet::encode(settings, 1);
  const auto second = config_packet::encode(settings, 2);
  TEST_ASSERT_EQUAL_HEX32(config_packet::fingerprint(first),
                          config_packet::fingerprint(second));
  TEST_ASSERT_TRUE(config_packet::effectiveDataEqual(first, second));

  auto changed = second;
  changed[2] = 20;
  TEST_ASSERT_FALSE(config_packet::effectiveDataEqual(first, changed));
}

void testStatusPacketLayout() {
  ble_service::Status status;
  status.alarmState = 2;
  status.muted = true;
  status.sampling = true;
  status.alarmActive = false;
  status.errorCode = 4;
  status.appliedRevision = 0x12345678UL;
  status.fingerprint = 0x90ABCDEFUL;
  status.measurementValid = true;
  status.observationMaximumDbfsX10 = -480;
  status.measurementSequence = 0x1234;
  status.historyCount = 6;
  status.greenSampleCount = 4;
  status.orangeSampleCount = 3;
  status.redSampleCount = 1;

  const auto packet = ble_service::encodeStatus(status);
  constexpr uint8_t expected[] = {
      0x02, 0x02, 0x0B, 0x04, 0x78, 0x56, 0x34, 0x12,
      0xEF, 0xCD, 0xAB, 0x90, 0x20, 0xFE, 0x34, 0x12,
      0x06, 0x04, 0x03, 0x01,
  };
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, packet.data(), packet.size());

  status.measurementValid = false;
  const auto invalidMeasurement = ble_service::encodeStatus(status);
  TEST_ASSERT_EQUAL_HEX8(0x03, invalidMeasurement[2]);
}

void testDeviceNamePacketValidation() {
  device_name::Packet query{};
  query[0] = 1;
  device_name::Value decoded;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(device_name::ValidationResult::kValid),
      static_cast<int>(device_name::decode(
          query.data(), query.size(), decoded)));
  TEST_ASSERT_EQUAL_UINT8(0, decoded.length);

  device_name::Value name;
  constexpr uint8_t office[] = {'O', 'f', 'f', 'i', 'c', 'e'};
  name.length = sizeof(office);
  std::copy(office, office + sizeof(office), name.bytes.begin());
  const auto packet = device_name::encode(name);
  TEST_ASSERT_EQUAL_UINT8(1, packet[0]);
  TEST_ASSERT_EQUAL_UINT8(6, packet[1]);

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(device_name::ValidationResult::kValid),
      static_cast<int>(device_name::decode(
          packet.data(), packet.size(), decoded)));
  TEST_ASSERT_TRUE(name == decoded);

  auto invalid = packet;
  invalid[2] = 0x07;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(device_name::ValidationResult::kBadUtf8),
      static_cast<int>(device_name::decode(
          invalid.data(), invalid.size(), decoded)));

  invalid = packet;
  invalid[19] = 1;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(device_name::ValidationResult::kBadPadding),
      static_cast<int>(device_name::decode(
          invalid.data(), invalid.size(), decoded)));

  device_name::Packet accented{};
  accented[0] = 1;
  accented[1] = 3;
  accented[2] = 'C';
  accented[3] = 0xC3;
  accented[4] = 0xA9;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(device_name::ValidationResult::kValid),
      static_cast<int>(device_name::decode(
          accented.data(), accented.size(), decoded)));
}

config_packet::ValidationResult decodeResult(
    const config_packet::Bytes& packet) {
  RuntimeSettings settings;
  uint32_t revision = 0;
  return config_packet::decode(packet.data(), packet.size(), settings,
                               revision);
}

void testLimitsRejectInvalidRelatedValues() {
  RuntimeSettings settings;

  settings.ledBrightnessPercent = 101;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(config_packet::ValidationResult::kBadBrightness),
      static_cast<int>(decodeResult(config_packet::encode(settings, 0))));

  settings = RuntimeSettings{};
  settings.orangeThresholdDbfsX10 = settings.greenThresholdDbfsX10;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(config_packet::ValidationResult::kBadThresholds),
      static_cast<int>(decodeResult(config_packet::encode(settings, 0))));

  settings = RuntimeSettings{};
  settings.decisionWindowMs = settings.samplePeriodMs + 1;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(config_packet::ValidationResult::kBadSampleTiming),
      static_cast<int>(decodeResult(config_packet::encode(settings, 0))));

  settings = RuntimeSettings{};
  settings.samplePeriodMs = 1;
  settings.sampleDurationMs = 1;
  settings.decisionWindowMs =
      static_cast<uint32_t>(config::kMaximumHistorySampleCount + 1);
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(
          config_packet::ValidationResult::kTooManyHistorySamples),
      static_cast<int>(decodeResult(config_packet::encode(settings, 0))));

  settings = RuntimeSettings{};
  settings.sampleDurationMs = 1000;
  settings.samplePeriodMs = 1000;
  settings.decisionWindowMs = 1000;
  settings.triggerSamplePercent = 50;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(
          config_packet::ValidationResult::kTooFewRequiredSamples),
      static_cast<int>(decodeResult(config_packet::encode(settings, 0))));
}

void addSample(NoiseDetector& detector, float dbfs) {
  detector.beginSample();
  detector.addFrame(dbfs);
  detector.commitSample();
}

void testDetectorUsesInclusiveTriggerPercent() {
  RuntimeSettings settings;
  settings.sampleDurationMs = 1000;
  settings.samplePeriodMs = 1000;
  settings.decisionWindowMs = 6000;
  settings.triggerSamplePercent = 50;
  NoiseDetector detector;
  detector.setSettings(settings);

  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);
  TEST_ASSERT_EQUAL_UINT(3, detector.greenSampleCount());
  TEST_ASSERT_EQUAL_UINT(0, detector.orangeSampleCount());
  TEST_ASSERT_EQUAL_UINT(0, detector.redSampleCount());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));

  addSample(detector, -60.0F);
  TEST_ASSERT_EQUAL_UINT(2, detector.greenSampleCount());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kQuiet),
                        static_cast<int>(detector.historyAlarmLevel()));

  settings.greenThresholdDbfsX10 = -500;
  detector.setSettings(settings);
  addSample(detector, -54.0F);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kQuiet),
                        static_cast<int>(detector.sampleLevel()));
  TEST_ASSERT_EQUAL_UINT(1, detector.historyCount());
}

void testDetectorUsesDynamicWindowAndInclusivePercent() {
  RuntimeSettings settings;
  settings.sampleDurationMs = 1000;
  settings.samplePeriodMs = 1000;
  settings.decisionWindowMs = 4000;
  settings.triggerSamplePercent = 50;
  NoiseDetector detector;
  detector.setSettings(settings);

  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);
  TEST_ASSERT_EQUAL_UINT(2, detector.greenSampleCount());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));

  addSample(detector, -60.0F);
  TEST_ASSERT_EQUAL_UINT(1, detector.greenSampleCount());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kQuiet),
                        static_cast<int>(detector.historyAlarmLevel()));
}

void testMuteDoublePressEndsMute() {
  MuteState mute;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(MutePressResult::kMuted),
      static_cast<int>(mute.press(1000, 60)));
  TEST_ASSERT_TRUE(mute.isMuted(1000));

  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(MutePressResult::kUnmuted),
      static_cast<int>(mute.press(1500, 60)));
  TEST_ASSERT_FALSE(mute.isMuted(1500));
}

void testMuteDoublePressIncludesWindowBoundary() {
  MuteState mute;
  mute.press(1000, 60);
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(MutePressResult::kUnmuted),
      static_cast<int>(mute.press(
          1000 + config::kMuteDoublePressWindowMs, 60)));
}

void testSinglePressRestartsActiveMute() {
  MuteState mute;
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(MutePressResult::kMuted),
      static_cast<int>(mute.press(1000, 60)));
  TEST_ASSERT_EQUAL_INT(
      static_cast<int>(MutePressResult::kMuteExtended),
      static_cast<int>(mute.press(2000, 60)));
  TEST_ASSERT_TRUE(mute.isMuted(61000));
  TEST_ASSERT_TRUE(mute.update(62000));
  TEST_ASSERT_FALSE(mute.isMuted(62000));
  TEST_ASSERT_FALSE(mute.update(62001));
}

void testMuteTimerWorksAcrossMillisWrap() {
  MuteState mute;
  constexpr uint32_t start = UINT32_MAX - 100;
  mute.press(start, 60);
  TEST_ASSERT_TRUE(mute.isMuted(UINT32_MAX - 50));
  TEST_ASSERT_TRUE(mute.isMuted(59000));
  TEST_ASSERT_TRUE(mute.update(59900));
  TEST_ASSERT_FALSE(mute.isMuted(59900));

  MuteState zeroEnd;
  constexpr uint32_t zeroEndStart = UINT32_MAX - 59999;
  zeroEnd.press(zeroEndStart, 60);
  TEST_ASSERT_TRUE(zeroEnd.isMuted(zeroEndStart));
  TEST_ASSERT_TRUE(zeroEnd.update(0));
  TEST_ASSERT_FALSE(zeroEnd.isMuted(0));
}

void testRollingCountsControlEveryLevelChange() {
  RuntimeSettings settings;
  settings.sampleDurationMs = 1000;
  settings.samplePeriodMs = 1000;
  settings.decisionWindowMs = 6000;
  settings.triggerSamplePercent = 50;
  NoiseDetector detector;
  detector.setSettings(settings);

  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));

  addSample(detector, -40.0F);
  TEST_ASSERT_EQUAL_UINT(3, detector.greenSampleCount());
  TEST_ASSERT_EQUAL_UINT(1, detector.orangeSampleCount());
  TEST_ASSERT_EQUAL_UINT(1, detector.redSampleCount());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));

  addSample(detector, -40.0F);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));
  addSample(detector, -40.0F);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kRed),
                        static_cast<int>(detector.historyAlarmLevel()));
}

void testMixedThresholdObservationsSelectGreen() {
  RuntimeSettings settings;
  settings.sampleDurationMs = 1000;
  settings.samplePeriodMs = 1000;
  settings.decisionWindowMs = 6000;
  settings.triggerSamplePercent = 50;
  NoiseDetector detector;
  detector.setSettings(settings);

  addSample(detector, -54.0F);
  addSample(detector, -47.0F);
  addSample(detector, -40.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);
  addSample(detector, -60.0F);

  TEST_ASSERT_EQUAL_UINT(3, detector.greenSampleCount());
  TEST_ASSERT_EQUAL_UINT(2, detector.orangeSampleCount());
  TEST_ASSERT_EQUAL_UINT(1, detector.redSampleCount());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));
}

uint16_t packet16(const noise_analytics::Packet& packet, size_t offset) {
  return static_cast<uint16_t>(packet[offset]) |
         static_cast<uint16_t>(packet[offset + 1]) << 8;
}

uint32_t packet32(const noise_analytics::Packet& packet, size_t offset) {
  uint32_t value = 0;
  for (size_t index = 0; index < 4; ++index) {
    value |= static_cast<uint32_t>(packet[offset + index]) << (index * 8);
  }
  return value;
}

void testAnalyticsMakesPrivateFifteenMinuteSummary() {
  noise_analytics::History history;
  constexpr uint32_t startUtc = 1700000000UL;
  TEST_ASSERT_TRUE(history.syncUtcTime(startUtc));
  for (uint16_t second = 0;
       second < noise_analytics::kBucketDurationSeconds; ++second) {
    const AlarmLevel level = second < 300
                                 ? AlarmLevel::kGreen
                                 : (second < 420 ? AlarmLevel::kOrange
                                                 : AlarmLevel::kQuiet);
    history.addSecond(level, second == 10 ? -300 : -600, true);
  }

  TEST_ASSERT_EQUAL_UINT(1, history.recordCount());
  noise_analytics::Bucket bucket;
  TEST_ASSERT_TRUE(history.recordAt(0, bucket));
  TEST_ASSERT_EQUAL_UINT32(1, bucket.sequence);
  TEST_ASSERT_EQUAL_UINT32(startUtc, bucket.startUtcSeconds);
  TEST_ASSERT_EQUAL_UINT16(900, bucket.durationSeconds);
  TEST_ASSERT_EQUAL_UINT16(900, bucket.peakPositiveLevelX10);
  TEST_ASSERT_EQUAL_UINT16(300, bucket.greenSeconds);
  TEST_ASSERT_EQUAL_UINT16(120, bucket.orangeSeconds);
  TEST_ASSERT_EQUAL_UINT16(0, bucket.redSeconds);

  const auto packet = history.packetFor(bucket);
  TEST_ASSERT_EQUAL_UINT8(2, packet[0]);
  TEST_ASSERT_EQUAL_UINT8(0, packet[1]);
  TEST_ASSERT_EQUAL_UINT32(1, packet32(packet, 2));
  TEST_ASSERT_EQUAL_UINT32(startUtc, packet32(packet, 6));
  TEST_ASSERT_EQUAL_UINT16(900, packet16(packet, 10));
  TEST_ASSERT_EQUAL_UINT8(60, packet[16]);
  TEST_ASSERT_EQUAL_UINT8(24, packet[17]);
}

void testAnalyticsStorageRoundTripsAndRejectsDamage() {
  noise_analytics::History source;
  TEST_ASSERT_TRUE(source.syncUtcTime(1700000000UL));
  for (uint16_t second = 0;
       second < noise_analytics::kBucketDurationSeconds; ++second) {
    source.addSecond(AlarmLevel::kRed, -400, true);
  }
  noise_analytics::Storage storage{};
  const size_t length = source.encodeStorage(storage);

  noise_analytics::History restored;
  TEST_ASSERT_TRUE(restored.decodeStorage(storage.data(), length));
  TEST_ASSERT_EQUAL_UINT(1, restored.recordCount());
  TEST_ASSERT_EQUAL_UINT32(2, restored.currentSequence());
  TEST_ASSERT_TRUE(restored.restoreCurrentSequence(9));
  TEST_ASSERT_EQUAL_UINT32(9, restored.currentSequence());
  TEST_ASSERT_FALSE(restored.restoreCurrentSequence(1));
  noise_analytics::Bucket bucket;
  TEST_ASSERT_TRUE(restored.recordAt(0, bucket));
  TEST_ASSERT_EQUAL_UINT32(1700000000UL, bucket.startUtcSeconds);
  TEST_ASSERT_EQUAL_UINT16(900, bucket.redSeconds);

  storage[0] = 0;
  TEST_ASSERT_FALSE(restored.decodeStorage(storage.data(), length));
}

void testAnalyticsRequestAndSequenceRules() {
  constexpr uint8_t request[] = {
      2, 1, 0x78, 0x56, 0x34, 0x12,
      0x00, 0xF1, 0x53, 0x65, 0, 0};
  uint32_t after = 0;
  uint32_t utc = 0;
  TEST_ASSERT_TRUE(noise_analytics::History::decodeRequest(
      request, sizeof(request), after, utc));
  TEST_ASSERT_EQUAL_HEX32(0x12345678UL, after);
  TEST_ASSERT_EQUAL_UINT32(1700000000UL, utc);
  TEST_ASSERT_TRUE(noise_analytics::History::sequenceIsAfter(10, 9));
  TEST_ASSERT_FALSE(noise_analytics::History::sequenceIsAfter(9, 10));
  TEST_ASSERT_TRUE(noise_analytics::History::sequenceIsAfter(1, UINT32_MAX));
}

void testAnalyticsUtcSyncBackfillsOnlyNewRecords() {
  noise_analytics::History history;
  for (uint16_t second = 0;
       second < noise_analytics::kBucketDurationSeconds + 60; ++second) {
    history.addSecond(AlarmLevel::kQuiet, -600, true);
  }
  constexpr uint32_t nowUtc = 1700000960UL;
  TEST_ASSERT_TRUE(history.syncUtcTime(nowUtc));

  noise_analytics::Bucket completed;
  TEST_ASSERT_TRUE(history.recordAt(0, completed));
  TEST_ASSERT_EQUAL_UINT32(1700000000UL, completed.startUtcSeconds);
  const auto current = history.currentPacket();
  TEST_ASSERT_EQUAL_UINT32(1700000900UL, packet32(current, 6));
  TEST_ASSERT_EQUAL_UINT16(60, packet16(current, 10));
}

}  // namespace

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;
  UNITY_BEGIN();
  RUN_TEST(testPacketLayoutAndDecode);
  RUN_TEST(testFingerprintDoesNotIncludeRevision);
  RUN_TEST(testStatusPacketLayout);
  RUN_TEST(testDeviceNamePacketValidation);
  RUN_TEST(testLimitsRejectInvalidRelatedValues);
  RUN_TEST(testDetectorUsesInclusiveTriggerPercent);
  RUN_TEST(testDetectorUsesDynamicWindowAndInclusivePercent);
  RUN_TEST(testMuteDoublePressEndsMute);
  RUN_TEST(testMuteDoublePressIncludesWindowBoundary);
  RUN_TEST(testSinglePressRestartsActiveMute);
  RUN_TEST(testMuteTimerWorksAcrossMillisWrap);
  RUN_TEST(testRollingCountsControlEveryLevelChange);
  RUN_TEST(testMixedThresholdObservationsSelectGreen);
  RUN_TEST(testAnalyticsMakesPrivateFifteenMinuteSummary);
  RUN_TEST(testAnalyticsStorageRoundTripsAndRejectsDamage);
  RUN_TEST(testAnalyticsRequestAndSequenceRules);
  RUN_TEST(testAnalyticsUtcSyncBackfillsOnlyNewRecords);
  return UNITY_END();
}
