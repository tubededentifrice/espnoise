# Genmitsu Cubiko first PCB guide

Use this guide for the ESPNoise Rev C two-unit panel. Do not start with the
70 mm by 50 mm blank. First use the 1:1 part check. Then use the coupon.

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

## Know the panel layout

The raw panel is 70 mm by 50 mm. Each finished PCB is 70 mm by 24.5 mm. The
1.0 mm router bit moves on Y = 25 mm. It removes the space from Y = 24.5 mm
through Y = 25.5 mm.

The second PCB has a 180-degree rotation in the panel data. Thus, the center
cut is the same local edge on both finished PCBs. Do not rotate the panel in
the machine to make this layout. The generated files already contain the
rotation.

The button centers, microphone acoustic center, and buzzer center are on one
straight line. This line is local Y = 12.25 mm on each finished PCB.

Before you mill copper, print `espnoise-component-fit-check.svg` at 100% scale.
Measure the printed 50 mm check line. It must be 50 mm. Put the real MIC1 and
BZ1 parts on the drawing. All leads must align with the hole centers. Update
the measured values in `generate_cnc_board.py`, rebuild the files, and repeat
this check. A screen view is not a physical fit check.

## Know the four coordinates

- Machine zero is the Cubiko home position. Do not change it.
- Work X/Y zero is the lower-left corner of the fixed 70 mm by 50 mm blank.
- Work Z zero is the measured copper surface for the installed tool.
- The internal-face job is already mirrored around X = 35 mm.

The two registration holes are on X = 35 mm. Flip the panel from left to
right. Do not flip it from top to bottom. The two pins keep the panel position.
Keep the same work X/Y zero after the flip. Make a new Z measurement and a new
height map for each face and after each tool change.

Do not add 70 mm to X after the flip. The generated internal-face G-code
already contains the mirror operation.

## Initial CAM values

The build files use these first-test values:

| Setting | Value |
| --- | ---: |
| Spindle speed | 10,000 RPM |
| Isolation horizontal feed | 120 mm/min |
| Vertical feed | 60 mm/min |
| Isolation depth | 0.04 mm |
| Effective V-bit cut width | 0.20 mm |
| Isolation width | 0.20 mm |
| Safe Z | 2.0 mm |
| Drill depth | 1.8 mm |
| Separation feed | 100 mm/min |
| Separation step-down | 0.4 mm |
| Separation final depth | 1.8 mm |

The SainSmart PCB guide gives an isolation depth range from 0.01 mm through
0.05 mm. This project starts at 0.04 mm. This value is a test value. Copper
thickness, tool tip width, spindle runout, and board flatness change the
result.

The separation depth is for nominal 1.6 mm FR-4 plus 0.2 mm into the
spoilboard. Measure your blank with a caliper. If its thickness is different,
change `cut.cut_depth` in `opendle-tools.toml`. Use the measured thickness plus
only 0.2 mm. Then run the shared CAM command again.

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

## Mill the two-unit panel

Use a new 70 mm by 50 mm blank after all coupon checks pass.

1. Measure the blank. Stop if a dimension is less than 70 mm by 50 mm.
2. Mark one face `USER` and mark its lower-left corner.
3. Fix the complete blank with the user face up.
4. Set X/Y zero at the marked lower-left corner.
5. Install the 2.0 mm drill and set Z zero.
6. Run `espnoise-panel-drill-2.0mm.nc` first. These holes set the flip axis.
7. Install the validated V-bit and set Z zero.
8. Make a height map for 70 mm by 50 mm.
9. Run `espnoise-panel-user-face.nc`.
10. Check the isolation before you remove the blank.
11. Put two smooth 2.0 mm pins into the registration holes and spoilboard.
12. Flip the panel from left to right. Keep the same X/Y zero.
13. Fix the panel. Set Z zero and make a new height map.
14. Run `espnoise-panel-internal-face.nc`.
15. Check the flip alignment at several wire-via pads.
16. Flip the panel back to the user face with the pins.
17. Run the 0.8 mm, 0.9 mm, 1.0 mm, and 1.2 mm panel drill jobs. Set Z zero
    after each tool change. The 1.2 mm holes are for the wire terminals.
18. Do all electrical checks while the two PCBs are still one panel.
19. Install the 1.0 mm PCB router bit and set Z zero.
20. Fix both future PCB halves to the spoilboard. Keep all clamps and tape
    clear of Y = 25 mm. Each half must stay fixed after the cut finishes.
21. Do a dry run at safe Z. Confirm the path from X = 0 through X = 70.
22. Run `espnoise-panel-separate.nc` last.
23. Vacuum the closed machine and the panel. Lightly remove edge burrs.
24. Wash the PCBs with isopropyl alcohol and let them dry.

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
