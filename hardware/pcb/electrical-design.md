# Electrical design

The carrier is for the USB-powered ESPNoise build. It includes the microphone
and buzzer. It does not include a battery charger, lithium cell, boost
converter, ESP32 module, LED strip, or external USB-C socket.

## Power path

J1 receives 5 V and GND from a power-only USB-C input module. The 5 V line
splits before F1. One branch goes directly to J2 for the removable controller.
The other branch goes through the 0.5 A resettable fuse to the LED buffer, LED
connector, bulk capacitor, and hard buzzer switch.

The external USB-C module must have one 5.1 kohm pull-down from CC1 to GND and
one 5.1 kohm pull-down from CC2 to GND. Do not combine CC1 and CC2. The
controller USB connector remains a separate firmware-service port.

## LED data

U1 is an SN74AHCT125 supplied from the fused 5 V rail. Channel 1 changes the
ESP32 3.3 V data to a 5 V data signal. R1 is the 330 ohm series resistor. C1 is
the 100 nF U1 bypass capacitor. C2 is the 1,000 uF LED rail capacitor.

J3 supplies the SK6812 RGB plus warm-white strip at both ends. The data path is
32-bit RGBW. Keep firmware brightness at 25% or less until power tests show
that a higher value is safe.

## Microphone

MIC1 is a TDK InvenSense ICS-43434 I2S microphone. It uses the same SCK, WS,
and SD interface as the prototype INMP441 module. Its L/R input is connected
to GND. C3 is its 100 nF supply bypass capacitor.

MIC1 is on the lower face and has a bottom acoustic port. Its footprint has a
0.5 mm non-plated hole. This hole faces the case top and is on the same board
centerline as the switches and buzzer.

## Buzzer and controls

SW2 is a DPDT push-push switch. The PCB uses one pole as a hard switch in the
buzzer 5 V wire. The switch data sheet connects pins 1 and 2 when the plunger
is extended. Thus, extended means buzzer enabled. The second pole is not used.

BZ1 is a 5 V passive electromagnetic buzzer. Its 2.4 kHz resonance agrees with
the red alarm tone. Q1 is an MMBT3904 low-side driver. R2 is 1 kohm and limits
the transistor base current. R3 keeps Q1 off while the controller starts or is
disconnected. D1 is the flyback diode for the buzzer coil.

SW1 is the matching momentary switch body. It connects `MUTE_N` to GND when
pressed. The controller supplies the input pull-up.

## Factory components

| Ref | Part | LCSC/JLCPCB ID |
| --- | --- | --- |
| U1 | SN74AHCT125PWR | C36365 |
| Q1 | MMBT3904 | C181119 |
| F1 | 1206L050YR, 0.5 A hold PTC | C163512 |
| C1, C3 | 100 nF, 0603 | C14663 |
| C2 | 1,000 uF, 10 V, 105 degrees C | C5246577 |
| D1 | 1N5819WS flyback diode | C191023 |
| R1 | 330 ohm, 0603 | C23138 |
| R2 | 1 kohm, 0603 | C21190 |
| R3 | 100 kohm, 0603 | C25803 |
| MIC1 | TDK InvenSense ICS-43434 | C5656610 |
| BZ1 | FUET FUET-1370F-05 | C2690507 |
| SW1 | SHOU HAN `7-7 WS`, momentary | C5379890 |
| SW2 | SHOU HAN `7-7 ZS`, latching | C5379891 |
| J1 | JST B2B-PH-SM4-TBT | C265003 |
| J2 | JST B10B-PH-SM4-TBT | C265112 |
| J3 | JST B5B-PH-SM4-TBT | C265086 |

Check the JLCPCB assembly library stock before each order. Do not replace an
AHCT part with an HC part or a generic MOSFET level shifter.
