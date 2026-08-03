# JLCPCB order guide

The files in `hardware/pcb/jlcpcb` are ready for a JLCPCB PCB and assembly
order. The KiCad design-rule check has zero violations and zero open
connections.

## Files to upload

1. Upload `espnoise-carrier-gerbers.zip` for PCB fabrication.
2. Select PCB assembly for both PCB faces.
3. Upload `espnoise-carrier-bom.csv` as the bill of materials.
4. Upload `espnoise-carrier-cpl.csv` as the component placement file.

Use these PCB options unless JLCPCB finds a technical conflict:

| Option | Value |
| --- | --- |
| Board size | 96 mm by 38 mm |
| Layers | 2 |
| Material | FR-4 |
| Thickness | 1.6 mm |
| Copper | 1 oz |
| Surface finish | Lead-free HASL |
| Solder mask | Green |
| Assembly | Both faces, including through-hole switches |

The design has bottom-side SMT parts and top-side through-hole switches. JLCPCB
states that its current service supports through-hole parts with manual or wave
soldering. Confirm that both switch rows are selected before payment. If the
site does not offer assembly for `C5379890` or `C5379891`, stop the order. Do
not accept a switch substitution without a data-sheet and footprint check.

## Assembly preview checks

Check these items in the online preview:

1. C2 positive is on pad 1 and points towards the PCB center.
2. U1 pin 1 agrees with the square pin-1 mark.
3. J1 to J5 pin 1 agrees with the square pad.
4. SW1 is `C5379890`, the momentary `7-7 WS` part.
5. SW2 is `C5379891`, the latching `7-7 ZS` part.
6. All five connectors are on the bottom face.
7. SW1 and SW2 are on the top face.

The CPL uses counter-clockwise rotation values, as the JLCPCB placement format
specifies. Bottom parts with a 270 degree value are the flipped form of a
90 degree KiCad placement. The JLCPCB component preview remains the final
orientation check.

## Cost allowance

For a small order of five assembled boards, keep an allowance of approximately
USD 90 to USD 160 before Dubai VAT and import charges. The range includes the
two-face setup, extended-part fees, components, and the small PCB charge. It
does not include a controller, LED strip, microphone module, buzzer, cables, or
power module. Courier delivery to Dubai is typically an additional charge.

This is an allowance, not a quote. JLCPCB part stock and shipping prices can
change. The order page gives the valid price after it maps all BOM lines.

JLCPCB gives its current setup, manual assembly, and through-hole service
details in its [PCB assembly FAQ](https://jlcpcb.com/help/article/pcb-assembly-faqs).
It gives the required placement columns in its
[pick-and-place guide](https://jlcpcb.com/help/article/pick-place-file-for-pcb-assembly).

## Mechanical check before the assembled order

Rev A uses switch centers taken from the current case mesh. The board origin is
its upper-left corner in the KiCad view. The important coordinates are:

| Item | X | Y |
| --- | ---: | ---: |
| SW2, buzzer enable | 22.9 mm | 11.4 mm |
| SW1, mute | 52.9 mm | 10.1 mm |
| H1 mounting hole | 4.0 mm | 4.0 mm |
| H2 mounting hole | 92.0 mm | 4.0 mm |

The two switch centers agree with the measured case openings. The mounting
holes are for a new printed carrier and do not claim alignment with the current
case. Before the assembled order, print the top SVG at 100% scale or order one
bare PCB. Put it in the case and check the switch, connector, capacitor, and
cable clearances.

The switch body is nominally 7 mm by 7 mm. Its stem is nominally 3 mm by 2 mm.
Use an initial printed-cap socket of approximately 3.2 mm by 2.2 mm, and adjust
it after a real switch measurement. Keep the round cap at approximately 10 mm
diameter. Do not make a final case model from the nominal stem dimension alone.
