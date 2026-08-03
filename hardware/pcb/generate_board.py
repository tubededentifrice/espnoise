#!/usr/bin/env python3
"""Generate the ESPNoise carrier PCB and JLCPCB assembly tables.

Run this file with the Python interpreter in KiCad 10. The generated board is
the controlled PCB layout source for this project.
"""

from __future__ import annotations

import csv
import os
from pathlib import Path

import pcbnew


HERE = Path(__file__).resolve().parent
BOARD_FILE = HERE / "espnoise-carrier.kicad_pcb"
JLC_DIR = HERE / "jlcpcb"
FP_ROOT = Path(
    os.environ.get(
        "KICAD_FOOTPRINT_DIR",
        "/Volumes/KiCad/KiCad/KiCad.app/Contents/SharedSupport/footprints",
    )
)


def mm(value: float) -> int:
    return pcbnew.FromMM(value)


def point(x: float, y: float) -> pcbnew.VECTOR2I:
    return pcbnew.VECTOR2I_MM(x, y)


board = pcbnew.BOARD()


NET_NAMES = [
    "GND",
    "+5V_IN",
    "+5V_PERIPH",
    "+5V_BUZZER_SW",
    "+3V3",
    "MIC_SCK",
    "MIC_WS",
    "MIC_SD",
    "LED_DATA_3V3",
    "LED_DATA_5V_RAW",
    "LED_DATA_5V",
    "BUZZER_PWM",
    "BUZZER_BASE",
    "BUZZER_COLLECTOR",
    "MUTE_N",
]

nets: dict[str, pcbnew.NETINFO_ITEM] = {}
for name in NET_NAMES:
    net = pcbnew.NETINFO_ITEM(board, name)
    board.Add(net)
    nets[name] = net


placements: list[dict[str, object]] = []


def load_footprint(library: str, name: str) -> pcbnew.FOOTPRINT:
    if library == "ESPNoise":
        path = HERE / "footprints"
    else:
        path = FP_ROOT / f"{library}.pretty"
    fp = pcbnew.FootprintLoad(str(path), name)
    if fp is None:
        raise RuntimeError(f"Cannot load footprint {library}:{name} from {path}")
    return fp


def add_footprint(
    library: str,
    name: str,
    ref: str,
    value: str,
    x: float,
    y: float,
    *,
    side: str = "Bottom",
    rotation: float = 0,
    lcsc: str = "",
    manufacturer: str = "",
    mpn: str = "",
    description: str = "",
    place: bool = True,
) -> pcbnew.FOOTPRINT:
    fp = load_footprint(library, name)
    fp.SetReference(ref)
    fp.SetValue(value)
    fp.SetPosition(point(x, y))
    fp.SetOrientationDegrees(rotation)
    board.Add(fp)
    if side == "Bottom":
        fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_TOP_BOTTOM)
    if lcsc:
        fp.SetField("LCSC", lcsc)
    if manufacturer:
        fp.SetField("Manufacturer", manufacturer)
    if mpn:
        fp.SetField("MPN", mpn)
    if description:
        fp.SetField("Description", description)
    for field in fp.GetFields():
        field.SetVisible(False)
    placements.append(
        {
            "ref": ref,
            "value": value,
            "footprint": name,
            "x": x,
            "y": y,
            "side": side,
            "rotation": rotation,
            "actual_rotation": float(fp.GetOrientationDegrees()) % 360.0,
            "lcsc": lcsc,
            "manufacturer": manufacturer,
            "mpn": mpn,
            "description": description,
            "place": place,
        }
    )
    return fp


def set_pad_nets(fp: pcbnew.FOOTPRINT, mapping: dict[str, str]) -> None:
    found: set[str] = set()
    for pad in fp.Pads():
        number = str(pad.GetNumber())
        if number in mapping:
            pad.SetNet(nets[mapping[number]])
            found.add(number)
    missing = set(mapping) - found
    if missing:
        raise RuntimeError(f"Missing pads on {fp.GetReference()}: {sorted(missing)}")


def pad(fp: pcbnew.FOOTPRINT, number: str) -> pcbnew.PAD:
    for candidate in fp.Pads():
        if str(candidate.GetNumber()) == str(number):
            return candidate
    raise KeyError(f"{fp.GetReference()} pad {number}")


def xy(item: pcbnew.BOARD_ITEM) -> tuple[float, float]:
    pos = item.GetPosition()
    return pcbnew.ToMM(pos.x), pcbnew.ToMM(pos.y)


def add_track(
    net_name: str,
    start: tuple[float, float],
    end: tuple[float, float],
    *,
    width: float = 0.25,
    layer: int = pcbnew.B_Cu,
) -> None:
    if start == end:
        return
    track = pcbnew.PCB_TRACK(board)
    track.SetStart(point(*start))
    track.SetEnd(point(*end))
    track.SetWidth(mm(width))
    track.SetLayer(layer)
    track.SetNet(nets[net_name])
    board.Add(track)


def route(
    net_name: str,
    points: list[tuple[float, float]],
    *,
    width: float = 0.25,
    layer: int = pcbnew.B_Cu,
) -> None:
    for start, end in zip(points, points[1:]):
        add_track(net_name, start, end, width=width, layer=layer)


def add_via(
    net_name: str,
    location: tuple[float, float],
    *,
    size: float = 0.70,
    drill: float = 0.35,
) -> None:
    via = pcbnew.PCB_VIA(board)
    via.SetPosition(point(*location))
    via.SetWidth(mm(size))
    via.SetDrill(mm(drill))
    via.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
    via.SetNet(nets[net_name])
    board.Add(via)


def route_with_vias(
    net_name: str,
    start: tuple[float, float],
    start_via: tuple[float, float],
    front_points: list[tuple[float, float]],
    end_via: tuple[float, float],
    end: tuple[float, float],
    *,
    width: float = 0.25,
) -> None:
    route(net_name, [start, start_via], width=width, layer=pcbnew.B_Cu)
    add_via(net_name, start_via)
    route(
        net_name,
        [start_via, *front_points, end_via],
        width=width,
        layer=pcbnew.F_Cu,
    )
    add_via(net_name, end_via)
    route(net_name, [end_via, end], width=width, layer=pcbnew.B_Cu)


def add_edge(start: tuple[float, float], end: tuple[float, float]) -> None:
    shape = pcbnew.PCB_SHAPE(board)
    shape.SetShape(pcbnew.SHAPE_T_SEGMENT)
    shape.SetStart(point(*start))
    shape.SetEnd(point(*end))
    shape.SetLayer(pcbnew.Edge_Cuts)
    shape.SetWidth(mm(0.10))
    board.Add(shape)


for a, b in [
    ((0, 0), (96, 0)),
    ((96, 0), (96, 38)),
    ((96, 38), (0, 38)),
    ((0, 38), (0, 0)),
]:
    add_edge(a, b)


def add_text(text: str, x: float, y: float, layer: int, size: float = 1.0) -> None:
    item = pcbnew.PCB_TEXT(board)
    item.SetText(text)
    item.SetPosition(point(x, y))
    item.SetLayer(layer)
    item.SetTextSize(point(size, size))
    item.SetTextThickness(mm(0.15))
    if layer == pcbnew.B_SilkS:
        item.SetMirrored(True)
    board.Add(item)


# Mounting holes are for a new printed carrier or standoffs. Their positions do
# not claim compatibility with the present enclosure.
for ref, x, y in [("H1", 4, 4), ("H2", 92, 4)]:
    add_footprint(
        "MountingHole",
        "MountingHole_3.2mm_M3",
        ref,
        "M3 mounting hole",
        x,
        y,
        side="Top",
        place=False,
        description="3.2 mm non-plated mounting hole",
    )


# The two switch centers follow the measured openings in the current case.
sw2 = add_footprint(
    "ESPNoise",
    "ESPNoise_7x7_DPDT_Pushbutton",
    "SW2",
    "BUZZER ENABLE",
    22.9,
    11.4,
    side="Top",
    lcsc="C5379891",
    manufacturer="SHOU HAN",
    mpn="7-7 ZS",
    description="7x7 mm DPDT latching pushbutton; extended state enables buzzer",
)
set_pad_nets(sw2, {"1": "+5V_BUZZER_SW", "2": "+5V_PERIPH"})

sw1 = add_footprint(
    "ESPNoise",
    "ESPNoise_7x7_DPDT_Pushbutton",
    "SW1",
    "MUTE",
    52.9,
    10.1,
    side="Top",
    lcsc="C5379890",
    manufacturer="SHOU HAN",
    mpn="7-7 WS",
    description="7x7 mm DPDT momentary pushbutton",
)
set_pad_nets(sw1, {"2": "MUTE_N", "3": "GND"})


j2 = add_footprint(
    "Connector_JST",
    "JST_PH_B10B-PH-SM4-TB_1x10-1MP_P2.00mm_Vertical",
    "J2",
    "CONTROLLER",
    15,
    31,
    lcsc="C265112",
    manufacturer="JST",
    mpn="B10B-PH-SM4-TBT(LF)(SN)",
    description="Controller adapter cable, JST PH 10 pin, lower face",
)
set_pad_nets(
    j2,
    {
        "1": "+5V_IN",
        "2": "GND",
        "3": "+3V3",
        "4": "MIC_SCK",
        "5": "MIC_WS",
        "6": "MIC_SD",
        "7": "LED_DATA_3V3",
        "8": "BUZZER_PWM",
        "9": "MUTE_N",
        "10": "GND",
    },
)

j4 = add_footprint(
    "Connector_JST",
    "JST_PH_B6B-PH-SM4-TB_1x06-1MP_P2.00mm_Vertical",
    "J4",
    "MICROPHONE",
    37,
    31,
    lcsc="C265088",
    manufacturer="JST",
    mpn="B6B-PH-SM4-TBT(LF)(SN)",
    description="INMP441 cable, JST PH 6 pin, lower face",
)
set_pad_nets(j4, {"1": "+3V3", "2": "GND", "3": "MIC_SCK", "4": "MIC_WS", "5": "MIC_SD", "6": "GND"})

j3 = add_footprint(
    "Connector_JST",
    "JST_PH_B5B-PH-SM4-TB_1x05-1MP_P2.00mm_Vertical",
    "J3",
    "LED STRIP",
    53.5,
    31,
    lcsc="C265086",
    manufacturer="JST",
    mpn="B5B-PH-SM4-TBT(LF)(SN)",
    description="SK6812 RGBW cable with power at both strip ends, lower face",
)
set_pad_nets(j3, {"1": "+5V_PERIPH", "2": "GND", "3": "LED_DATA_5V", "4": "+5V_PERIPH", "5": "GND"})

j1 = add_footprint(
    "Connector_JST",
    "JST_PH_B2B-PH-SM4-TB_1x02-1MP_P2.00mm_Vertical",
    "J1",
    "5V INPUT",
    66,
    31,
    lcsc="C265003",
    manufacturer="JST",
    mpn="B2B-PH-SM4-TBT(LF)(SN)",
    description="External power-only USB-C module cable, lower face",
)
set_pad_nets(j1, {"1": "+5V_IN", "2": "GND"})

j5 = add_footprint(
    "Connector_JST",
    "JST_PH_B2B-PH-SM4-TB_1x02-1MP_P2.00mm_Vertical",
    "J5",
    "BUZZER",
    76.5,
    31,
    lcsc="C265003",
    manufacturer="JST",
    mpn="B2B-PH-SM4-TBT(LF)(SN)",
    description="Passive piezo buzzer cable, lower face",
)
set_pad_nets(j5, {"1": "+5V_BUZZER_SW", "2": "BUZZER_COLLECTOR"})


u1 = add_footprint(
    "Package_SO",
    "TSSOP-14_4.4x5mm_P0.65mm",
    "U1",
    "SN74AHCT125PWR",
    47,
    21,
    rotation=90,
    lcsc="C36365",
    manufacturer="Texas Instruments",
    mpn="SN74AHCT125PWR",
    description="5 V AHCT quad buffer for SK6812 data",
)
set_pad_nets(
    u1,
    {
        "1": "GND",
        "2": "LED_DATA_3V3",
        "3": "LED_DATA_5V_RAW",
        "4": "+5V_PERIPH",
        "5": "GND",
        "7": "GND",
        "9": "GND",
        "10": "+5V_PERIPH",
        "12": "GND",
        "13": "+5V_PERIPH",
        "14": "+5V_PERIPH",
    },
)

c1 = add_footprint(
    "Capacitor_SMD",
    "C_0603_1608Metric",
    "C1",
    "100nF",
    42,
    21,
    rotation=90,
    lcsc="C14663",
    manufacturer="Yageo",
    mpn="CC0603KRX7R9BB104",
    description="AHCT bypass capacitor, 50 V X7R",
)
set_pad_nets(c1, {"1": "+5V_PERIPH", "2": "GND"})

r1 = add_footprint(
    "Resistor_SMD",
    "R_0603_1608Metric",
    "R1",
    "330R",
    54,
    21,
    rotation=90,
    lcsc="C23138",
    manufacturer="UNI-ROYAL",
    mpn="0603WAF3300T5E",
    description="SK6812 series data resistor",
)
set_pad_nets(r1, {"1": "LED_DATA_5V_RAW", "2": "LED_DATA_5V"})

f1 = add_footprint(
    "Fuse",
    "Fuse_1206_3216Metric",
    "F1",
    "0.5A PTC",
    65,
    22,
    lcsc="C163512",
    manufacturer="Littelfuse",
    mpn="1206L050YR",
    description="0.50 A hold resettable fuse, 6 V",
)
set_pad_nets(f1, {"1": "+5V_IN", "2": "+5V_PERIPH"})

c2 = add_footprint(
    "Capacitor_SMD",
    "CP_Elec_10x10.5",
    "C2",
    "1000uF 16V",
    88.5,
    22,
    lcsc="C970714",
    manufacturer="DMBJ",
    mpn="RVT1C102M1010",
    description="LED rail bulk capacitor, 105 C, observe polarity",
)
set_pad_nets(c2, {"1": "+5V_PERIPH", "2": "GND"})

q1 = add_footprint(
    "Package_TO_SOT_SMD",
    "SOT-23",
    "Q1",
    "MMBT3904",
    76,
    21,
    rotation=90,
    lcsc="C181119",
    manufacturer="Hottech",
    mpn="MMBT3904",
    description="NPN low-side buzzer driver; pin 1 base, 2 emitter, 3 collector",
)
set_pad_nets(q1, {"1": "BUZZER_BASE", "2": "GND", "3": "BUZZER_COLLECTOR"})

r2 = add_footprint(
    "Resistor_SMD",
    "R_0603_1608Metric",
    "R2",
    "5.1k",
    70,
    18,
    lcsc="C23186",
    manufacturer="UNI-ROYAL",
    mpn="0603WAF5101T5E",
    description="Buzzer transistor base resistor",
)
set_pad_nets(r2, {"1": "BUZZER_PWM", "2": "BUZZER_BASE"})

r3 = add_footprint(
    "Resistor_SMD",
    "R_0603_1608Metric",
    "R3",
    "100k",
    76,
    16,
    rotation=90,
    lcsc="C25803",
    manufacturer="UNI-ROYAL",
    mpn="0603WAF1003T5E",
    description="Buzzer transistor base pull-down",
)
set_pad_nets(r3, {"1": "BUZZER_BASE", "2": "GND"})


# The four microphone signals use separate upper and lower paths. Two signals
# change layer so no route crosses another route.
route("+3V3", [xy(pad(j2, "3")), (10.0, 36.0), (32.0, 36.0), xy(pad(j4, "1"))])
route("MIC_WS", [xy(pad(j2, "5")), (14.0, 25.0), (38.0, 25.0), xy(pad(j4, "4"))])
route("MIC_SCK", [xy(pad(j2, "4")), (12.0, 33.5)], layer=pcbnew.B_Cu)
add_via("MIC_SCK", (12.0, 33.5))
route("MIC_SCK", [(12.0, 33.5), (12.0, 35.0), (36.0, 35.0), (36.0, 33.5)], layer=pcbnew.F_Cu)
add_via("MIC_SCK", (36.0, 33.5))
route("MIC_SCK", [(36.0, 33.5), xy(pad(j4, "3"))], layer=pcbnew.B_Cu)
route("MIC_SD", [xy(pad(j2, "6")), (16.0, 29.0)], layer=pcbnew.B_Cu)
add_via("MIC_SD", (16.0, 29.0))
route("MIC_SD", [(16.0, 29.0), (16.0, 27.0), (40.0, 27.0), (40.0, 29.0)], layer=pcbnew.F_Cu)
add_via("MIC_SD", (40.0, 29.0))
route("MIC_SD", [(40.0, 29.0), xy(pad(j4, "5"))], layer=pcbnew.B_Cu)

# The input rail splits before the fuse. It supplies the controller directly.
j2_5v = xy(pad(j2, "1"))
j1_5v = xy(pad(j1, "1"))
route("+5V_IN", [j2_5v, (6.0, 34.5)], width=0.90)
add_via("+5V_IN", (6.0, 34.5))
route("+5V_IN", [(6.0, 34.5), (6.0, 36.5), (65.0, 36.5), (65.0, 34.5)], width=0.90, layer=pcbnew.F_Cu)
add_via("+5V_IN", (65.0, 34.5))
route("+5V_IN", [(65.0, 34.5), j1_5v], width=0.90)
f1_in = xy(pad(f1, "1"))
route("+5V_IN", [j1_5v, (62.0, 30.5), (62.0, 28.0)], width=0.90)
add_via("+5V_IN", (62.0, 28.0))
route("+5V_IN", [(62.0, 28.0), (69.0, 20.0), (63.6, 20.0)], width=0.90, layer=pcbnew.F_Cu)
add_via("+5V_IN", (63.6, 20.0))
route("+5V_IN", [(63.6, 20.0), f1_in], width=0.90)

# The fused rail uses a 1.0 mm lower-face trunk.
f1_out = xy(pad(f1, "2"))
route("+5V_PERIPH", [f1_out, (66.4, 26.2), (42.0, 26.2)], width=0.80)
route("+5V_PERIPH", [f1_out, (84.3, 26.2), xy(pad(c2, "1"))], width=0.80)
for target in [pad(j3, "1"), pad(j3, "4")]:
    target_xy = xy(target)
    route("+5V_PERIPH", [(target_xy[0], 26.2), target_xy], width=0.80)
route("+5V_PERIPH", [(42.0, 26.2), (40.0, 26.2), (40.0, 20.23), xy(pad(c1, "1"))], width=0.45)
for target in [pad(u1, "14"), pad(u1, "13"), pad(u1, "10")]:
    target_xy = xy(target)
    route("+5V_PERIPH", [(target_xy[0], 26.2), target_xy], width=0.35)
route("+5V_PERIPH", [xy(pad(u1, "4")), (47.0, 16.0), (51.0, 16.0), (51.0, 26.2)], width=0.35)

# Pin 1 and pin 2 of SW2 are connected when the plunger is extended.
route("+5V_PERIPH", [(61.0, 26.2), (61.0, 10.1), (27.0, 10.1), (27.0, 5.5), (22.9, 5.5), xy(pad(sw2, "2"))], width=0.70)
route("+5V_BUZZER_SW", [xy(pad(sw2, "1")), (18.5, 8.9), (18.5, 3.5), (85.0, 3.5), (85.0, 30.0), (74.0, 30.0)], width=0.70, layer=pcbnew.F_Cu)
add_via("+5V_BUZZER_SW", (74.0, 30.0))
route("+5V_BUZZER_SW", [(74.0, 30.0), xy(pad(j5, "1"))], width=0.70)

# LED data buffer.
route("LED_DATA_3V3", [xy(pad(j2, "7")), (18.0, 29.0)])
add_via("LED_DATA_3V3", (18.0, 29.0))
route("LED_DATA_3V3", [(18.0, 29.0), (18.0, 31.3), (44.0, 31.3), (44.0, 16.0), (45.7, 16.0)], layer=pcbnew.F_Cu)
add_via("LED_DATA_3V3", (45.7, 16.0), size=0.60, drill=0.30)
route("LED_DATA_3V3", [(45.7, 16.0), xy(pad(u1, "2"))])
route("LED_DATA_5V_RAW", [xy(pad(u1, "3")), (46.35, 14.5), (54.0, 14.5), xy(pad(r1, "1"))])
route("LED_DATA_5V", [xy(pad(r1, "2")), (56.0, 21.83)])
add_via("LED_DATA_5V", (56.0, 21.83))
route("LED_DATA_5V", [(56.0, 21.83), (58.0, 27.0), (58.0, 29.0), (53.5, 29.0)], layer=pcbnew.F_Cu)
add_via("LED_DATA_5V", (53.5, 29.0))
route("LED_DATA_5V", [(53.5, 29.0), xy(pad(j3, "3"))])

# Mute uses the top layer and approaches the center switch pin from the board
# edge. This avoids the unused pin in the second switch row.
route("MUTE_N", [xy(pad(j2, "9")), (22.0, 33.5)])
add_via("MUTE_N", (22.0, 33.5))
route("MUTE_N", [(22.0, 33.5), (24.0, 32.5), (70.0, 32.5), (70.0, 15.0), (75.0, 15.0), (75.0, 5.5), (52.9, 5.5), xy(pad(sw1, "2"))], layer=pcbnew.F_Cu)

# Buzzer driver.
route("BUZZER_PWM", [xy(pad(j2, "8")), (20.0, 29.0)])
add_via("BUZZER_PWM", (20.0, 29.0))
route("BUZZER_PWM", [(20.0, 29.0), (20.0, 30.0), (42.0, 30.0), (42.0, 23.5), (28.0, 23.5), (28.0, 11.0), (68.0, 11.0), (68.0, 18.0)], layer=pcbnew.F_Cu)
add_via("BUZZER_PWM", (68.0, 18.0))
route("BUZZER_PWM", [(68.0, 18.0), xy(pad(r2, "1"))])
route("BUZZER_BASE", [xy(pad(r2, "2")), xy(pad(q1, "1"))])
route("BUZZER_BASE", [xy(pad(q1, "1")), (73.5, 16.0), xy(pad(r3, "1"))])
route("BUZZER_COLLECTOR", [xy(pad(q1, "3")), (78.0, 21.94)])
add_via("BUZZER_COLLECTOR", (78.0, 21.94))
route("BUZZER_COLLECTOR", [(78.0, 21.94), (80.0, 26.5), (80.0, 28.0), (77.5, 28.0)], width=0.50, layer=pcbnew.F_Cu)
add_via("BUZZER_COLLECTOR", (77.5, 28.0))
route("BUZZER_COLLECTOR", [(77.5, 28.0), xy(pad(j5, "2"))], width=0.50)


def add_ground_zone(layer: int) -> None:
    zone = pcbnew.ZONE(board)
    zone.SetLayer(layer)
    zone.SetNet(nets["GND"])
    zone.SetLocalClearance(mm(0.25))
    zone.SetMinThickness(mm(0.20))
    zone.SetThermalReliefGap(mm(0.25))
    zone.SetThermalReliefSpokeWidth(mm(0.30))
    zone.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
    outline = zone.Outline()
    outline.NewOutline()
    for x, y in [(0.5, 0.5), (95.5, 0.5), (95.5, 37.5), (0.5, 37.5)]:
        outline.Append(point(x, y))
    board.Add(zone)


add_ground_zone(pcbnew.F_Cu)
add_ground_zone(pcbnew.B_Cu)

add_text("ESPNoise carrier rev A", 48, 2.2, pcbnew.F_SilkS, 1.2)
add_text("BUZZER ENABLE", 22.9, 5.2, pcbnew.F_SilkS, 0.9)
add_text("EXTENDED = ON", 22.9, 17.8, pcbnew.F_SilkS, 0.8)
add_text("MUTE", 52.9, 4.5, pcbnew.F_SilkS, 0.9)
add_text("LOWER FACE - CABLES DOWN", 48, 6.2, pcbnew.B_SilkS, 1.0)
add_text("J2 CTRL  J4 MIC  J3 LED  J1 5V  J5 BUZZ", 48, 36.6, pcbnew.B_SilkS, 0.75)


pcbnew.ZONE_FILLER(board).Fill(board.Zones())
pcbnew.SaveBoard(str(BOARD_FILE), board)


JLC_DIR.mkdir(parents=True, exist_ok=True)

with (JLC_DIR / "espnoise-carrier-bom.csv").open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
    groups: dict[tuple[str, str, str], list[str]] = {}
    for item in placements:
        if not item["place"] or not item["lcsc"]:
            continue
        key = (str(item["value"]), str(item["footprint"]), str(item["lcsc"]))
        groups.setdefault(key, []).append(str(item["ref"]))
    for (value, footprint, lcsc), refs in sorted(groups.items()):
        writer.writerow([value, ",".join(sorted(refs)), footprint, lcsc])

with (JLC_DIR / "espnoise-carrier-cpl.csv").open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    for item in sorted(placements, key=lambda row: str(row["ref"])):
        if not item["place"] or not item["lcsc"]:
            continue
        writer.writerow(
            [
                item["ref"],
                f"{item['x']:.3f}mm",
                f"{item['y']:.3f}mm",
                item["side"],
                f"{item['actual_rotation']:.1f}",
            ]
        )

with (JLC_DIR / "espnoise-carrier-parts.csv").open("w", newline="", encoding="utf-8") as handle:
    fields = ["ref", "value", "manufacturer", "mpn", "lcsc", "side", "description"]
    writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(sorted(placements, key=lambda row: str(row["ref"])))

print(f"Generated {BOARD_FILE}")
print(f"Generated JLCPCB BOM and CPL in {JLC_DIR}")
