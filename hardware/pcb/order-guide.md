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
| Board size | 80 mm by 20 mm |
| Layers | 2 |
| Material | FR-4 |
| Thickness | 1.6 mm |
| Copper | 1 oz |
| Surface finish | Lead-free HASL |
| Solder mask | Green |
| Assembly | Both faces, including through-hole switches |

The design has SMT parts on both faces and through-hole switches on the top
face. JLCPCB states that its current service supports through-hole parts with
manual or wave soldering. Confirm that both switch rows are selected before
payment. If the site does not offer assembly for `C5379890` or `C5379891`, stop
the order. Do not accept a part substitution without a data-sheet and
footprint check.

## Assembly preview checks

Check these items in the online preview:

1. C2 positive is on pad 1 and points towards the PCB center.
2. U1 pin 1 agrees with the square pin-1 mark.
3. J1, J2, and J3 pin 1 agree with the square pad.
4. SW1 is `C5379890`, the momentary `7-7 WS` part.
5. SW2 is `C5379891`, the latching `7-7 ZS` part.
6. J1, J2, J3, MIC1, and C2 are on the bottom face.
7. SW1, SW2, BZ1, and D1 are on the top face.
8. MIC1 pin 1 and D1 cathode agree with the marks in the preview.
9. BZ1 positive pad 1 is on the right side in the top view.

The CPL uses counter-clockwise rotation values, as the JLCPCB placement format
specifies. Bottom parts with a 270 degree value are the flipped form of a
90 degree KiCad placement. The JLCPCB component preview remains the final
orientation check.

## Cost allowance

For a small order of five assembled boards, keep an allowance of approximately
USD 110 to USD 190 before Dubai VAT and import charges. The range includes the
two-face setup, through-hole work, extended-part fees, components, and the PCB
charge. It does not include a controller, LED strip, cables, or power module.
Courier delivery to Dubai is an additional charge.

This is an allowance, not a quote. JLCPCB part stock and shipping prices can
change. The order page gives the valid price after it maps all BOM lines.

JLCPCB gives its current setup, manual assembly, and through-hole service
details in its [PCB assembly FAQ](https://jlcpcb.com/help/article/pcb-assembly-faqs).
It gives the required placement columns in its
[pick-and-place guide](https://jlcpcb.com/help/article/pick-place-file-for-pcb-assembly).

## Mechanical check before the assembled order

Rev B uses an 80 mm by 20 mm outline. The user-facing parts are on the 10 mm
centerline. The board origin is its upper-left corner in the KiCad view. The
important coordinates are:

| Item | X | Y |
| --- | ---: | ---: |
| SW2, buzzer enable | 7.0 mm | 10.0 mm |
| SW1, mute | 20.0 mm | 10.0 mm |
| MIC1 acoustic hole | 29.5 mm | 10.0 mm |
| BZ1, buzzer | 69.0 mm | 10.0 mm |

The PCB has no mounting holes. The case must hold its long edges or use a
printed tray. Before the assembled order, print the top SVG at 100% scale or
order one bare PCB. Put it in the case and check the switch, microphone,
buzzer, connector, capacitor, and cable clearances.

The switch body is nominally 7 mm by 7 mm. Its stem is nominally 3 mm by 2 mm.
Use an initial printed-cap socket of approximately 3.2 mm by 2.2 mm, and adjust
it after a real switch measurement. Keep the round cap at approximately 10 mm
diameter. Do not make a final case model from the nominal stem dimension alone.

Keep a clear sound path above the 0.5 mm microphone hole and above the buzzer
port. Do not put a closed printed button cap over either sound path.
