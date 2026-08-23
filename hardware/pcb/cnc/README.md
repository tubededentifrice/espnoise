# ESPNoise Rev C CNC unit

This directory contains a two-copper-face PCB for the Genmitsu Cubiko. One
nominal 70 mm by 50 mm FR-4 blank can make two units. The machine files contain
one unit only. Run each unit file, rotate the complete blank by 180 degrees in
its plane, set the work origin again, and run the same file a second time.

This method references each unit from an outside factory edge. An error in the
blank height stays in the center area. The file does not contain a second,
rotated unit. The rear-copper file still contains the X mirror that is required
for a left-to-right copper-face flip.

The mute button, hard buzzer switch, microphone acoustic center, and buzzer
center are on one line at local Y = 12.25 mm. Their local X positions are
6.5 mm, 17.5 mm, 35.5 mm, and 60.5 mm. All other component bodies and all wire
terminals are on the internal face.

![Unit user face](espnoise-cnc-user.svg)

![Unit internal face](espnoise-cnc-internal.svg)

The electrical schematic is in `espnoise-cnc-schematic.svg`. The exact pin
connections are in `pinout.md` and `espnoise-cnc-netlist.csv`. The editable
unit PCB is `espnoise-cnc.kicad_pcb`. The generator is the controlled layout
source.

This layout uses the measured buzzer dimensions, the confirmed microphone pin
pattern, and a centered microphone acoustic hole. The microphone body diameter
is approximately 13 mm. Print `espnoise-component-fit-check.svg` at 100% scale
and put the real parts on the drawing before you mill the complete blank.

## Important design limits

- Nominal raw blank: 70 mm by 50 mm
- Unit job area: 70 mm by 24.5 mm
- Supported assumed minimum blank: 69 mm by 49 mm
- Layout shift: 0.50 mm toward the left edge
- Copper faces: two
- Minimum track width: 1.00 mm
- Minimum checked copper clearance: 0.40 mm
- Power track width: 1.30 mm
- Milled isolation width: 0.40 mm
- Microphone pads: 2.00 mm copper with 1.00 mm holes
- Buzzer pads: 2.00 mm copper with 0.80 mm holes
- Mounting hole: one 2.0 mm hole at X = 34.5 mm for each unit run
- Wire vias: 0.8 mm holes with 1.7 mm copper pads
- No plated holes and no solder mask
- 1.2 mm holes for the individual wire terminals
- No insulated link wires
- No LED logic-level IC

The board uses direct insulated wires instead of cable headers. The exact
signal for each pad is in `pinout.md`, the netlist, the schematic, and the
internal-face SVG.

| Pad group | Connection |
| --- | --- |
| PWR1-1 / PWR1-2 | External +5 V / GND |
| J_ESP32-1 through J_ESP32-9 | ESP32 5 V, GND, 3.3 V, and six GPIO wires |
| J_LED-1 / J_LED-2 / J_LED-3 | LED +5 V / DIN / GND |

The LED data path is a direct trace from ESP32 GPIO18 to J_LED-2. This matches
the tested prototype. It is not a guaranteed 5 V logic interface. Keep the
wire short. If the installed strip is not reliable, add an external 5 V logic
buffer near the strip.

The buzzer driver parts stay on the board. The specified magnetic 5 V buzzer
must not connect directly to an ESP32 GPIO. SW2 stays as a hard switch in the
buzzer power wire and can remove all buzzer power.

MIC1 is the round MH-ET LIVE INMP441 module with two rows of three pins. With
the printed-label and acoustic-hole face toward the case top, and with the
notch at the local top edge, the top row is `GND`, `VDD`, `SD`. The bottom row
is `L/R`, `WS`, `SCK`. `L/R` connects to GND. This is the same view as the
supplied product image.

BZ1 is a 12 mm passive two-pin through-hole buzzer. Its lead pitch is 6.5 mm,
and each lead is 0.5 mm. Pad 1 is positive. Pad 2 is negative and connects to
the transistor collector.

## Generate the files

Install `pcb2gcode`. On macOS, use this command:

```sh
brew install pcb2gcode
```

Then run this command from the repository root:

```sh
uv run --locked opendle-cnc build --config opendle-tools.toml
```

The script does these tasks:

1. It generates one unit PCB.
2. It checks the board limits, body overlap, copper width, and clearance.
3. It makes one user-face isolation job and one mirrored internal-face job.
4. It makes one unit G-code file for each drill size.
5. It checks all X, Y, and Z limits and writes SHA-256 checksums.

The ready files are in `machine`. Do not run them until the coupon and the
preflight checks in `cubiko-guide.md` pass.

## Source files

| File | Purpose |
| --- | --- |
| `generate_cnc_board.py` | Unit source, router, and checks |
| `espnoise-cnc.kicad_pcb` | Editable and reviewable 70 mm by 24.5 mm unit |
| `espnoise-cnc-user.svg` | Single-unit user-face check view |
| `espnoise-cnc-internal.svg` | Single-unit internal-face check view |
| `espnoise-cnc-schematic.svg` | Electrical schematic |
| `pinout.md` | Complete pad and connector pin map |
| `espnoise-component-fit-check.svg` | 1:1 physical part fit check |
| `espnoise-cnc-netlist.csv` | Exact pin-to-net table |
| `espnoise-cnc-bom.csv` | Parts and face assignment for one unit |
| `millproject` | Single-unit isolation values |
| `millproject-coupon` | Coupon isolation values |
| `opendle-tools.toml` | Project paths, process values, and machine limits |
| `opendle-electronics` | Pinned shared CAM, G-code checks, and manifests |
