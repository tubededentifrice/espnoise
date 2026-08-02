# Case design input

Do not make the final case from a generic board name. Low-cost ESP32 boards
with the same name can have different USB positions, hole positions, and board
sizes.

## Proposed layout

```text
Front
+--------------------------------------------------+
|                  N O I S E                       |
|        black face and white diffuser             |
+--------------------------------------------------+

Inside, from front to back
1. Printed front face, 2.0 mm to 2.4 mm
2. White diffuser, 1.0 mm to 1.5 mm
3. Air gap, 15 mm to 25 mm
4. Ten SK6812 pixels, two behind each letter
5. Electronics tray
```

Ten pixels from a 60-pixel/m strip have a nominal length of 166.7 mm. Measure
the cut section because the solder pads and end wires can change the necessary
space.

Put the microphone on a side or bottom wall. This position keeps direct sound
from the optional buzzer away from the microphone. Use a 2 mm first test hole
and a short acoustic channel. Do not put a case rib over the module acoustic
hole.

Use a removable back with screws. For the battery build, use a separate
battery cover. Do not use glue on the battery bay. Give the LiPo pouch at least
2 mm of free space on each flat side. Do not put a screw, sharp edge, printed
clamp, or solder joint against the pouch.

Put the 30-minute mute button and buzzer switch where they cannot be pressed by
accident. Mark the buzzer switch `SOUND ON` and `SOUND OFF`. Keep the panel
USB-C connector accessible without removal of the back cover.

## Measurements needed

Measure each value with a caliper and add it to this file:

| Part | Required measurement | Value |
| --- | --- | --- |
| Full-size ESP32 | Board length, width, and highest part | Not measured |
| Full-size ESP32 | USB-C center and mount holes | Not measured |
| WEMOS | Board length, width, and highest part | Nominal 57 mm by 25.4 mm; not measured |
| WEMOS | Micro-USB and battery-socket positions | Not measured |
| INMP441 module | Length, width, height, and acoustic hole | Not measured |
| SK6812 section | Length, width, height, and end-wire space | Nominal 166.7 mm long; not measured |
| Mute button | Thread diameter, body depth, and terminal depth | Not selected |
| Buzzer switch | Cut-out size, body depth, and terminal depth | Not selected |
| Panel USB-C | Cut-out size and screw spacing | Not selected |
| Buzzer | Diameter and height | Not selected |
| TPS61023 module | Board and connector size | Nominal 17.8 mm by 11.3 mm by 5.6 mm; not measured |
| LiPo pack | Length, width, thickness, wire, and connector | Not selected |

## First size target

Use 190 mm by 80 mm by 50 mm only as a layout target. Do not print the case at
this size until the parts are measured. The internal 10,000 mAh battery can
control the final depth. The final wall thickness must be at least 2.0 mm. Use
heat-set M3 inserts for the back cover if they are available.

For the diffuser, use natural or white translucent PETG. For the case and
front mask, use opaque PETG or PLA. Keep the battery bay away from direct sun
and other heat sources.
