# Bill of materials

This bill of materials is for one USB-powered production unit. Match the
written part specification. Seller names and listing titles can be incorrect.

## Controller and display

| Qty | Part | Required specification |
| ---: | --- | --- |
| 1 | ESP32 development board | Full-size ESP32, USB-C service port, `esp32dev` PlatformIO support |
| 1 | Digital microphone | INMP441 I2S module, 3.3 V |
| 10 | Addressable pixels | SK6812 RGB plus warm-white, 5 V, 32-bit data; normally cut from a 60-pixel/m strip |
| 1 | Data buffer | SN74AHCT125N, DIP-14; the part number must include `AHCT` |
| 1 | Data resistor | 330 ohm, 0.25 W |
| 1 | Buffer bypass capacitor | 100 nF ceramic, 50 V |
| 1 | LED rail capacitor | 1,000 uF, 10 V or 16 V, 105 degrees C |

Ten pixels from a 60-pixel/m strip have a nominal length of 166.7 mm. Cut only
at a marked cut line. Keep the data arrows in the direction from `DIN` to
`DOUT`.

## Controls and sound

| Qty | Part | Required specification |
| ---: | --- | --- |
| 1 | Mute button | Momentary, normally open |
| 1 | Buzzer switch | Maintained SPST switch; install it in the buzzer 5 V wire |
| 1 | Buzzer | Passive piezo buzzer, suitable for the tested 2.4 kHz drive |
| 1 | Driver transistor | 2N3904 NPN |
| 1 | Base resistor | 5.1 kohm, 0.25 W or higher |

The buzzer switch is a hard power cut. Do not replace it with a software-only
control. Confirm the transistor pin order for the purchased part before you
solder it.

## Power

| Qty | Part | Required specification |
| ---: | --- | --- |
| 1 | Wall supply | Regulated 5 V, 2 A minimum; 5 V, 3 A recommended; approved for the country of use |
| 1 | External power cable | USB-C to USB-C, rated for at least 3 A |
| 1 | External power socket | Power-only USB-C input with one 5.1 kohm CC pull-down on CC1 and one on CC2 |
| 1 | Service cable | USB data cable for firmware upload through the ESP32 port |
| 1 | Removable power connector | Two pins, 5 V and GND, rated for at least 2 A |
| 1 | Resettable fuse | MF-R050 or equivalent, 0.50 A hold |

Keep the external power input separate from the ESP32 service port. Do not
combine CC1 and CC2. Disconnect the external power connector before you attach
the ESP32 service cable to a computer.

A supply rated for 3 A does not force 3 A through the circuit. The circuit
takes the current that it needs. Do not use a 6 V to 30 V buck converter in
this 5 V build.

## Assembly

| Qty | Part | Required specification |
| ---: | --- | --- |
| 1 | Prototype board or PCB | Sufficient space for the buffer, driver, fuse, and connectors |
| As needed | Module connectors | Keyed connectors, with different pin counts where practical |
| As needed | Power wire | 22 AWG stranded copper, red and black |
| As needed | Signal wire | 26 AWG stranded copper, multiple colors |
| As needed | Heat-shrink tube | 2:1 ratio, sizes that fit the joints |

The modular build guide specifies the recommended connector pin counts.

## Optional battery build

The battery build is not necessary for the production enclosure. Do not add it
until the USB-powered unit is stable and its current is measured.

| Qty | Part | Required specification |
| ---: | --- | --- |
| 1 | Controller | WEMOS LOLIN32 Lite V1.0.0 with its on-board charger |
| 1 | Battery pack | One protected 3.7 V LiPo pack with built-in protection and the correct connector polarity |
| 1 | Boost module | TPS61023, 5.2 V output, with an accessible enable input |
| 1 | Enable resistor | 100 ohm, 0.25 W |
| 1 | Enable pull-down | 100 kohm, 0.25 W |

Use a complete protected pack. Do not use a raw pouch cell or loose 18650 or
21700 cells. Confirm the connector polarity with a multimeter before you
connect the pack. The battery-build 5 V boost must stay off when there is no
alarm.

## Tools

- Soldering iron with a small tip
- Multimeter
- USB power meter
- Wire cutter and wire stripper
- Heat gun for heat-shrink tube
- Sound level meter for dBA calibration
- Caliper for part and enclosure checks

## Technical sources

- [ESP32-DevKitC documentation](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html)
- [INMP441 data sheet](https://invensense.tdk.com/wp-content/uploads/2015/02/INMP441.pdf)
- [SN74AHCT125 data sheet](https://www.ti.com/lit/gpn/SN74AHCT125)
- [SK6812 RGBW data sheet](https://cdn-shop.adafruit.com/product-files/2757/p2757_SK6812RGBW_REV01.pdf)
- [TPS61023 data](https://www.ti.com/product/TPS61023)
- [LiPo protection guidance](https://learn.adafruit.com/li-ion-and-lipoly-batteries/protection-circuitry)
- [CPSC loose-cell warning](https://www.cpsc.gov/Newsroom/News-Releases/2021/CPSC-Issues-Consumer-Safety-Warning-Serious-Injury-or-Death-Can-Occur-if-Lithium-Ion-Battery-Cells-Are-Separated-from-Battery-Packs-and-Used-to-Power-Devices)
