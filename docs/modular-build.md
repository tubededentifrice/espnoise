# Modular build stages

Do not build all functions at the same time. Complete and test one stage before
you add the next stage.

## Module interfaces

Use plugs between the modules. Do not solder each external module directly to
the ESP32 board.

| Module | Connector | Pins |
| --- | --- | --- |
| 5 V sign power | JST-XH-2 | `5V`, `GND` |
| Microphone | JST-XH-6 | `3V3`, `GND`, `SCK`, `WS`, `SD`, `L/R` |
| LED sign | JST-XH-3 | `5V`, `GND`, `DATA` |
| Mute button | JST-XH-2 | `GPIO27`, `GND` |
| Buzzer | JST-XH-2 | `SWITCHED_5V`, `COLLECTOR` |
| Optional power control | JST-XH-3 | `BAT`, `GND`, `ENABLE` |

Mark pin 1 on each plug and socket. Use different pin counts where possible so
that one module cannot connect to the wrong socket.

The production carrier PCB replaces these prototype plugs with JST PH
connectors. It combines controller signals in J2 and supplies LED power at both
strip ends through J3. Use `hardware/pcb/controller-adapters.md` as the
production connector table. Do not use the prototype JST-XH pin count as a
carrier PCB pin count.

## Stage 0: Two-wire USB-C power module

Test the two-wire USB-C connector before you connect it to the ESP32:

1. Keep its red and black wires disconnected from all circuits.
2. Connect a USB-C to USB-C cable and a 5 V USB-C supply.
3. Measure between the red and black wires.
4. Reverse the USB-C cable plug and measure again.
5. Use the connector if both measurements are from 4.75 V to 5.25 V.

If both measurements are zero, the connector probably has no CC pull-down
resistors. If it exposes separate CC1 and CC2 pads, connect one 5.1 kohm
resistor from each pad to GND. Do not combine CC1 and CC2. If the connector
exposes only red and black wires, the resistors cannot be added to it.

The [USB-C compatibility repair](usb-c-repair.md) is an optional advanced
method. It is not necessary when the input module has the two correct CC
pull-down resistors.

## Stage 1: ESP32 and USB power

Use the full-size USB-C ESP32. Connect no other modules.

1. Connect the two-wire power module red wire to the ESP32 `5V` or `VIN` pin.
2. Connect its black wire to ESP32 GND.
3. Connect a regulated 5 V USB supply rated for at least 2 A.
4. Confirm that the ESP32 starts.
5. Measure from the board `5V` or `VIN` pin to GND.
6. Continue only if the value is from 4.75 V to 5.25 V.

Use a removable two-pin plug between the power module and the rest of the
circuit. Disconnect this plug before you connect the ESP32 service USB port to
a computer.

## Stage 2: Microphone

Connect only the INMP441 module. Upload the `esp32dev` firmware and use the
serial monitor. Confirm that quiet and loud sounds give different dBFS values.

## Stage 3: One LED pixel

Build the AHCT level-change circuit. Connect one SK6812 pixel with the 330 ohm
data resistor, 100 nF AHCT capacitor, and 1,000 uF rail capacitor. Supply it
from the fused peripheral branch of the two-wire power module.

Confirm red, green, blue, and warm-white operation. If the colors are wrong,
change the firmware pixel order. Do not continue until one pixel is correct.

## Stage 4: Complete sign

Connect 10 pixels. Supply 5 V and GND at both ends of the strip. Keep the
firmware brightness at 25% or less. Measure the 5 V rail while the sign flashes.
It must stay above 4.75 V.

## Stage 5: Controls

Add the 30-minute mute button. Test its action during a sample and during an
alarm. Then add the physical buzzer switch and the tested 2N3904 driver
circuit.

## Stage 6: Prototype case

Make a simple test case or open frame. Test the microphone position and the
diffuser before you make the final enclosure.

## Stage 7: Optional battery power

Do not add this stage until the USB-powered unit is stable and its current is
measured. A battery module must present the same 5 V and GND interface to the
sign. The detector and control modules do not change.

If the full-size ESP32 remains in use, the future battery module needs a
protected cell, a charger with load sharing, and a 5 V boost supply. Do not
connect a battery directly to this ESP32 board.
