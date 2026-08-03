# Agent instructions

- The product monitors noise in a coworking space. It warns participants when
  they are too loud for a sustained time, so they can lower their volume or
  move to another place. Do not make sporadic noise trigger the warning.
- Use ASD-STE100 Simplified Technical English in reports, documents, issues,
  pull requests, and comments.
- Keep battery safety statements clear. Do not recommend loose lithium cells
  for this project.
- Do not change the assigned GPIO pins without an update to `docs/wiring.md`
  and `firmware/include/config.h`.
- Keep the buzzer switch as a hard switch in the buzzer power wire.
- Keep the detector values K, N, X, and threshold in
  `firmware/include/config.h`.
- Keep Wi-Fi and Bluetooth off unless a task needs them.
- Do not save raw microphone audio.
- Keep the LED brightness limit at or below 25% until power tests show that a
  higher limit is safe.
- Keep both PlatformIO environments working: `esp32dev` and `lolin32_lite`.
- Keep `esp32dev` as the default environment until the USB-powered build is
  complete.
- Keep hardware access, sound detection, controls, and output code in separate
  firmware modules.
- Keep the external two-wire USB-C power input separate from the internal
  ESP32 firmware-service port.
- Do not combine USB-C CC1 and CC2. Use one 5.1 kohm pull-down on each pin.
- Keep the battery-build 5 V boost disabled when there is no alarm.
- Treat the installed strip as SK6812 RGB plus warm-white with 32-bit data.
- Run a firmware build after each firmware change when PlatformIO is
  available.
- Keep hardware assumptions in the documents. Do not put an unknown part size
  into a final case model.
