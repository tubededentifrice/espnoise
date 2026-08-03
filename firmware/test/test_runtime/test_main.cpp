#include <unity.h>

#include "config_packet.h"
#include "noise_detector.h"

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

void testDetectorUsesDynamicWindowThresholdAndPercent() {
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
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kQuiet),
                        static_cast<int>(detector.historyAlarmLevel()));

  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  addSample(detector, -54.0F);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kGreen),
                        static_cast<int>(detector.historyAlarmLevel()));

  settings.greenThresholdDbfsX10 = -500;
  detector.setSettings(settings);
  addSample(detector, -54.0F);
  TEST_ASSERT_EQUAL_INT(static_cast<int>(AlarmLevel::kQuiet),
                        static_cast<int>(detector.sampleLevel()));
  TEST_ASSERT_EQUAL_UINT(1, detector.historyCount());
}

}  // namespace

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;
  UNITY_BEGIN();
  RUN_TEST(testPacketLayoutAndDecode);
  RUN_TEST(testFingerprintDoesNotIncludeRevision);
  RUN_TEST(testLimitsRejectInvalidRelatedValues);
  RUN_TEST(testDetectorUsesDynamicWindowThresholdAndPercent);
  return UNITY_END();
}
