# ESPNoise Rev C pin and part map

This document uses the view from the marked face of each part. The marked face
points toward the top opening of the case. The internal PCB face contains the
wire pads and the buzzer driver parts.

The microphone pin pattern, centered acoustic hole, and buzzer dimensions come
from the prototype parts. The microphone body diameter is approximately
13 mm. Use the 1:1 fit check before you engrave the full panel.

## PWR1: external 5 V power wires

| PCB pad | Connect to | Function |
| --- | --- | --- |
| PWR1-1 | External red wire | +5 V input |
| PWR1-2 | External black wire | GND |

The external power input must stay separate from the ESP32 firmware-service
USB port. Do not power both ports at the same time.

## J_ESP32: individual wires to the ESP32

These are individual solder pads. `J_ESP32` is their electrical group name.
It is not a plug housing.

| PCB pad | ESP32 connection | Signal destination |
| --- | --- | --- |
| J_ESP32-1 | VIN or 5V | +5 V input, before F1 |
| J_ESP32-2 | GND | Common GND |
| J_ESP32-3 | 3V3 | MIC1-2 VDD |
| J_ESP32-4 | GPIO26 | MIC1-6 SCK |
| J_ESP32-5 | GPIO25 | MIC1-5 WS |
| J_ESP32-6 | GPIO32 | MIC1-3 SD |
| J_ESP32-7 | GPIO18 | J_LED-2 DIN |
| J_ESP32-8 | GPIO23 | R2, then Q1 base |
| J_ESP32-9 | GPIO27 | SW1-5 MUTE_N |

## J_LED: individual wires to the LED strip

| PCB pad | LED strip connection |
| --- | --- |
| J_LED-1 | +5 V after F1 |
| J_LED-2 | DIN, direct from ESP32 GPIO18 |
| J_LED-3 | GND |

The direct 3.3 V data signal matches the tested short-wire prototype. A 5 V
SK6812 data input does not have a guaranteed 3.3 V margin. If the strip is not
stable, install an external 5 V logic buffer close to the strip.

## MIC1: MH-ET LIVE INMP441 module

Install the module with its printed-label and acoustic-hole face toward the
case top. The pin diagram below is the view from that face. Put the edge notch
at the local top edge of the PCB, as shown in the supplied product image.

```text
                  LOCAL TOP EDGE / NOTCH

                  1 GND   2 VDD   3 SD

                  4 L/R   5 WS    6 SCK

                  LOCAL BOTTOM EDGE
```

MIC1-4 `L/R` connects to GND. The firmware reads both I2S slots, but this
connection gives the module a defined channel.

The module already contains its local microphone support parts. Do not add a
second microphone resistor or capacitor.

## BZ1: two-pin buzzer

Use the top sound-port view:

```text
        BZ1-2  -             +  BZ1-1
     Q1 collector         switched +5 V
```

The PCB uses two drilled holes. It does not use side SMD pads. Confirm the
positive mark on the real buzzer before solder.

## Switch contacts

| Switch | Used pads | Connection |
| --- | --- | --- |
| SW1 MUTE | 5 and 6 | GPIO27/MUTE_N to GND when pressed |
| SW2 BUZZER ENABLE | 4 and 5 | +5 V peripheral rail to BZ1-1 when enabled |

Check these contact pairs with a multimeter before solder. Seller switch
contact numbering can differ.

## Support parts that remain

| Part | Purpose |
| --- | --- |
| F1, 0.5 A PTC | Limits fault current in the LED and buzzer branch |
| Q1, 2N3904 | Keeps buzzer current out of ESP32 GPIO23 |
| R2, 1 kohm | Limits Q1 base current |
| R3, 100 kohm | Keeps Q1 off while GPIO23 floats during reset |
| D1, 1N5819 | Clamps the turn-off pulse from a magnetic buzzer coil |

The PCB has no LED resistor, no bulk capacitor, no LED level shifter, and no
extra microphone passives.

## Physical values

| Value | PCB value | Source |
| --- | ---: | ---: |
| MIC1 round body diameter | 13.00 mm | Approximate |
| MIC1 pin pitch inside each row | 2.54 mm | Confirmed on prototype board |
| MIC1 distance between rows | 7.62 mm | Confirmed: two empty 2.54 mm rows between occupied rows |
| MIC1 acoustic-hole X offset from body center | 0.00 mm | Confirmed centered |
| MIC1 acoustic-hole Y offset from body center | 0.00 mm | Confirmed centered |
| BZ1 body diameter | 12.00 mm | Measured |
| BZ1 lead pitch | 6.50 mm | Measured |
| BZ1 lead diameter | 0.50 mm | Measured; PCB drill is 0.80 mm |

The centered microphone acoustic hole is on the switch and buzzer centerline.
