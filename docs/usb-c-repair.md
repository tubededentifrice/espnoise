# USB-C compatibility repair

This is an optional advanced method. The first build uses a separate two-wire
USB-C power module and does not need this board repair.

## Problem

The old ESP32 board operates with a USB-A to USB-C cable but does not operate
with a USB-C to USB-C cable. This usually means that its USB-C socket does not
have the two required configuration-channel pull-down resistors.

A USB-A port supplies 5 V without USB-C attachment detection. A USB-C source
first looks for an `Rd` pull-down on a configuration-channel pin. If it does
not find the pull-down, it keeps VBUS off.

## Preferred board repair

Add two independent 5.1 kohm, 1% resistors:

```text
USB-C receptacle CC1 (A5) ── 5.1 kohm ── board GND
USB-C receptacle CC2 (B5) ── 5.1 kohm ── board GND
```

Do not connect CC1 and CC2 together. Do not use one resistor for both pins.
Do not connect a resistor to D+, D-, SBU1, SBU2, or VBUS.

This is a hardware-only repair. It does not need USB Power Delivery firmware.
It keeps the original USB-C port for power, firmware upload, and the serial
monitor.

## Parts

- 2 resistors, 5.1 kohm, 1%, 0603 or 0805 SMD
- Fine insulated wire, 30 AWG, only if a resistor cannot connect directly
- Fine soldering tip, flux, magnification, and a multimeter

Select the resistor size only after inspection of the board. The USB-C contact
pitch is small. Do not attempt the repair without a clear view of the pads.

## Inspection before soldering

1. Disconnect all USB power and all modules.
2. Identify the exact USB-C receptacle or follow its CC traces.
3. Identify CC1 and CC2 from the connector data sheet or board traces. Do not
   use a generic pad position without confirmation.
4. Confirm that CC1 and CC2 are not shorted together.
5. Measure from each CC pin to board GND.
6. If both values are already near 5.1 kohm, do not add more resistors. The
   fault has a different cause.
7. If the pins are open to GND, install the two resistors.

If CC1 and CC2 are shorted together, stop. The traces must be separated before
the two resistors can be installed. A full-data adapter module is safer in
that condition.

## Test after soldering

1. Use magnification to look for solder bridges.
2. With power disconnected, measure approximately 5.1 kohm from CC1 to GND.
3. Measure approximately 5.1 kohm from CC2 to GND.
4. Confirm that VBUS is not shorted to GND, CC1, or CC2.
5. Connect a USB-C to USB-C cable with no external modules connected.
6. Measure 4.75 V to 5.25 V from the board `5V` or `VIN` pin to GND.
7. Reverse the cable plug and repeat the power test.
8. Confirm serial-port detection and firmware upload in both plug positions.
9. Connect the microphone.
10. Connect one LED pixel, and then the complete sign.

Disconnect the LED power plug during the first firmware-upload tests. A
computer USB port can advertise less current than a wall supply.

## Use of a two-wire USB-C connector

A two-wire connector exposes only VBUS and GND. It cannot carry D+ and D-, so
it cannot upload firmware or provide a serial monitor.

Some two-wire USB-C boards include the two 5.1 kohm resistors. Some do not. A
board without them has the same USB-C to USB-C power fault.

Use a two-wire connector only for a separate power-only test or a later power
module. Do not use it for the preferred single-port build.

## Full-data adapter fallback

If the board CC pads are not accessible, use a USB 2.0 Type-C female breakout
that has all of these connections:

- VBUS and GND
- D+ and D-
- Separate CC1 and CC2 pads
- One 5.1 kohm pull-down from each CC pad to GND

Connect this module through a short full-data cable to the ESP32 USB-C port.
This keeps one external connector for power and upload, but it uses more space
than the direct board repair. A two-wire breakout is not a valid substitute.

## Technical sources

- [USB Type-C Cable and Connector Specification](https://www.usb.org/sites/default/files/USB%20Type-C%20Spec%20R2.0%20-%20August%202019.pdf)
- [Microchip USB-C downstream-device example](https://onlinedocs.microchip.com/oxy/GUID-D5B5915F-6907-409C-A6D9-F79690ACDCA3-en-US-1/GUID-EBF2E2A2-E9F3-4834-B185-F9FCCCABB46F.html)
