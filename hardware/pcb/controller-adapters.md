# Controller adapter cables

J2 is a controller-independent signal connector. The carrier PCB does not
contain an ESP32. Use one adapter cable between J2 and the selected development
board.

The cable housing is JST `PHR-10`. Use JST `SPH-002T-P0.5S` crimp terminals or
an approved equivalent. Mark pin 1 before you install the cable.

## J2 signal order

| J2 pin | Signal | Full-size ESP32 adapter | ESP32-C3 SuperMini adapter |
| ---: | --- | --- | --- |
| 1 | `+5V_IN` | `5V` or `VIN` | `5V` |
| 2 | `GND` | `GND` | `GND` |
| 3 | `+3V3` | `3V3` | `3V3` |
| 4 | `MIC_SCK` | GPIO26 | GPIO4 |
| 5 | `MIC_WS` | GPIO25 | GPIO5 |
| 6 | `MIC_SD` | GPIO32 | GPIO6 |
| 7 | `LED_DATA_3V3` | GPIO18 | GPIO7 |
| 8 | `BUZZER_PWM` | GPIO23 | GPIO3 |
| 9 | `MUTE_N` | GPIO27 | GPIO10 |
| 10 | `GND` | `GND` | `GND` |

Use two controller GND pins when the board has them. If the board has only one
convenient GND pin, make the GND split in the adapter cable. Do not omit either
J2 ground wire.

The current firmware supports the full-size ESP32 pin map. It does not yet
include an ESP32-C3 build environment. The C3 column is the reserved adapter
map for a future firmware port. Do not connect a C3 and expect the current
`esp32dev` binary to operate.

Do not connect external 5 V power and the controller service USB port at the
same time. Disconnect J1 before you connect the service USB cable.

## Other PCB connectors

| Connector | Cable housing | Pin order |
| --- | --- | --- |
| J1, power input | JST `PHR-2` | 1 `+5V_IN`, 2 `GND` |
| J3, LED strip | JST `PHR-5` | 1 `+5V` first end, 2 `GND` first end, 3 `DIN`, 4 `+5V` far end, 5 `GND` far end |
| J4, microphone | JST `PHR-6` | 1 `3V3`, 2 `GND`, 3 `SCK`, 4 `WS`, 5 `SD`, 6 `L/R` to GND |
| J5, buzzer | JST `PHR-2` | 1 switched `+5V`, 2 transistor collector |

J1, J2, J3, J4, and J5 are mounted on the lower PCB face. Their cable entry
direction is away from that face. Thus, the installed cables point down.

The J3 cable divides power and ground between the two strip ends. Connect pin
3 only to the first pixel `DIN`. Do not connect it to the far strip end.
