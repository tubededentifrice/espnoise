# Production enclosure

This directory contains the release enclosure for the USB-powered ESPNoise
build. The main case envelope is 164 mm by 54 mm by 54.5 mm.

![ESPNoise enclosure assembly](media/enclosure-preview.png)

## Choose a file

- Open [`production/espnoise.3mf`](production/espnoise.3mf) in Bambu Studio to
  use the arranged plates and saved print profile.
- Open [`production/espnoise.f3d`](production/espnoise.f3d) in Autodesk Fusion
  to change the design.
- Import the individual STL files into another slicer when you do not use the
  3MF package.

Do not scale the models. The STL coordinate origins are assembly coordinates,
so an individual part can open away from the slicer origin. Use the slicer's
place-on-bed and arrange functions.

## Included parts

The dimensions below are axis-aligned STL bounds in millimetres.

| File | Purpose | Size, X × Y × Z |
| --- | --- | ---: |
| [`case.stl`](production/case.stl) | Main enclosure | 164.0 × 54.0 × 54.5 |
| [`back.stl`](production/back.stl) | Rear cover | 164.0 × 54.0 × 4.4 |
| [`reflector.stl`](production/reflector.stl) | LED light divider | 159.3 × 47.3 × 22.0 |
| [`letters.stl`](production/letters.stl) | Illuminated NOISE face | 159.0 × 35.0 × 2.4 |
| [`letters-mould.stl`](production/letters-mould.stl) | Optional letter mould | 173.0 × 49.0 × 8.6 |
| [`button.stl`](production/button.stl) | Momentary-button cap | 14.3 × 8.0 × 14.3 |
| [`toggle-button.stl`](production/toggle-button.stl) | Buzzer-switch cap | 14.3 × 4.0 × 14.3 |

## Saved print profile

The 3MF package was saved from Bambu Studio 2.7 for a Bambu Lab X1 Carbon.
Its main settings are:

| Setting | Saved value |
| --- | --- |
| Nozzle | 0.4 mm |
| Layer height | 0.2 mm |
| Wall loops | 2 |
| Sparse infill | 15% |
| Supports | Off |
| Bed adhesion | Automatic brim |

The saved material assignments are cyan PETG for the letters, white PLA for
the reflector and switch cap, and black PLA for the case, back, button cap, and
letter mould. These colors help the sign control stray light. Equivalent colors
and materials can be used after a small fit and light test.

Check temperatures, cooling, bed adhesion, and dimensional compensation for
your printer. Print the small button parts first. Confirm their fit before you
start the case.

## Assembly notes

1. Remove all brim material and clean the button openings.
2. Test-fit the button and switch caps. They must move freely.
3. Put the reflector behind the letter face.
4. Align two SK6812 pixels behind each letter.
5. Keep the microphone acoustic hole clear and away from the buzzer.
6. Install the electronics with removable connectors.
7. Fit the back only after the wiring and power tests pass.

Do not put pressure, a screw, a sharp edge, or a hot part against a LiPo pack.
The production enclosure is for the USB-powered build. A battery version needs
a separate fit, clearance, and temperature review.

## Design compatibility

Low-cost ESP32 boards with the same product name can have different board,
connector, and mounting dimensions. Compare your parts with the Fusion model
before a long print. If you change a component, keep the changed hardware
assumption in this file and update the related model.

[`production/SHA256SUMS`](production/SHA256SUMS) contains checksums for all
release assets.
