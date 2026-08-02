#include "audio_input.h"

#include <driver/i2s.h>

#include <cmath>

#include "board_profile.h"

namespace {

constexpr i2s_port_t kI2sPort = I2S_NUM_0;
constexpr double kMicFullScale = 8388608.0;  // 2^23 for signed 24-bit audio.

}  // namespace

bool AudioInput::start() {
  if (running_) {
    return true;
  }

  const i2s_config_t i2sConfig = {
      .mode = static_cast<i2s_mode_t>(I2S_MODE_MASTER | I2S_MODE_RX),
      .sample_rate = config::kSampleRateHz,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
      // Read both I2S slots. INMP441 modules can select either slot with the
      // L/R pin, and some board packages name the slots differently.
      .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
      .communication_format = I2S_COMM_FORMAT_STAND_I2S,
      .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
      .dma_buf_count = 8,
      .dma_buf_len = config::kAudioBlockSamples,
      .use_apll = false,
      .tx_desc_auto_clear = false,
      .fixed_mclk = 0,
  };

  const i2s_pin_config_t pinConfig = {
      .mck_io_num = I2S_PIN_NO_CHANGE,
      .bck_io_num = board_profile::kMicClockPin,
      .ws_io_num = board_profile::kMicWordSelectPin,
      .data_out_num = I2S_PIN_NO_CHANGE,
      .data_in_num = board_profile::kMicDataPin,
  };

  if (i2s_driver_install(kI2sPort, &i2sConfig, 0, nullptr) != ESP_OK) {
    return false;
  }
  if (i2s_set_pin(kI2sPort, &pinConfig) != ESP_OK) {
    i2s_driver_uninstall(kI2sPort);
    return false;
  }

  previousInput_[0] = 0.0;
  previousInput_[1] = 0.0;
  previousFiltered_[0] = 0.0;
  previousFiltered_[1] = 0.0;
  i2s_zero_dma_buffer(kI2sPort);
  running_ = true;
  return true;
}

void AudioInput::stop() {
  if (!running_) {
    return;
  }
  i2s_driver_uninstall(kI2sPort);
  running_ = false;
}

bool AudioInput::readFrame(float& dbfs) {
  if (!running_) {
    return false;
  }

  size_t bytesRead = 0;
  const esp_err_t result =
      i2s_read(kI2sPort, audioBlock_, sizeof(audioBlock_), &bytesRead,
               pdMS_TO_TICKS(25));
  if (result != ESP_OK || bytesRead == 0) {
    return false;
  }

  const size_t sampleCount = bytesRead / sizeof(audioBlock_[0]);
  double squareSum[2] = {0.0, 0.0};
  size_t channelSampleCount[2] = {0, 0};
  for (size_t index = 0; index < sampleCount; ++index) {
    const size_t channel = index & 1U;
    const double input = static_cast<double>(audioBlock_[index] >> 8);
    const double filtered =
        input - previousInput_[channel] +
        config::kDcBlockFactor * previousFiltered_[channel];
    previousInput_[channel] = input;
    previousFiltered_[channel] = filtered;
    squareSum[channel] += filtered * filtered;
    ++channelSampleCount[channel];
  }

  const double rms0 = channelSampleCount[0] == 0
                          ? 0.0
                          : std::sqrt(squareSum[0] / channelSampleCount[0]);
  const double rms1 = channelSampleCount[1] == 0
                          ? 0.0
                          : std::sqrt(squareSum[1] / channelSampleCount[1]);
  const double rms = rms0 > rms1 ? rms0 : rms1;
  dbfs = rms > 1.0
             ? static_cast<float>(20.0 * std::log10(rms / kMicFullScale))
             : -120.0F;
  return true;
}

bool AudioInput::isRunning() const { return running_; }
