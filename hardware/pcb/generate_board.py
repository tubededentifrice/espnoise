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
    ((0, 0), (80, 0)),
    ((80, 0), (80, 20)),
    ((80, 20), (0, 20)),
    ((0, 20), (0, 0)),
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


# The user-facing parts share the board centerline. The microphone is on the
# lower face. Its bottom port listens through the non-plated PCB hole.
sw2 = add_footprint(
    "ESPNoise",
    "ESPNoise_7x7_DPDT_Pushbutton",
    "SW2",
    "BUZZER ENABLE",
    7.0,
    10.0,
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
    20.0,
    10.0,
    side="Top",
    lcsc="C5379890",
    manufacturer="SHOU HAN",
    mpn="7-7 WS",
    description="7x7 mm DPDT momentary pushbutton",
)
set_pad_nets(sw1, {"2": "MUTE_N", "3": "GND"})

mic1 = add_footprint(
    "Sensor_Audio",
    "InvenSense_ICS-43434-6_3.5x2.65mm",
    "MIC1",
    "ICS-43434",
    29.5,
    10.71,
    lcsc="C5656610",
    manufacturer="TDK InvenSense",
    mpn="ICS-43434",
    description="I2S bottom-port MEMS microphone; acoustic port faces the top through the PCB hole",
)
set_pad_nets(
    mic1,
    {"1": "MIC_WS", "2": "GND", "3": "GND", "4": "MIC_SCK", "5": "+3V3", "6": "MIC_SD"},
)

bz1 = add_footprint(
    "ESPNoise",
    "ESPNoise_FUET-1370F-05",
    "BZ1",
    "FUET-1370F-05",
    69.0,
    10.0,
    side="Top",
    lcsc="C2690507",
    manufacturer="FUET",
    mpn="FUET-1370F-05",
    description="5 V, 2.4 kHz passive electromagnetic buzzer with top sound port",
)
set_pad_nets(bz1, {"1": "+5V_BUZZER_SW", "2": "BUZZER_COLLECTOR"})


j2 = add_footprint(
    "Connector_JST",
    "JST_PH_B10B-PH-SM4-TB_1x10-1MP_P2.00mm_Vertical",
    "J2",
    "CONTROLLER",
    44.5,
    15.0,
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

j3 = add_footprint(
    "Connector_JST",
    "JST_PH_B5B-PH-SM4-TB_1x05-1MP_P2.00mm_Vertical",
    "J3",
    "LED STRIP",
    62.5,
    5.0,
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
    "USB-C 5V",
    75.2,
    5.0,
    lcsc="C265003",
    manufacturer="JST",
    mpn="B2B-PH-SM4-TBT(LF)(SN)",
    description="External power-only USB-C module cable, lower face",
)
set_pad_nets(j1, {"1": "+5V_IN", "2": "GND"})


u1 = add_footprint(
    "Package_SO",
    "TSSOP-14_4.4x5mm_P0.65mm",
    "U1",
    "SN74AHCT125PWR",
    39.5,
    5.0,
    rotation=0,
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
    30.5,
    4.0,
    rotation=0,
    lcsc="C14663",
    manufacturer="Yageo",
    mpn="CC0603KRX7R9BB104",
    description="AHCT bypass capacitor, 50 V X7R",
)
set_pad_nets(c1, {"1": "+5V_PERIPH", "2": "GND"})

c3 = add_footprint(
    "Capacitor_SMD",
    "C_0603_1608Metric",
    "C3",
    "100nF",
    26.5,
    10.0,
    rotation=90,
    lcsc="C14663",
    manufacturer="Yageo",
    mpn="CC0603KRX7R9BB104",
    description="Microphone bypass capacitor, 50 V X7R",
)
set_pad_nets(c3, {"1": "+3V3", "2": "GND"})

r1 = add_footprint(
    "Resistor_SMD",
    "R_0603_1608Metric",
    "R1",
    "330R",
    48.5,
    5.0,
    rotation=0,
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
    24.5,
    4.0,
    rotation=90,
    lcsc="C163512",
    manufacturer="Littelfuse",
    mpn="1206L050YR",
    description="0.50 A hold resettable fuse, 6 V",
)
set_pad_nets(f1, {"1": "+5V_IN", "2": "+5V_PERIPH"})

c2 = add_footprint(
    "Capacitor_SMD",
    "CP_Elec_8x10.5",
    "C2",
    "1000uF 10V",
    72.0,
    15.0,
    lcsc="C5246577",
    manufacturer="KNSCHA",
    mpn="RVT1000UF10V167RV0083",
    description="LED rail bulk capacitor, 105 C, observe polarity",
)
set_pad_nets(c2, {"1": "+5V_PERIPH", "2": "GND"})

q1 = add_footprint(
    "Package_TO_SOT_SMD",
    "SOT-23",
    "Q1",
    "MMBT3904",
    60.5,
    14.0,
    rotation=0,
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
    "1k",
    60.0,
    17.0,
    rotation=0,
    lcsc="C21190",
    manufacturer="UNI-ROYAL",
    mpn="0603WAF1001T5E",
    description="Buzzer transistor base resistor",
)
set_pad_nets(r2, {"1": "BUZZER_PWM", "2": "BUZZER_BASE"})

r3 = add_footprint(
    "Resistor_SMD",
    "R_0603_1608Metric",
    "R3",
    "100k",
    64.0,
    17.0,
    rotation=90,
    lcsc="C25803",
    manufacturer="UNI-ROYAL",
    mpn="0603WAF1003T5E",
    description="Buzzer transistor base pull-down",
)
set_pad_nets(r3, {"1": "BUZZER_BASE", "2": "GND"})

d1 = add_footprint(
    "Diode_SMD",
    "D_SOD-323",
    "D1",
    "1N5819WS",
    59.0,
    7.8,
    side="Top",
    rotation=0,
    lcsc="C191023",
    manufacturer="Hottech",
    mpn="1N5819WS",
    description="Buzzer flyback diode; cathode on switched 5 V",
)
set_pad_nets(d1, {"1": "+5V_BUZZER_SW", "2": "BUZZER_COLLECTOR"})


# Routing is added below after placement. Keep ground connections in the two
# filled ground planes.

# The unfused input rail supplies the controller and the PTC input.
route("+5V_IN", [xy(pad(j1, "1")), (72.8, 3.0)], width=0.80)
add_via("+5V_IN", (72.8, 3.0))
route("+5V_IN", [(72.8, 3.0), (72.8, 1.2), (24.5, 1.2)], width=0.80, layer=pcbnew.F_Cu)
add_via("+5V_IN", (24.5, 1.2))
route("+5V_IN", [(24.5, 1.2), xy(pad(f1, "1"))], width=0.80)
route("+5V_IN", [xy(pad(j2, "1")), (35.5, 17.5)], width=0.80)
add_via("+5V_IN", (35.5, 17.5))
route("+5V_IN", [(35.5, 17.5), (13.0, 17.5), (13.0, 1.2), (24.5, 1.2)], width=0.80, layer=pcbnew.F_Cu)

# The fused 5 V rail has a top-layer trunk and short lower-face branches.
route("+5V_PERIPH", [xy(pad(f1, "2")), (25.8, 5.4)], width=0.70)
add_via("+5V_PERIPH", (25.8, 5.4))
route("+5V_PERIPH", [(25.8, 5.4), (25.8, 2.8), (66.8, 2.8)], width=0.70, layer=pcbnew.F_Cu)
route("+5V_PERIPH", [xy(pad(f1, "2")), (11.0, 5.4), (11.0, 6.0), (7.0, 6.0), xy(pad(sw2, "2"))], width=0.70)

for via_xy, target, target_path in [
    ((29.0, 3.0), pad(c1, "1"), [(29.0, 3.0)]),
    ((44.2, 4.35), pad(u1, "10"), [(44.2, 4.35)]),
    ((58.5, 3.1), pad(j3, "1"), [(58.5, 3.1)]),
    ((64.5, 3.1), pad(j3, "4"), [(64.5, 3.1)]),
]:
    route("+5V_PERIPH", [(via_xy[0], 2.8), via_xy], width=0.40, layer=pcbnew.F_Cu)
    add_via("+5V_PERIPH", via_xy)
    route("+5V_PERIPH", [*target_path, xy(target)], width=0.40)
route("+5V_PERIPH", [(35.0, 2.8), (35.0, 5.0)], width=0.25, layer=pcbnew.F_Cu)
add_via("+5V_PERIPH", (35.0, 5.0), size=0.60, drill=0.30)
route("+5V_PERIPH", [(35.0, 5.0), xy(pad(u1, "4"))], width=0.25)
route("+5V_PERIPH", [xy(pad(u1, "13")), (44.2, 6.3), (44.2, 4.35)], width=0.35)
route("+5V_PERIPH", [xy(pad(u1, "14")), (45.0, 6.95), (45.0, 4.35), (44.2, 4.35)], width=0.35)
route("+5V_PERIPH", [(66.8, 2.8), (66.8, 15.0)], width=0.70, layer=pcbnew.F_Cu)
add_via("+5V_PERIPH", (66.8, 15.0))
route("+5V_PERIPH", [(66.8, 15.0), xy(pad(c2, "1"))], width=0.70)

# SW2 remains a hard series switch in the buzzer positive power wire.
route("+5V_BUZZER_SW", [xy(pad(sw2, "1")), (3.0, 7.5), (3.0, 19.0), (77.8, 19.0), (77.8, 10.0), xy(pad(bz1, "1"))], width=0.70, layer=pcbnew.F_Cu)
route("+5V_BUZZER_SW", [xy(pad(d1, "1")), (55.0, 7.8), (55.0, 10.6)], layer=pcbnew.F_Cu)
add_via("+5V_BUZZER_SW", (55.0, 10.6))
route("+5V_BUZZER_SW", [(55.0, 10.6), (76.5, 10.6)], width=0.40, layer=pcbnew.B_Cu)
add_via("+5V_BUZZER_SW", (76.5, 10.6))
route("+5V_BUZZER_SW", [(76.5, 10.6), xy(pad(bz1, "1"))], width=0.40, layer=pcbnew.F_Cu)

# The four microphone connections use parallel top-layer paths.
route("+3V3", [xy(pad(j2, "3")), (39.5, 13.9)])
add_via("+3V3", (39.5, 13.9), size=0.60, drill=0.30)
route("+3V3", [(39.5, 13.9), (31.0, 13.9)], layer=pcbnew.F_Cu)
add_via("+3V3", (31.0, 13.9), size=0.60, drill=0.30)
route("+3V3", [(31.0, 13.9), (31.0, 12.074), xy(pad(mic1, "5"))])
route("+3V3", [xy(pad(mic1, "5")), (30.8, 14.2), (25.2, 14.2), (25.2, 9.225), xy(pad(c3, "1"))])

route("MIC_SCK", [xy(pad(j2, "4")), (41.5, 11.8)])
add_via("MIC_SCK", (41.5, 11.8), size=0.60, drill=0.30)
route("MIC_SCK", [(41.5, 11.8), (32.5, 11.8)], layer=pcbnew.F_Cu)
add_via("MIC_SCK", (32.5, 11.8), size=0.60, drill=0.30)
route("MIC_SCK", [(32.5, 11.8), (32.5, 11.252), xy(pad(mic1, "4"))])

route("MIC_WS", [xy(pad(j2, "5")), (43.5, 12.5)])
add_via("MIC_WS", (43.5, 12.5), size=0.60, drill=0.30)
route("MIC_WS", [(43.5, 12.5), (27.3, 12.5)], layer=pcbnew.F_Cu)
add_via("MIC_WS", (27.3, 12.5), size=0.60, drill=0.30)
route("MIC_WS", [(27.3, 12.5), xy(pad(mic1, "1"))])

route("MIC_SD", [xy(pad(j2, "6")), (45.5, 13.2)])
add_via("MIC_SD", (45.5, 13.2), size=0.60, drill=0.30)
route("MIC_SD", [(45.5, 13.2), (29.5, 13.2)], layer=pcbnew.F_Cu)
add_via("MIC_SD", (29.5, 13.2), size=0.60, drill=0.30)
route("MIC_SD", [(29.5, 13.2), xy(pad(mic1, "6"))])

# LED data enters U1 on pin 2 and leaves through R1.
route("LED_DATA_3V3", [xy(pad(j2, "7")), (47.5, 10.8), (34.5, 10.8), (34.5, 6.3), xy(pad(u1, "2"))])

route("LED_DATA_5V_RAW", [xy(pad(u1, "3")), (33.5, 5.65)])
add_via("LED_DATA_5V_RAW", (33.5, 5.65))
route("LED_DATA_5V_RAW", [(33.5, 5.65), (33.5, 9.5), (46.5, 9.5), (46.5, 5.0)], layer=pcbnew.F_Cu)
add_via("LED_DATA_5V_RAW", (46.5, 5.0))
route("LED_DATA_5V_RAW", [(46.5, 5.0), xy(pad(r1, "1"))])
route("LED_DATA_5V", [xy(pad(r1, "2")), (50.0, 5.0), (50.0, 9.8), (62.5, 9.8), xy(pad(j3, "3"))])

# MUTE_N approaches the top switch from above its unused contact row.
route("MUTE_N", [xy(pad(j2, "9")), (51.5, 15.7)])
add_via("MUTE_N", (51.5, 15.7))
route("MUTE_N", [(51.5, 15.7), (14.5, 15.7), (14.5, 5.5), (20.0, 5.5), xy(pad(sw1, "2"))], layer=pcbnew.F_Cu)

# Q1 drives the magnetic buzzer. D1 clamps its inductive turn-off pulse.
route("BUZZER_PWM", [xy(pad(j2, "8")), (49.5, 11.8)])
add_via("BUZZER_PWM", (49.5, 11.8))
route("BUZZER_PWM", [(49.5, 11.8), (59.175, 11.8)], layer=pcbnew.F_Cu)
add_via("BUZZER_PWM", (59.175, 11.8))
route("BUZZER_PWM", [(59.175, 11.8), (57.6, 11.8), (57.6, 17.0), xy(pad(r2, "1"))])
route("BUZZER_BASE", [xy(pad(r2, "2")), (60.825, 15.8), xy(pad(q1, "1"))])
route("BUZZER_BASE", [xy(pad(q1, "1")), (62.2, 14.95), (62.2, 17.0), xy(pad(r3, "1"))])
route("BUZZER_COLLECTOR", [xy(pad(q1, "3")), (62.0, 14.0), (62.0, 12.0)], width=0.45)
add_via("BUZZER_COLLECTOR", (62.0, 12.0))
route("BUZZER_COLLECTOR", [(62.0, 12.0), xy(pad(bz1, "2"))], width=0.45, layer=pcbnew.F_Cu)
route("BUZZER_COLLECTOR", [xy(pad(d1, "2")), (61.0, 7.8), (61.0, 10.0), xy(pad(bz1, "2"))], width=0.40, layer=pcbnew.F_Cu)

route("GND", [xy(pad(q1, "2")), (61.0, 13.05)])
add_via("GND", (61.0, 13.05))


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
    for x, y in [(0.5, 0.5), (79.5, 0.5), (79.5, 19.5), (0.5, 19.5)]:
        outline.Append(point(x, y))
    board.Add(zone)


add_ground_zone(pcbnew.F_Cu)
add_ground_zone(pcbnew.B_Cu)

add_text("ESPNoise rev B", 40, 1.3, pcbnew.F_SilkS, 0.75)
add_text("BUZZ ON", 7.0, 4.7, pcbnew.F_SilkS, 0.65)
add_text("EXTENDED=ON", 7.0, 15.3, pcbnew.F_SilkS, 0.55)
add_text("MUTE", 20.0, 4.7, pcbnew.F_SilkS, 0.65)
add_text("MIC", 29.5, 7.9, pcbnew.F_SilkS, 0.55)
add_text("BUZZER", 69.0, 2.3, pcbnew.F_SilkS, 0.65)
add_text("BOTTOM - CONNECTORS DOWN", 40, 18.8, pcbnew.B_SilkS, 0.65)
add_text("J2 CTRL", 44.5, 10.4, pcbnew.B_SilkS, 0.55)
add_text("J3 LED", 62.5, 10.4, pcbnew.B_SilkS, 0.55)
add_text("J1 USB-C 5V", 74.0, 10.4, pcbnew.B_SilkS, 0.50)


pcbnew.ZONE_FILLER(board).Fill(board.Zones())
pcbnew.SaveBoard(str(BOARD_FILE), board)


JLC_DIR.mkdir(parents=True, exist_ok=True)

with (JLC_DIR / "espnoise-carrier-bom.csv").open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle, lineterminator="\n")
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
    writer = csv.writer(handle, lineterminator="\n")
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
    writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(sorted(placements, key=lambda row: str(row["ref"])))

print(f"Generated {BOARD_FILE}")
print(f"Generated JLCPCB BOM and CPL in {JLC_DIR}")
