# Genmitsu Cubiko first PCB guide

Use this guide to put two ESPNoise Rev C units on one blank. The machine files
contain one unit. Do not start with the complete blank. First use the 1:1 part
check. Then use the coupon.

## Tools and material

Use these items:

- Genmitsu Cubiko with its cover, clamps, and height-map cable
- Flat two-face copper-clad FR-4, nominally 70 mm by 50 mm
- Sharp 20-degree or 30-degree V-bit with a 3.175 mm shank
- 0.8 mm, 0.9 mm, 1.0 mm, 1.2 mm, and 2.0 mm carbide drills
- 1.0 mm carbide PCB router bit with a 3.175 mm shank
- Two smooth 2.0 mm registration pins
- Flat sacrificial spoilboard
- Caliper, fine marker, multimeter, and magnifier or USB microscope
- Safety glasses and suitable dust protection
- Small vacuum with a suitable fine-dust filter

Use a 20-degree V-bit first if you have one. A small Z error changes its cut
width less than it changes the cut width of a large-angle bit. A 30-degree
V-bit also works after the coupon passes. Do not use a 60-degree or 90-degree
V-bit for the first panel.

Use the 1.0 mm PCB router bit only for the last separation cut. A corn-cut PCB
router bit is a good type for FR-4. A straight carbide end mill can also work
after a test. Do not use a drill for a side cut. A drill is not made for that
load. Do not use a V-bit for the full-depth separation cut.

Do not touch a tool when the spindle can start. Close the machine cover for
each operation. FR-4 dust is harmful. Do not use compressed air. Keep the dust
in the closed machine. Remove it with the vacuum. Clean the board before you
touch your face or food.

The SainSmart quick-start guide supplies a 20-degree V-bit and tells the user
to leave approximately 15 mm of the tool outside the collet. The Cubiko
resource page gives the Genmitsu App and Universal Gcode Sender options. Use
the Genmitsu App for this first panel because its PCB height-map process is
made for the Cubiko.

Sources:

- [Cubiko resource page](https://docs.sainsmart.com/article/8f6ypseduj-cubiko)
- [SainSmart KiCad-to-CNC PCB guide](https://www.sainsmart.com/blogs/news/cubiko-pcb-milling-tutorial)
- [Cubiko product and height-map description](https://genmitsu.com/pages/cubiko)

## Know the repeated-unit layout

The raw blank is nominally 70 mm by 50 mm. The assumed minimum size is 69 mm
by 49 mm. Each unit job uses 70 mm by 24.5 mm nominal coordinates. All copper
and holes have a 0.50 mm shift toward the left. This gives more clearance at
the right edge of a short blank.

Run the first unit from one outside edge. Rotate the complete blank by 180
degrees in its plane. Set X/Y zero at the new lower-left corner. Run the same
file again. The machine file does not contain a second unit or its rotation.
The blank-height error stays between the two units.

The button centers, microphone acoustic center, and buzzer center are on one
straight line. This line is local Y = 12.25 mm on each finished PCB.

Before you mill copper, print `espnoise-component-fit-check.svg` at 100% scale.
Measure the printed 50 mm check line. It must be 50 mm. Put the real MIC1 and
BZ1 parts on the drawing. All leads must align with the hole centers. Update
the measured values in `generate_cnc_board.py`, rebuild the files, and repeat
this check. A screen view is not a physical fit check.

## Know the four coordinates

- Machine zero is the Cubiko home position. Do not change it.
- Work X/Y zero is the lower-left corner of the current blank orientation.
- Work Z zero is the measured copper surface for the installed tool.
- The internal-face job is already mirrored around X = 34.5 mm. This is the
  center of the 69 mm minimum-width reference window.

Each unit run makes one 2.0 mm mounting hole at X = 34.5 mm. Do not use the two
repeated holes as a flip axis when the blank is wider than 69 mm. Use the
corner stops for the copper-face flip. Flip the blank from left to right. Do
not flip it from top to bottom. If the measured blank length is more than
69 mm, put the extra length before X zero on the internal-face presentation.
For example, put 0.8 mm before X zero for a 69.8 mm blank. This keeps the
69 mm reference window aligned on both faces. Make a new Z measurement and a
new height map for each face and after each tool change.

Do not add 70 mm to X after the flip. The generated internal-face G-code
already contains the mirror operation.

## Initial CAM values

The build files use these first-test values:

| Setting | Value |
| --- | ---: |
| Spindle speed | 10,000 RPM |
| Isolation horizontal feed | 120 mm/min |
| Vertical feed | 60 mm/min |
| Isolation depth | 0.05 mm in two equal passes |
| Effective V-bit cut width | 0.20 mm |
| Isolation width | 0.40 mm |
| Safe Z | 2.0 mm |
| Drill depth | 1.8 mm |

The SainSmart PCB guide gives an isolation depth range from 0.01 mm through
0.05 mm. Tests on the installed copper blank gave a cleaner result with two
equal passes to 0.05 mm. Confirm that height compensation is applied. Copper
thickness, tool tip width, spindle runout, and board flatness change the
result.

There is no fixed blank-separation file. Its Y coordinate depends on the
measured blank height. Do not use an old `espnoise-panel-separate.nc` file.

## Make and test the coupon

Run the build script. Use the files that start with `coupon-`.

1. Fix a small FR-4 test piece to the spoilboard with its user face up.
2. Confirm that the clamps are outside the 30 mm by 15 mm job area.
3. Set work X/Y zero at the coupon lower-left corner.
4. Install the 2.0 mm drill. Set Z zero.
5. Run `coupon-drill-2.0mm.nc`.
6. Install the V-bit. Set Z zero. Make a height map for 30 mm by 15 mm.
7. Run `coupon-user-face.nc`.
8. Check that each copper path is continuous and isolated.
9. Put two smooth 2.0 mm pins into the spoilboard holes.
10. Flip the coupon from left to right. Put it on the pins and clamp it.
11. Set Z zero and make a new height map.
12. Run `coupon-internal-face.nc`.
13. Check the front-to-back alignment at the 0.8 mm via holes.
14. Run the 0.8 mm, 0.9 mm, and 1.0 mm drill jobs with the matching drills.
15. Install the 1.0 mm PCB router bit. Set Z zero.
16. Fix both sides of the coupon separation line to the spoilboard.
17. Run `coupon-separate.nc` last.

The coupon cut at Y = 13.5 mm removes a narrow edge strip. Check the cut wall.
It must not have large fibers, burns, or a large burr. Reduce the feed only if
the tool or machine needs it. Stop if the tool bends, chatters, or becomes hot.

Use the multimeter continuity mode. Adjacent copper paths must not connect.
Each complete path must have low resistance. Drill holes must keep the complete
annular ring. The front and back via pads must be concentric.

If copper remains between two paths, first check the height map and the tool
tip. Increase the depth by only 0.01 mm. Do not use an isolation depth below
-0.05 mm for this first test. If a cut is too wide, reduce the depth or use the
smaller-angle V-bit. Change `zwork` or `mill-diameters` in both millproject
files. Then run the build script again.

## Mill two units on one blank

Use a new blank after all coupon checks pass.

1. Measure and record the blank length, height, and thickness. Stop if its
   length is less than 69 mm or its height is less than 49 mm.
2. Mark one face `USER` and mark its lower-left corner.
3. Fix the complete blank with the user face up.
4. Set X/Y zero at the marked lower-left corner.
5. Install the 2.0 mm drill and set Z zero.
6. Run `espnoise-unit-drill-2.0mm.nc`.
7. Install the validated V-bit and set Z zero.
8. Make a height map for the first 69 mm by 24.5 mm reference area.
9. Run `espnoise-unit-user-face.nc`.
10. Check the isolation. Rotate the blank by 180 degrees in its plane.
11. Set X/Y zero at the new lower-left corner. Set Z zero and make a new
    height map for the second unit area.
12. Run `espnoise-unit-drill-2.0mm.nc` and `espnoise-unit-user-face.nc` again.
13. Record the measured blank length. Flip the blank from left to right. Do
    not rotate it in its plane during this face flip. Put it against the corner
    stops.
14. Set X zero inward from the presented left edge by `length - 69.0 mm`.
    Keep Y zero at the presented lower edge. For a 69.0 mm blank, X zero is on
    the edge.
15. Set Z zero, make a new height map, and run
    `espnoise-unit-internal-face.nc`.
16. Rotate the blank by 180 degrees in its plane. Set X/Y zero with the same
    69 mm reference rule. Make a new height map. Run
    `espnoise-unit-internal-face.nc` again.
17. Flip the blank back to the `USER` face. Use the same two user-face
    orientations to run the 0.8 mm, 0.9 mm, 1.0 mm, and 1.2 mm unit drill
    files. Set Z zero after each tool change.
18. Do all electrical checks before you separate the two units.
19. Measure the center space between the two unit areas. Only make a router
    cut if its complete 1.0 mm kerf stays outside both unit areas.
20. Clamp both future parts. Set Z zero and do a safe-Z dry run of a cut that
    uses the measured blank height. Do not use the removed fixed center file.
21. Vacuum the closed machine. Lightly remove edge burrs.
22. Wash the PCBs with isopropyl alcohol and let them dry.

Do not hold a PCB by hand during the separation cut. Do not use only one clamp
for the complete panel. The two free parts can move when the cut finishes. Use
low-profile clamps on both halves, or use strong thin double-face fixture tape
under both halves. Make sure that the tool cannot touch a clamp.

## Electrical check before solder

Do not connect power during these checks.

1. Check each adjacent PWR1, J_ESP32, J_LED, switch, MIC1, and BZ1 pad pair
   for a short circuit.
2. Check `+5V_IN` to GND and `+5V_PERIPH` to GND. Both results must be open.
3. Check each track from one listed endpoint to the other endpoint.
4. Check that each registration hole has no copper contact.
5. Compare diode, transistor, buzzer, and wire-pad marks with the schematic
   and netlist.

Do not repair a narrow gap with a powered rotary tool. Disconnect the board.
Use a fine knife or a small hand tool under magnification.

## Wire vias and solder order

This home-milled board has no plated holes. Install all 0.8 mm wire vias before
you install a component:

1. Put tinned 0.5 mm solid copper wire through each wire-via hole.
2. Solder the wire on both copper faces.
3. Cut the wire close to both solder joints.
4. Check continuity through each via.
5. Check that each via has no short to an adjacent path.

This revision needs no insulated link wires.

Install low parts first. Install the resistors, diode, transistor, and fuse.
Install the insulated wires in PWR1, J_ESP32, and J_LED. Add strain relief to
the wires, but do not cover a pad or a bare copper path. Install the user-face
switches, microphone module, and buzzer last.

Confirm the `2N3904` E-B-C pin order from its data sheet. Confirm the INMP441
module pin labels. Do not install a part only from its seller title.

## First power test

Keep J_ESP32 and J_LED disconnected for the first test. Put SW2 in the
buzzer-off position.

1. Put a current-limited 5 V supply on PWR1.
2. Start with a 100 mA current limit.
3. Confirm 5 V at J_ESP32-1 and after F1 at J_LED-1.
4. Disconnect power. Connect J_ESP32-1 through J_ESP32-7 and J_ESP32-9. Keep
   J_ESP32-8 disconnected.
5. Test the microphone before you connect the LED strip.
6. Test one SK6812 RGBW pixel through J_LED at no more than the present
   brightness limit.
7. Connect all 10 to 12 pixels only after the one-pixel test passes.
8. Connect J_ESP32-8. Test the buzzer driver and its hard switch last.

Keep the external USB-C power input separate from the ESP32 firmware-service
port. Do not power both inputs at the same time. The buzzer switch must stay in
the buzzer power wire.
