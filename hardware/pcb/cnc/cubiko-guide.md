# Genmitsu Cubiko first PCB guide

Use this guide for the ESPNoise Rev C CNC prototype. Do not start with the
complete board. Start with the coupon.

## Tools and material

Use these items:

- Genmitsu Cubiko with its cover, clamps, and height-map cable
- Flat, two-face copper-clad FR-4, nominally 70 mm by 50 mm
- Sharp 20-degree or 30-degree V-bit with a 3.175 mm shank
- 0.8 mm, 0.9 mm, 1.0 mm, and 2.0 mm carbide drills
- Two smooth 2.0 mm registration pins
- Sacrificial spoilboard
- Caliper, fine marker, multimeter, and magnifier or USB microscope
- Safety glasses and suitable dust protection
- Small vacuum with a suitable fine-dust filter

Use the 20-degree V-bit first if you have one. It changes the cut width less
for a small Z error. A 30-degree V-bit also works after the coupon passes.
Do not use a 60-degree or 90-degree V-bit for the first board. It makes a much
wider cut when Z changes.

Do not touch the tool when the spindle can start. Close the machine cover for
each operation. FR-4 dust is harmful. Do not blow it with compressed air. Keep
the dust in the closed machine, remove it with the vacuum, and clean the board
before you touch your face or food.

The SainSmart quick-start guide supplies a 20-degree V-bit and tells the user
to leave approximately 15 mm of the tool outside the collet. The Cubiko
resource page gives the Genmitsu App and Universal Gcode Sender options. Use
the Genmitsu App for this first board because its PCB height-map process is
made for the Cubiko.

Sources:

- [Cubiko resource page](https://docs.sainsmart.com/article/8f6ypseduj-cubiko)
- [SainSmart KiCad-to-CNC PCB guide](https://www.sainsmart.com/blogs/news/cubiko-pcb-milling-tutorial)
- [Cubiko product and height-map description](https://genmitsu.com/pages/cubiko)

## Understand the four coordinates

- Machine zero is the Cubiko home position. Do not change it.
- Work X/Y zero is the lower-left corner of the fixed 70 mm by 50 mm blank.
- Work Z zero is the measured copper surface for the installed tool.
- The back job is already mirrored around X = 35 mm.

The two registration holes are on X = 35 mm. Flip the board from left to
right. Do not flip it from top to bottom. The two pins keep the board position.
Keep the same work X/Y zero after the flip. Make a new Z measurement and a new
height map for each face and after each tool change.

This process is different from a visual edge-flip process. Do not add 70 mm to
X after the flip. The generated back G-code already contains the required
mirror operation.

## Initial CAM values

The `millproject` and `millproject-coupon` files use these first-test values:

| Setting | Value |
| --- | ---: |
| Spindle speed | 10,000 RPM |
| Horizontal feed | 120 mm/min |
| Vertical feed | 60 mm/min |
| Isolation depth | 0.04 mm |
| Effective V-bit cut width | 0.20 mm |
| Isolation width | 0.20 mm |
| Safe Z | 2.0 mm |
| Drill depth | 1.8 mm |

The SainSmart PCB guide gives an isolation depth range from 0.01 mm to
0.05 mm. The project starts at 0.04 mm. This is a test value, not a universal
value. Copper thickness, bit tip width, spindle runout, and board flatness
change the result.

## Make and test the coupon

Run the build script. Use the files with names that start with `coupon-`.

1. Put a small FR-4 test piece on the spoilboard with its user face up.
2. Clamp it. Confirm that the clamps are outside the 30 mm by 15 mm job area.
3. Set work X/Y zero at the coupon lower-left corner.
4. Install the 2.0 mm drill. Set Z zero.
5. Run `coupon-drill-2.0mm.nc`. The holes must enter the spoilboard.
6. Install the V-bit. Set Z zero. Make a height map for 30 mm by 15 mm.
7. Run `coupon-user-face.nc`.
8. Stop the spindle. Check that each copper path is continuous and isolated.
9. Put two smooth 2.0 mm pins into the spoilboard holes.
10. Flip the coupon from left to right. Put it on the pins and clamp it.
11. Set Z zero and make a new height map.
12. Run `coupon-internal-face.nc`.
13. Check the front-to-back alignment at the 0.8 mm via holes.
14. Run the 0.8 mm, 0.9 mm, and 1.0 mm coupon drill jobs with the matching
    tools. Set Z zero after each tool change.

Use the multimeter continuity mode. Adjacent copper paths must not connect.
Each complete path must have low resistance. The drill holes must not remove
the complete annular ring. The front and back via pads must be concentric.

If copper remains between two paths, first check the height map and the tool
tip. Increase the depth by only 0.01 mm. Do not use a depth below -0.05 mm for
this V-bit test. If the cut is too wide or a track becomes narrow, reduce the
depth or use the smaller-angle V-bit. Change `zwork` or `mill-diameters` in
both millproject files, and then run the build script again.

## Mill the complete board

Use a new 70 mm by 50 mm blank after the coupon passes.

1. Measure the blank. Stop if a dimension is less than 70 mm by 50 mm.
2. Mark one face `USER` and mark its lower-left corner.
3. Clamp the blank with the user face up.
4. Set X/Y zero at the marked lower-left corner.
5. Install the 2.0 mm drill and set Z zero.
6. Run `espnoise-cnc-drill-2.0mm.nc` first. These holes set the flip axis.
7. Install the validated V-bit and set Z zero.
8. Make a height map for 70 mm by 50 mm.
9. Run `espnoise-cnc-user-face.nc`.
10. Check the isolation before you remove the blank.
11. Put two smooth 2.0 mm pins into the registration holes and spoilboard.
12. Flip the board from left to right. Keep the same X/Y zero.
13. Clamp the board. Set Z zero and make a new height map.
14. Run `espnoise-cnc-internal-face.nc`.
15. Check the flip alignment at several wire-via pads.
16. Flip the board back to the user face with the pins.
17. Run the 0.8 mm, 0.9 mm, and 1.0 mm drill jobs. Install the matching drill
    and set Z zero before each job.
18. Vacuum the machine and board. Lightly remove copper burrs.
19. Wash the board with isopropyl alcohol and let it dry.
20. Use the multimeter test in the next section.

The complete blank is the PCB outline. Do not run an outline or cutout job.

## Electrical check before solder

Do not connect power during these checks.

1. Check each adjacent J1, J2, J3, U1, and MIC1 pad pair for a short circuit.
2. Check `+5V_IN` to GND and `+5V_PERIPH` to GND. Both results must be open.
3. Check each track from one listed endpoint to the other endpoint.
4. Check that each registration hole has no copper contact.
5. Compare all diode, transistor, capacitor, connector, and IC pin marks with
   the schematic and netlist.

Do not repair a narrow isolation gap with a powered rotary tool. Disconnect
the board and use a fine knife or a small hand tool under magnification.

## Wire vias and solder order

This home-milled board has no plated holes. The generated board has 25 wire
vias. Do these steps before you install a component:

1. Put tinned 0.5 mm solid copper wire through each 0.8 mm wire-via hole.
2. Solder the wire on both copper faces.
3. Cut the wire close to both solder joints.
4. Check continuity through each via.
5. Check that each via has no short to an adjacent path.

Then install low parts first. Install resistors, diode, IC socket, small
capacitor, transistor, and fuse. Install the large capacitor and connectors
after these parts. Install the user-face switches, microphone module, and
buzzer last.

The internal component bodies use copper tracks on the user face. Solder their
leads on the user face. The user component bodies use tracks on the internal
face. Solder their leads on the internal face. BZ1 is an SMD part on the user
face. Solder it on that face.

Use a socket for U1. Confirm the `2N3904` E-B-C pin order from its data sheet.
Confirm the INMP441 module pin labels. Do not install a part only from its
seller title.

## First power test

Keep J2, J3, and the buzzer disconnected for the first test.

1. Put a current-limited 5 V supply on J1.
2. Start with a 100 mA current limit.
3. Confirm 5 V at J2 pin 1 and after F1.
4. Disconnect power. Install U1 and connect the controller.
5. Test the microphone before you connect the LED strip.
6. Test one SK6812 RGBW pixel at no more than the present brightness limit.
7. Connect all 10 pixels only after the one-pixel test passes.
8. Test the buzzer and its hard switch last.

Keep the external USB-C power input separate from the ESP32 firmware-service
port. Do not power both inputs at the same time. The buzzer switch must stay in
the buzzer power wire.
