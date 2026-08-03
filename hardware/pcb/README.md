# ESPNoise carrier PCB

This directory contains the carrier PCB for the USB-powered ESPNoise build.
The ESP32 stays on a removable cable. The PCB contains the controls, LED data
buffer, buzzer driver, fuse, and keyed module connectors.

The board is 96 mm by 38 mm. Its nominal stack is two copper layers, 1.6 mm
FR-4, 1 oz copper, lead-free HASL, and a green solder mask.

## Interface summary

The controller and LED connectors are JST PH vertical headers on the lower
face. A cable enters each connector in the direction away from the lower PCB
face. This placement keeps the cables away from the two top controls.

The controller interface uses signal names. It does not depend on the physical
size of the ESP32 board. Make one adapter cable for the selected controller.
The current `esp32dev` pin map is in `docs/wiring.md`. An ESP32-C3 needs a
separate firmware target and a different adapter cable before use.

## Factory order files

The `jlcpcb` directory contains these order files:

- `espnoise-carrier-gerbers.zip`: PCB fabrication data.
- `espnoise-carrier-bom.csv`: component list for assembly.
- `espnoise-carrier-cpl.csv`: component placement data.
- `espnoise-carrier-top.svg` and `espnoise-carrier-bottom.svg`: assembly views.

Upload the Gerber ZIP in the JLCPCB PCB order page. Enable PCB assembly, and
then upload the BOM and CPL files. Check every mapped part and orientation in
the assembly preview. In particular, check the polarity of C2, pin 1 of all
JST connectors, and the six switch pins.

JLCPCB stock can change. Do not submit the order if the site replaces a part
without a new electrical and footprint check.

## Regeneration

Run `./hardware/pcb/build-factory-files.sh` from the repository root. The
script needs KiCad 10 and its Python `pcbnew` module. It regenerates the board,
Gerbers, drill files, BOM, CPL, and assembly views.

The generator is the controlled source for the board layout. Do not edit the
generated board without the same change in `generate_board.py`.

Use these documents with the order package:

- `electrical-design.md` gives the circuit and selected factory parts.
- `controller-adapters.md` gives all cable pin orders.
- `order-guide.md` gives the JLCPCB upload and preview checks.
