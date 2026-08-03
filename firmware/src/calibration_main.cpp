#include <Arduino.h>

#include "alarm_output.h"
#include "audio_input.h"
#include "calibration_session.h"

namespace {

AudioInput audioInput;
CalibrationSession calibration;

AlarmLevel alarmLevelForTarget(char target) {
  if (target == 'g') {
    return AlarmLevel::kGreen;
  }
  if (target == 'o') {
    return AlarmLevel::kOrange;
  }
  return AlarmLevel::kRed;
}

const char* targetName(char target) {
  if (target == 'g') {
    return "green";
  }
  if (target == 'o') {
    return "orange";
  }
  return "red";
}

void failMicrophone() {
  Serial.println("ERROR: I2S microphone start failed");
  while (true) {
    alarm_output::showMicrophoneError(true);
    delay(250);
    alarm_output::showMicrophoneError(false);
    delay(250);
  }
}

void startTarget(char target) {
  alarm_output::showCalibrationTarget(alarmLevelForTarget(target));
  calibration.start(target, millis());
  Serial.printf("START %s: make the target sound for 10 seconds\n",
                targetName(target));
}

void readCommand() {
  while (Serial.available() > 0) {
    char command = static_cast<char>(Serial.read());
    if (command >= 'A' && command <= 'Z') {
      command = static_cast<char>(command - 'A' + 'a');
    }
    if (command == 'g' || command == 'o' || command == 'r') {
      startTarget(command);
    } else if (command == 'x') {
      calibration.cancel();
      alarm_output::off();
      Serial.println("CANCELLED");
    }
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(300);

  alarm_output::begin();
  alarm_output::off();
  if (!audioInput.start()) {
    failMicrophone();
  }

  Serial.println("ESPNoise calibration ready");
  Serial.println("Send g, o, or r to measure that level. Send x to cancel.");
  Serial.println("Each result uses one 10-second sample.");
  Serial.println("The result is the median of its ten one-second maxima.");
}

void loop() {
  readCommand();

  float dbfs = -120.0F;
  if (audioInput.readFrame(dbfs)) {
    calibration.addFrame(dbfs);
  }

  if (!calibration.update(millis())) {
    return;
  }

  Serial.printf("SAMPLE %s %u/%u max=%.1f dBFS\n",
                targetName(calibration.target()),
                static_cast<unsigned>(calibration.completedSecondCount()),
                static_cast<unsigned>(CalibrationSession::kSecondCount),
                calibration.lastSecondMaximumDbfs());

  if (calibration.complete()) {
    alarm_output::off();
    Serial.printf(
        "RESULT %s median=%.1f dBFS range=%.1f..%.1f dBFS\n",
        targetName(calibration.target()), calibration.medianDbfs(),
        calibration.minimumDbfs(), calibration.maximumDbfs());
    Serial.println("READY");
  }
}
