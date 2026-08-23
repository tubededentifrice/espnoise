# ESPNoise carrier PCB

For the nominal 70 mm by 50 mm home-milled blank, use
[`cnc/README.md`](cnc/README.md). The Cubiko files contain one unit. Run them
twice with a 180-degree blank rotation between the two runs. The prototype uses
larger through-hole parts, individual wire terminals, registration holes,
Gerber files, and Cubiko G-code.
The Rev B factory board below stays separate.

This directory contains the carrier PCB for the USB-powered ESPNoise build.
The ESP32 stays on a removable cable. The PCB contains the controls, digital
microphone, buzzer, LED data buffer, buzzer driver, fuse, and keyed connectors.

The board is 80 mm by 20 mm. Its nominal stack is two copper layers, 1.6 mm
FR-4, 1 oz copper, lead-free HASL, and a green solder mask.

## Interface summary

The controller, LED, and USB-C power connectors are JST PH vertical headers on
the lower face. A cable enters each connector in the direction away from that
face. The two switches, microphone opening, and buzzer are on the 10 mm board
centerline and face the case top.

MIC1 is on the lower face because it is a bottom-port microphone. A 0.5 mm
non-plated hole carries sound from the case top to the microphone port. Do not
cover this hole with glue, foam, or a label.

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
the assembly preview. In particular, check C2 and D1 polarity, MIC1 pin 1, pin
1 of all JST connectors, BZ1 polarity, and the six pins on each switch.

JLCPCB stock can change. Do not submit the order if the site replaces a part
without a new electrical and footprint check.

## Regeneration

Run `uv run --locked opendle-kicad export --config opendle-tools.toml` from the
repository root. The pinned shared tool needs KiCad 10 and its Python `pcbnew`
module. It regenerates the board, Gerbers, drill files, BOM, CPL, assembly
views, and hash manifest.

The generator is the controlled source for the board layout. Do not edit the
generated board without the same change in `generate_board.py`.

Use these documents with the order package:

- `electrical-design.md` gives the circuit and selected factory parts.
- `controller-adapters.md` gives all cable pin orders.
- `order-guide.md` gives the JLCPCB upload and preview checks.
