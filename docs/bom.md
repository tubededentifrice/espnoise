# Bill of materials

The links and listing identifiers were checked on 2026-08-01. AliExpress can
change a listing or an option. Match the written specification before you buy.
The quantity is the quantity to order, not the seller pack quantity.

## Parts already available

- 1 full-size ESP32 development board with USB-C
- 1 WEMOS LOLIN32 Lite V1.0.0 with Micro-USB and a battery socket
- 1 MH-ET LIVE INMP441 I2S microphone module
- 1 roll of SK6812 RGB plus warm-white strip, 5 V, 60 pixels/m
- 1 USB-C data cable
- 1 tested passive piezo buzzer
- 1 2N3904 transistor
- 1 maintained SPST buzzer switch
- 1 momentary normally-open mute button
- 1 5.1 kohm, 1 W resistor for the 2N3904 base
- JST connectors

Cut 10 pixels, or approximately 167 mm, from the SK6812 strip. Cut only on a
marked cut line. Keep the arrows in the data direction from `DIN` to `DOUT`.

Do not use the 6 V to 30 V buck converters. They cannot operate from the
3.0 V to 4.2 V battery range.

## Buy now for the USB-powered first build

### Power parts

| Qty | Part | Exact selection | Purchase note |
| ---: | --- | --- | --- |
| 1 | Wall supply | Regulated 5 V, 2 A minimum; 5 V, 3 A recommended | Buy a known brand with the correct safety approval for your country. |
| 1 | Service USB cable | The data cable that currently operates the ESP32 | Use it only when the external power module is disconnected. |
| 1 | Power cable | USB-C to USB-C, rated for at least 3 A | Use it with the two-wire external power connector. |
| 1 | USB-C power socket, only if the available socket fails its test | Female socket with two built-in 5.1 kohm CC resistors | [Item 1005007348932368](https://www.aliexpress.com/item/1005007348932368.html) |
| 1 | Removable power plug | JST-XH-2 or equal, rated for at least 2 A | Disconnect it before firmware upload through the ESP32 USB port. |
| 1 | Resettable fuse | MF-R050 or equal, 0.50 A hold | Put it between the 5 V power split and the sign power connector. |
| 1 | Rail capacitor | 1,000 uF, 10 V or 16 V, 105 degrees C | Put it at the first LED power connection. |
| 1 | USB power meter | USB-C input and output, voltage and current display | Optional, but recommended for the first USB-C power test. |

No USB-C board-repair parts are necessary for the first build. The available
5.1 kohm, 1 W resistors are electrically suitable only if the two-wire
connector exposes separate CC1 and CC2 pads. Do not connect these resistors to
the red 5 V wire.

No buck converter, boost converter, battery charger, or battery is necessary
for the first build. A 3 A supply does not force 3 A into the circuit. The
circuit takes only the current that it needs.

Use one available two-wire USB-C connector for the external power input. It
does not carry firmware-upload data.

### Signal and assembly parts

| Qty | Part | Exact selection | AliExpress link |
| ---: | --- | --- | --- |
| 5 | Level buffer | SN74AHCT125N, DIP-14. The letters must include `AHCT`. | [Item 1005005469299469](https://www.aliexpress.com/item/1005005469299469.html) |
| 5 | Resettable fuse | MF-R050 or equal, 0.50 A hold, radial | [Search MF-R050](https://www.aliexpress.com/w/wholesale-MF-R050-resettable-fuse.html) |
| 5 | Large capacitor | 1,000 uF, 10 V or 16 V, 105 degrees C | [Search capacitor](https://www.aliexpress.com/w/wholesale-1000uF-10V-105C-electrolytic-capacitor.html) |
| 20 | Small capacitor | 100 nF, ceramic, 50 V, 2.54 mm lead space | [Search capacitor](https://www.aliexpress.com/w/wholesale-100nF-ceramic-capacitor-2.54mm.html) |
| 1 kit | Resistors | Must include 100 ohm, 330 ohm, and 100 kohm, 0.25 W | [Search resistor kit](https://www.aliexpress.com/w/wholesale-metal-film-resistor-kit-1-4W.html) |
| 2 | Prototype board | Double-side plated board, 5 cm by 7 cm, 2.54 mm pitch | [Search prototype board](https://www.aliexpress.com/w/wholesale-double-side-prototype-PCB-5x7cm.html) |
| 1 roll | Power wire | Red and black silicone wire, 22 AWG | [Search 22 AWG wire](https://www.aliexpress.com/w/wholesale-22AWG-silicone-wire-red-black.html) |
| 1 roll | Signal wire | Six colors, 26 AWG silicone wire | [Search 26 AWG wire](https://www.aliexpress.com/w/wholesale-26AWG-silicone-wire-kit.html) |
| 1 kit | Heat-shrink tube | 2:1 ratio, 1 mm to 10 mm sizes | [Search heat-shrink kit](https://www.aliexpress.com/w/wholesale-heat-shrink-tube-kit-2%3A1.html) |

The 100 ohm resistor is in series with the future boost converter enable pin.
The 100 kohm resistor keeps that pin off while the ESP32 starts. The available
5.1 kohm resistor limits the 2N3904 base current.

Do not buy another buzzer, buzzer transistor, or flyback diode for the tested
buzzer circuit.

## Buy later for the case

| Build | Qty | Exact selection | AliExpress link |
| --- | ---: | --- | --- |
| Full-size USB-C ESP32 | 1 | USB-C female panel socket to USB-C male plug, data and charge, 0.2 m or 0.3 m | [Item 1005005710706581](https://www.aliexpress.com/item/1005005710706581.html) |
| WEMOS battery build | 1 | USB-C female screw-panel socket to Micro-USB male plug, USB 2.0 data and charge | [Item 1005008918607532](https://www.aliexpress.com/item/1005008918607532.html) |
| WEMOS battery build, alternate | 1 | USB-C female snap-in panel socket to Micro-USB male plug, USB 2.0 data and charge | [Item 1005009655567850](https://www.aliexpress.com/item/1005009655567850.html) |

For the WEMOS build, buy only one of the last two cables. Confirm the connector
direction in the product pictures. The case side must be USB-C female. The
board side must be Micro-USB male. The cable must have the data wires so that
the external connector can also upload firmware.

## Optional battery-build parts

| Qty | Part | Exact selection | Link |
| ---: | --- | --- | --- |
| 2 | Switched 5 V boost module | TPS61023 module, 2 V to 5 V input, 5.2 V output, with `EN` pad | [Item 1005010391033856](https://www.aliexpress.com/item/1005010391033856.html) |
| 1 | Battery pack | 1260110, 3.7 V, 10,000 mAh, built-in PCM, JST-PH 2.0 | [Item 1005010066449193](https://www.aliexpress.com/item/1005010066449193.html) |
| 1 | Wall supply | Regulated 5 V USB-C, 3 A, with the correct safety approval for your country | [Search 5 V 3 A supply](https://www.aliexpress.com/w/wholesale-USB-C-5V-3A-power-adapter.html) |

Buy two boost modules so that there is one spare. The selected module is set
near 5.2 V. This is inside the 3.5 V to 5.5 V SK6812 supply range. Measure its
output before you connect the LEDs.

The WEMOS has a TP4054 charger and a PH-2 2.0 mm battery socket. Do not buy a
second charger board. Its charge current is approximately 500 mA. A discharged
10,000 mAh pack needs at least 20 hours and can need 24 hours for a full charge.

Buy the battery only if the listing states that the pack has built-in PCM
protection for overcharge, over-discharge, overcurrent, and short circuit. Ask
the seller to confirm this before purchase. Do not buy a raw pouch cell.

The battery plug polarity is not standard between sellers. Before connection,
use a multimeter to confirm that battery positive goes to board positive. Move
the JST contacts or use an adapter if the polarity is wrong. Do not reverse the
battery, even for a short time.

Do not buy these parts for this build:

- A second LiPo charge board
- A raw LiPo pouch without a PCM
- Loose 18650 or 21700 cells
- A no-name power-bank module
- A battery that has no protection data

## Tools

- Soldering iron with a small tip
- Multimeter
- USB power meter
- Wire cutter and wire stripper
- Small heat gun for heat-shrink tube
- Sound level meter for final dBA calibration
- Caliper for the case measurements

## Technical sources

- [WEMOS D32 battery connector and 500 mA charge data](https://www.wemos.cc/en/latest/d32/d32.html)
- [TPS61023 data](https://www.ti.com/product/TPS61023)
- [SK6812 RGBW data sheet](https://cdn-shop.adafruit.com/product-files/2757/p2757_SK6812RGBW_REV01.pdf)
- [LiPo protection guidance](https://learn.adafruit.com/li-ion-and-lipoly-batteries/protection-circuitry)
- [CPSC loose-cell warning](https://www.cpsc.gov/Newsroom/News-Releases/2021/CPSC-Issues-Consumer-Safety-Warning-Serious-Injury-or-Death-Can-Occur-if-Lithium-Ion-Battery-Cells-Are-Separated-from-Battery-Packs-and-Used-to-Power-Devices)
