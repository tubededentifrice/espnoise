#!/usr/bin/env python3
"""Generate the ESPNoise Rev C unit and two-unit CNC panel.

The generated files do not need KiCad. KiCad can open the generated board, and
pcb2gcode can convert the Gerber files to GRBL G-code.
"""

from __future__ import annotations

from dataclasses import dataclass
from heapq import heappop, heappush
from itertools import count
from math import hypot
from pathlib import Path
from typing import Iterable
from uuid import uuid5, NAMESPACE_URL


HERE = Path(__file__).resolve().parent
BOARD_NAME = "espnoise-cnc"
PANEL_NAME = "espnoise-panel"
BOARD_WIDTH = 70.0
BOARD_HEIGHT = 24.5
PANEL_WIDTH = 70.0
PANEL_HEIGHT = 50.0
PANEL_CUT_Y = 25.0
USER_CENTERLINE_Y = BOARD_HEIGHT / 2
MIN_TRACK_WIDTH = 0.50
MIN_CLEARANCE = 0.40
POWER_TRACK_WIDTH = 1.00

# Physical values from the user's prototype board. The microphone diameter is
# approximate. The acoustic hole is confirmed at the module center.
MIC_MODULE_DIAMETER = 13.0
MIC_PIN_PITCH_X = 2.54
MIC_ROW_PITCH_Y = 7.62
MIC_ACOUSTIC_OFFSET_X = 0.0
MIC_ACOUSTIC_OFFSET_Y = 0.0
BUZZER_BODY_DIAMETER = 12.0
BUZZER_LEAD_PITCH = 6.5
BUZZER_LEAD_DIAMETER = 0.5
BUZZER_DRILL_DIAMETER = 0.8


@dataclass(frozen=True)
class Pad:
    number: str
    x: float
    y: float
    net: str
    diameter: float = 2.0
    drill: float = 0.9
    side: str = "both"
    shape: str = "circle"
    width: float | None = None
    height: float | None = None

    @property
    def copper_radius(self) -> float:
        return max(self.width or self.diameter, self.height or self.diameter) / 2


@dataclass(frozen=True)
class Component:
    ref: str
    value: str
    face: str
    x: float
    y: float
    body_width: float
    body_height: float
    pads: tuple[Pad, ...]
    note: str = ""
    footprint: str = "ESPNoise:CNC_Custom"
    body_shape: str = "rect"


@dataclass(frozen=True)
class Track:
    net: str
    layer: str
    points: tuple[tuple[float, float], ...]
    width: float = MIN_TRACK_WIDTH


@dataclass(frozen=True)
class Via:
    x: float
    y: float
    net: str
    diameter: float = 1.7
    drill: float = 0.8


components: list[Component] = []
tracks: list[Track] = []
vias: list[Via] = []


def add_component(component: Component) -> None:
    components.append(component)


def add_track(
    net: str,
    layer: str,
    *points: tuple[float, float],
    width: float = MIN_TRACK_WIDTH,
) -> None:
    tracks.append(Track(net, layer, tuple(points), width))


def add_via(x: float, y: float, net: str) -> Via:
    item = Via(x, y, net)
    vias.append(item)
    return item


def th_pad(
    number: int | str,
    x: float,
    y: float,
    net: str,
    *,
    drill: float = 0.9,
    diameter: float | None = None,
) -> Pad:
    return Pad(str(number), x, y, net, diameter=diameter or max(1.6, drill + 0.6), drill=drill)


def smd_pad(
    number: int | str,
    x: float,
    y: float,
    net: str,
    width: float,
    height: float,
) -> Pad:
    return Pad(
        str(number), x, y, net, drill=0.0, side="F.Cu", shape="rect", width=width, height=height
    )


# User face: the two switches, microphone module, and buzzer only.
add_component(
    Component(
        "SW2",
        "BUZZER ENABLE (7-7 ZS)",
        "User",
        7.0,
        USER_CENTERLINE_Y,
        7.0,
        7.0,
        (
            th_pad(1, 5.0, 9.75, "", drill=1.0),
            th_pad(2, 7.0, 9.75, "", drill=1.0),
            th_pad(3, 9.0, 9.75, "", drill=1.0),
            th_pad(4, 5.0, 14.75, "+5V_BUZZER_SW", drill=1.0),
            th_pad(5, 7.0, 14.75, "+5V_PERIPH", drill=1.0),
            th_pad(6, 9.0, 14.75, "", drill=1.0),
        ),
        "Extended state enables buzzer power.",
        "ESPNoise:7x7_DPDT_Pushbutton",
    )
)
add_component(
    Component(
        "SW1",
        "MUTE (7-7 WS)",
        "User",
        18.0,
        USER_CENTERLINE_Y,
        7.0,
        7.0,
        (
            th_pad(1, 16.0, 9.75, "", drill=1.0),
            th_pad(2, 18.0, 9.75, "", drill=1.0),
            th_pad(3, 20.0, 9.75, "", drill=1.0),
            th_pad(4, 16.0, 14.75, "", drill=1.0),
            th_pad(5, 18.0, 14.75, "MUTE_N", drill=1.0),
            th_pad(6, 20.0, 14.75, "GND", drill=1.0),
        ),
        "Momentary mute button.",
        "ESPNoise:7x7_DPDT_Pushbutton",
    )
)

mic_center_x = 36.0 - MIC_ACOUSTIC_OFFSET_X
mic_center_y = USER_CENTERLINE_Y - MIC_ACOUSTIC_OFFSET_Y
mic_x = [mic_center_x - MIC_PIN_PITCH_X, mic_center_x, mic_center_x + MIC_PIN_PITCH_X]
mic_top_y = mic_center_y - MIC_ROW_PITCH_Y / 2
mic_bottom_y = mic_center_y + MIC_ROW_PITCH_Y / 2
add_component(
    Component(
        "MIC1",
        "MH-ET LIVE INMP441 2x3 MODULE",
        "User",
        mic_center_x,
        mic_center_y,
        MIC_MODULE_DIAMETER,
        MIC_MODULE_DIAMETER,
        (
            th_pad(1, mic_x[0], mic_top_y, "GND", drill=1.0),
            th_pad(2, mic_x[1], mic_top_y, "+3V3", drill=1.0),
            th_pad(3, mic_x[2], mic_top_y, "MIC_SD", drill=1.0),
            th_pad(4, mic_x[0], mic_bottom_y, "GND", drill=1.0),
            th_pad(5, mic_x[1], mic_bottom_y, "MIC_WS", drill=1.0),
            th_pad(6, mic_x[2], mic_bottom_y, "MIC_SCK", drill=1.0),
        ),
        "The printed-label and acoustic-hole face points toward the case top. In that face view, with the notch at the local top edge: top row 1 GND, 2 VDD, 3 SD; bottom row 4 L/R, 5 WS, 6 SCK. L/R is grounded. The pin pitches and centered acoustic hole are confirmed. The 13 mm body is approximate.",
        "ESPNoise:MH_ET_LIVE_INMP441_2x3_P2.54_Row7.62",
        "circle",
    )
)
add_component(
    Component(
        "BZ1",
        "TWO-PIN 5 V BUZZER",
        "User",
        61.0,
        USER_CENTERLINE_Y,
        BUZZER_BODY_DIAMETER,
        BUZZER_BODY_DIAMETER,
        (
            th_pad(1, 61.0 + BUZZER_LEAD_PITCH / 2, USER_CENTERLINE_Y, "+5V_BUZZER_SW", drill=BUZZER_DRILL_DIAMETER),
            th_pad(2, 61.0 - BUZZER_LEAD_PITCH / 2, USER_CENTERLINE_Y, "BUZZER_COLLECTOR", drill=BUZZER_DRILL_DIAMETER),
        ),
        "Passive buzzer with top sound port. Pad 1 is + and pad 2 is -. The measured body is 12 mm, the lead pitch is 6.5 mm, and each lead is 0.5 mm. D1 protects the driver from the coil turn-off pulse.",
        "ESPNoise:Buzzer_THT_2Pin_P6.50mm_D12mm",
        "circle",
    )
)

# Internal face: support parts and large wire pads. There are no cable headers.
wire_pad = {"drill": 1.2, "diameter": 2.4}
add_component(
    Component(
        "PWR1", "5 V POWER WIRES", "Internal", 4.75, 3.0, 7.0, 4.0,
        (
            th_pad(1, 3.0, 3.0, "+5V_IN", **wire_pad),
            th_pad(2, 6.5, 3.0, "GND", **wire_pad),
        ),
        "External power-only input. Keep it separate from the ESP32 service port.",
        "ESPNoise:WirePads_2_P3.5mm",
    )
)

terminal = lambda number, x, y, net: th_pad(number, x, y, net, drill=1.2, diameter=2.0)
add_component(
    Component(
        "J_ESP32", "ESP32 INDIVIDUAL WIRES", "Internal", 0.0, 0.0, 0.0, 0.0,
        (
            terminal(1, 2.5, 22.0, "+5V_IN"),
            terminal(2, 6.0, 22.0, "GND"),
            terminal(3, 39.81, 22.0, "+3V3"),
            terminal(4, 29.65, 22.0, "MIC_SCK"),
            terminal(5, 32.19, 22.0, "MIC_WS"),
            terminal(6, 37.27, 22.0, "MIC_SD"),
            terminal(7, 35.0, 3.0, "LED_DATA"),
            terminal(8, 48.0, 3.0, "BUZZER_PWM"),
            terminal(9, 18.0, 22.0, "MUTE_N"),
        ),
        "Pins: 1 VIN/5V, 2 GND, 3 3V3, 4 GPIO26 MIC_SCK, 5 GPIO25 MIC_WS, 6 GPIO32 MIC_SD, 7 GPIO18 LED_DATA, 8 GPIO23 BUZZER_PWM, 9 GPIO27 MUTE_N.",
        "ESPNoise:IndividualWireGroup_ESP32",
        "none",
    )
)
add_component(
    Component(
        "J_LED", "LED STRIP INDIVIDUAL WIRES", "Internal", 0.0, 0.0, 0.0, 0.0,
        (
            terminal(1, 44.0, 22.0, "+5V_PERIPH"),
            terminal(2, 42.0, 3.0, "LED_DATA"),
            terminal(3, 48.0, 22.0, "GND"),
        ),
        "Pins: 1 +5V, 2 DIN from GPIO18, 3 GND.",
        "ESPNoise:IndividualWireGroup_LED",
        "none",
    )
)

def axial(ref: str, value: str, x1: float, y1: float, x2: float, y2: float, net1: str, net2: str) -> None:
    add_component(
        Component(ref, value, "Internal", (x1 + x2) / 2, (y1 + y2) / 2,
                  max(2.5, abs(x2 - x1) + 2), max(2.5, abs(y2 - y1) + 2),
                  (th_pad(1, x1, y1, net1), th_pad(2, x2, y2, net2)), footprint="THT:Axial")
    )


axial("R2", "1K", 49.0, 6.0, 56.0, 6.0, "BUZZER_PWM", "BUZZER_BASE")
axial("R3", "100K", 49.0, 10.0, 49.0, 16.0, "BUZZER_BASE", "GND")
axial("D1", "1N5819", 66.0, 21.0, 56.0, 21.0, "+5V_BUZZER_SW", "BUZZER_COLLECTOR")

add_component(
    Component("F1", "0.5A PTC MF-R050", "Internal", 12.5, 3.0, 6.0, 4.0,
              (th_pad(1, 10.0, 3.0, "+5V_IN", drill=1.0), th_pad(2, 15.0, 3.0, "+5V_PERIPH", drill=1.0)),
              footprint="THT:Fuse_Radial_P5.00mm")
)
add_component(
    Component("Q1", "2N3904", "Internal", 59.5, 17.0, 6.0, 4.0,
              (th_pad(1, 56.96, 17.0, "GND"), th_pad(2, 59.5, 17.0, "BUZZER_BASE"),
               th_pad(3, 62.04, 17.0, "BUZZER_COLLECTOR")),
              "Flat-face pin order is E-B-C. Confirm the transistor data sheet.", "THT:TO-92_Inline_EBC")
)

# Registration holes are also usable as mounting holes. They have no copper.
registration_holes = [(35.0, 2.5)]

MANUAL_NETS: set[str] = set()
ESCAPED_PADS: set[tuple[str, str]] = set()


def all_pads() -> Iterable[tuple[Component, Pad]]:
    for component in components:
        for item in component.pads:
            yield component, item


ROUTER_GRID = 0.25
LAYER_NAMES = ("F.Cu", "B.Cu")


def grid_point(x: float, y: float, layer: int) -> tuple[int, int, int]:
    return (round(x / ROUTER_GRID), round(y / ROUTER_GRID), layer)


def world_point(node: tuple[int, int, int]) -> tuple[float, float]:
    return (node[0] * ROUTER_GRID, node[1] * ROUTER_GRID)


def preferred_layer(component: Component, item: Pad) -> int:
    if item.drill == 0:
        return 0
    # Keep the buzzer base route off the user-face buzzer pads.
    if item.net == "BUZZER_BASE":
        return 1
    # Put the solder joint and the connected track on the face opposite the body.
    return 1 if component.face == "User" else 0


def route_board() -> None:
    """Route all nets with a deterministic two-layer Manhattan grid router."""
    endpoints: dict[str, list[tuple[int, int, int]]] = {}
    for component, item in all_pads():
        if item.net and item.net not in MANUAL_NETS and (component.ref, item.number) not in ESCAPED_PADS:
            endpoints.setdefault(item.net, []).append(grid_point(item.x, item.y, preferred_layer(component, item)))
    for item in vias:
        if item.net not in MANUAL_NETS:
            endpoints.setdefault(item.net, []).append(grid_point(item.x, item.y, 0))

    occupied: dict[int, list[tuple[str, tuple[float, float], tuple[float, float], float]]] = {0: [], 1: []}
    for item in tracks:
        layer = LAYER_NAMES.index(item.layer)
        for start, end in zip(item.points, item.points[1:]):
            occupied[layer].append((item.net, start, end, item.width))
    occupied_vias: list[tuple[str, float, float, float]] = [
        (item.net, item.x, item.y, item.diameter / 2) for item in vias
    ]
    foreign_pads: list[tuple[str, int, float, float, float]] = []
    for component, item in all_pads():
        if not item.net:
            for layer in (0, 1):
                foreign_pads.append(("<NC>", layer, item.x, item.y, item.copper_radius))
            continue
        layers = (0, 1) if item.side == "both" else (0 if item.side == "F.Cu" else 1,)
        for layer in layers:
            foreign_pads.append((item.net, layer, item.x, item.y, item.copper_radius))

    via_keepouts: list[tuple[float, float, float]] = [(x, y, 1.4) for x, y in registration_holes]

    def distance_to_segment(
        point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]
    ) -> float:
        vx, vy = end[0] - start[0], end[1] - start[1]
        wx, wy = point[0] - start[0], point[1] - start[1]
        length2 = vx * vx + vy * vy
        if length2 == 0:
            return hypot(point[0] - start[0], point[1] - start[1])
        ratio = max(0.0, min(1.0, (wx * vx + wy * vy) / length2))
        closest = (start[0] + ratio * vx, start[1] + ratio * vy)
        return hypot(point[0] - closest[0], point[1] - closest[1])

    def node_blocked(node: tuple[int, int, int], net: str, allow: set[tuple[int, int, int]]) -> bool:
        if node in allow:
            return False
        x, y = world_point(node)
        edge_margin = 1.0 if net in {"+5V_IN", "+5V_PERIPH", "+5V_BUZZER_SW"} else 1.5
        if x < edge_margin or x > BOARD_WIDTH - edge_margin or y < edge_margin or y > BOARD_HEIGHT - edge_margin:
            return True
        candidate_width = POWER_TRACK_WIDTH if net in {"GND", "+5V_IN", "+5V_PERIPH", "+5V_BUZZER_SW"} else MIN_TRACK_WIDTH
        for pad_net, layer, px, py, radius in foreign_pads:
            if layer == node[2] and pad_net != net and hypot(x - px, y - py) < radius + MIN_CLEARANCE + candidate_width / 2:
                return True
        for existing_net, start, end, width in occupied[node[2]]:
            if existing_net != net and distance_to_segment((x, y), start, end) < width / 2 + MIN_CLEARANCE + candidate_width / 2:
                return True
        for via_net, vx, vy, radius in occupied_vias:
            if via_net != net and hypot(x - vx, y - vy) < radius + MIN_CLEARANCE + candidate_width / 2:
                return True
        return False

    def via_blocked(node: tuple[int, int, int], net: str, allow: set[tuple[int, int, int]]) -> bool:
        x, y = world_point(node)
        for px, py, radius in via_keepouts:
            if hypot(x - px, y - py) < radius + 1.1:
                return True
        via_radius = Via(x, y, net).diameter / 2
        for layer in (0, 1):
            for pad_net, pad_layer, px, py, radius in foreign_pads:
                if pad_layer == layer and pad_net != net and hypot(x - px, y - py) < radius + MIN_CLEARANCE + via_radius:
                    return True
            for existing_net, start, end, width in occupied[layer]:
                if existing_net != net and distance_to_segment((x, y), start, end) < width / 2 + MIN_CLEARANCE + via_radius:
                    return True
        for via_net, vx, vy, radius in occupied_vias:
            if via_net != net and hypot(x - vx, y - vy) < radius + MIN_CLEARANCE + via_radius:
                return True
        return False

    def find_path(
        starts: set[tuple[int, int, int]], goals: set[tuple[int, int, int]], net: str
    ) -> list[tuple[int, int, int]]:
        serial = count()
        queue: list[tuple[float, int, tuple[int, int, int]]] = []
        previous: dict[tuple[int, int, int], tuple[int, int, int] | None] = {}
        cost: dict[tuple[int, int, int], float] = {}
        allow = starts | goals
        goal_xy = [(goal[0], goal[1], goal[2]) for goal in goals]
        for start in starts:
            cost[start] = 0.0
            previous[start] = None
            heappush(queue, (0.0, next(serial), start))
        found: tuple[int, int, int] | None = None
        while queue:
            _, _, current = heappop(queue)
            if current in goals:
                found = current
                break
            neighbors = [
                (current[0] + 1, current[1], current[2]), (current[0] - 1, current[1], current[2]),
                (current[0], current[1] + 1, current[2]), (current[0], current[1] - 1, current[2]),
                (current[0] + 1, current[1] + 1, current[2]),
                (current[0] + 1, current[1] - 1, current[2]),
                (current[0] - 1, current[1] + 1, current[2]),
                (current[0] - 1, current[1] - 1, current[2]),
            ]
            if not via_blocked(current, net, allow):
                neighbors.append((current[0], current[1], 1 - current[2]))
            for neighbor in neighbors:
                if node_blocked(neighbor, net, allow):
                    continue
                if neighbor[2] != current[2]:
                    step = 14.0
                elif neighbor[0] != current[0] and neighbor[1] != current[1]:
                    step = 1.414
                else:
                    step = 1.0
                new_cost = cost[current] + step
                if new_cost >= cost.get(neighbor, float("inf")):
                    continue
                cost[neighbor] = new_cost
                previous[neighbor] = current
                heuristic = min(abs(neighbor[0] - gx) + abs(neighbor[1] - gy) + (10 if neighbor[2] != gl else 0) for gx, gy, gl in goal_xy)
                heappush(queue, (new_cost + heuristic, next(serial), neighbor))
        if found is None:
            goal_text = ", ".join(f"{world_point(goal)} {LAYER_NAMES[goal[2]]}" for goal in goals)
            raise SystemExit(f"Router failed on net {net} at {goal_text}; tree has {len(starts)} nodes")
        result = []
        while found is not None:
            result.append(found)
            found = previous[found]
        return list(reversed(result))

    def compress(path: list[tuple[int, int, int]]) -> list[list[tuple[int, int, int]]]:
        groups: list[list[tuple[int, int, int]]] = []
        current: list[tuple[int, int, int]] = []
        for node in path:
            if current and node[2] != current[-1][2]:
                groups.append(current)
                current = [node]
            else:
                current.append(node)
        if current:
            groups.append(current)
        output: list[list[tuple[int, int, int]]] = []
        for group in groups:
            if len(group) <= 2:
                output.append(group)
                continue
            compact = [group[0]]
            last_direction = None
            for previous_node, node in zip(group, group[1:]):
                direction = (node[0] - previous_node[0], node[1] - previous_node[1])
                if last_direction is not None and direction != last_direction:
                    compact.append(previous_node)
                last_direction = direction
            compact.append(group[-1])
            output.append(compact)
        return output

    # Route the small signals before the large power rails.
    route_order = [
        "MIC_SCK", "MIC_WS", "MIC_SD", "+3V3", "MUTE_N", "BUZZER_PWM",
        "LED_DATA", "GND", "+5V_IN", "+5V_PERIPH",
        "BUZZER_BASE", "BUZZER_COLLECTOR",
        "+5V_BUZZER_SW",
    ]
    priority = {net: index for index, net in enumerate(route_order)}
    ordered_nets = sorted(endpoints, key=lambda net: priority.get(net, 100))
    for net in ordered_nets:
        net_points = endpoints[net]
        tree: set[tuple[int, int, int]] = {net_points[0]}
        remaining = set(net_points[1:])
        while remaining:
            distance_from_tree = lambda item: min(
                abs(item[0] - root[0]) + abs(item[1] - root[1]) + 10 * (item[2] != root[2])
                for root in tree
            )
            goal = min(remaining, key=distance_from_tree)
            path = find_path(tree, {goal}, net)
            for current, following in zip(path, path[1:]):
                if current[2] != following[2]:
                    x, y = world_point(current)
                    if not any(existing.net == net and hypot(existing.x - x, existing.y - y) < 0.1 for existing in vias):
                        item = add_via(x, y, net)
                        occupied_vias.append((net, x, y, item.diameter / 2))
            for group in compress(path):
                if len(group) < 2:
                    continue
                points = tuple(world_point(node) for node in group)
                width = POWER_TRACK_WIDTH if net in {"GND", "+5V_IN", "+5V_PERIPH", "+5V_BUZZER_SW"} else MIN_TRACK_WIDTH
                add_track(net, LAYER_NAMES[group[0][2]], *points, width=width)
                for start, end in zip(points, points[1:]):
                    occupied[group[0][2]].append((net, start, end, width))
            tree.update(path)
            remaining.remove(goal)


route_board()


def segment_distance(
    a1: tuple[float, float], a2: tuple[float, float], b1: tuple[float, float], b2: tuple[float, float]
) -> float:
    """Return a conservative segment distance without an external geometry package."""
    def point_segment(point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]) -> float:
        vx, vy = end[0] - start[0], end[1] - start[1]
        wx, wy = point[0] - start[0], point[1] - start[1]
        length2 = vx * vx + vy * vy
        if length2 == 0:
            return hypot(point[0] - start[0], point[1] - start[1])
        ratio = max(0.0, min(1.0, (wx * vx + wy * vy) / length2))
        closest = (start[0] + ratio * vx, start[1] + ratio * vy)
        return hypot(point[0] - closest[0], point[1] - closest[1])

    # Intersection test with collinear contact included.
    def orientation(p: tuple[float, float], q: tuple[float, float], r: tuple[float, float]) -> float:
        return (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])

    o1, o2 = orientation(a1, a2, b1), orientation(a1, a2, b2)
    o3, o4 = orientation(b1, b2, a1), orientation(b1, b2, a2)
    if o1 * o2 < 0 and o3 * o4 < 0:
        return 0.0
    return min(
        point_segment(a1, b1, b2), point_segment(a2, b1, b2),
        point_segment(b1, a1, a2), point_segment(b2, a1, a2),
    )


def validate() -> None:
    errors: list[str] = []
    for component, item in all_pads():
        if not (1.2 <= item.x <= BOARD_WIDTH - 1.2 and 1.2 <= item.y <= BOARD_HEIGHT - 1.2):
            errors.append(f"{component.ref} pad {item.number} is too close to the board edge")
        if item.net and item.drill > 0 and item.diameter - item.drill < 0.6:
            errors.append(f"{component.ref} pad {item.number} has a small annular ring")
    for index, first in enumerate(components):
        if first.body_shape == "none":
            continue
        if not (
            first.body_width / 2 <= first.x <= BOARD_WIDTH - first.body_width / 2
            and first.body_height / 2 <= first.y <= BOARD_HEIGHT - first.body_height / 2
        ):
            errors.append(f"{first.ref} body extends outside the unit outline")
        for second in components[index + 1:]:
            if first.face != second.face or second.body_shape == "none":
                continue
            x_overlap = (first.body_width + second.body_width) / 2 - abs(first.x - second.x)
            y_overlap = (first.body_height + second.body_height) / 2 - abs(first.y - second.y)
            if x_overlap > 0 and y_overlap > 0:
                errors.append(f"{first.ref} body overlaps {second.ref} on the {first.face} face")
    for item in tracks:
        if item.width < MIN_TRACK_WIDTH:
            errors.append(f"{item.net} has a track narrower than {MIN_TRACK_WIDTH:.2f} mm")
        for x, y in item.points:
            if not (1.0 <= x <= BOARD_WIDTH - 1.0 and 1.0 <= y <= BOARD_HEIGHT - 1.0):
                errors.append(f"{item.net} track point ({x}, {y}) is too close to the edge")

    segments: list[tuple[str, str, float, tuple[float, float], tuple[float, float]]] = []
    for item in tracks:
        for start, end in zip(item.points, item.points[1:]):
            segments.append((item.net, item.layer, item.width, start, end))
    for index, first in enumerate(segments):
        for second in segments[index + 1:]:
            if first[1] != second[1] or first[0] == second[0]:
                continue
            required = first[2] / 2 + second[2] / 2 + MIN_CLEARANCE
            distance = segment_distance(first[3], first[4], second[3], second[4])
            if distance + 1e-6 < required:
                errors.append(
                    f"{first[1]} clearance {distance:.2f} mm between {first[0]} and {second[0]} "
                    f"near {first[3]} / {second[3]}"
                )

    # Pad-to-track and via-to-track checks catch the most common hand-route errors.
    copper_points: list[tuple[str, str, float, tuple[float, float], str]] = []
    for component, item in all_pads():
        if not item.net:
            continue
        layers = ("F.Cu", "B.Cu") if item.side == "both" else (item.side,)
        for layer in layers:
            copper_points.append((item.net, layer, item.copper_radius, (item.x, item.y), f"{component.ref}-{item.number}"))
    for item in vias:
        for layer in ("F.Cu", "B.Cu"):
            copper_points.append((item.net, layer, item.diameter / 2, (item.x, item.y), "via"))
    for index, first in enumerate(copper_points):
        for second in copper_points[index + 1:]:
            if first[1] != second[1] or first[0] == second[0]:
                continue
            distance = hypot(first[3][0] - second[3][0], first[3][1] - second[3][1])
            required = first[2] + second[2] + MIN_CLEARANCE
            if distance + 1e-6 < required:
                errors.append(
                    f"{first[1]} copper clearance {distance:.2f} mm between "
                    f"{first[4]} {first[0]} and {second[4]} {second[0]}"
                )
    for point_net, point_layer, radius, location, label in copper_points:
        for segment_net, segment_layer, width, start, end in segments:
            if point_layer != segment_layer or point_net == segment_net:
                continue
            distance = segment_distance(location, location, start, end)
            required = radius + width / 2 + MIN_CLEARANCE
            if distance + 1e-6 < required:
                errors.append(
                    f"{point_layer} clearance {distance:.2f} mm from {label} {point_net} "
                    f"to {segment_net} track near {start}"
                )

    if errors:
        unique = list(dict.fromkeys(errors))
        raise SystemExit("CNC board validation failed:\n- " + "\n- ".join(unique))


def kicad_uuid(key: str) -> str:
    return str(uuid5(NAMESPACE_URL, "https://espnoise.local/cnc/" + key))


def write_kicad_board() -> None:
    net_names = sorted({item.net for _, item in all_pads() if item.net} | {item.net for item in vias})
    net_ids = {name: index + 1 for index, name in enumerate(net_names)}
    lines = [
        "(kicad_pcb", "  (version 20240108)", '  (generator "espnoise-cnc-generator")',
        "  (general (thickness 1.6))", '  (paper "A4")',
        "  (layers", '    (0 "F.Cu" signal)', '    (31 "B.Cu" signal)',
        '    (36 "B.SilkS" user "b.silkscreen")', '    (37 "F.SilkS" user "f.silkscreen")',
        '    (44 "Edge.Cuts" user)', '  )',
        "  (setup (pad_to_mask_clearance 0))",
        '  (net 0 "")',
    ]
    lines.extend(f'  (net {net_ids[name]} "{name}")' for name in net_names)
    for component in components:
        layer = "F.Cu" if component.face == "User" else "B.Cu"
        silk = "F.SilkS" if component.face == "User" else "B.SilkS"
        label_x = component.x if component.body_shape != "none" else sum(item.x for item in component.pads) / len(component.pads)
        label_y = component.y if component.body_shape != "none" else sum(item.y for item in component.pads) / len(component.pads)
        lines.extend([
            f'  (footprint "{component.footprint}"', f'    (layer "{layer}")',
            f'    (uuid "{kicad_uuid(component.ref)}")', '    (at 0 0)',
            f'    (property "Reference" "{component.ref}" (at {label_x:.3f} {label_y - component.body_height / 2 - 1.3:.3f} 0) (layer "{silk}") (effects (font (size 1 1) (thickness 0.15))))',
            f'    (property "Value" "{component.value}" (at {label_x:.3f} {label_y + component.body_height / 2 + 1.3:.3f} 0) (layer "{silk}") (effects (font (size 0.8 0.8) (thickness 0.12))))',
        ])
        if component.body_shape == "circle":
            lines.append(
                f'    (fp_circle (center {component.x:.3f} {component.y:.3f}) '
                f'(end {component.x + component.body_width / 2:.3f} {component.y:.3f}) '
                f'(stroke (width 0.25) (type default)) (fill none) (layer "{silk}"))'
            )
        elif component.body_shape == "rect":
            lines.append(
                f'    (fp_rect (start {component.x - component.body_width / 2:.3f} {component.y - component.body_height / 2:.3f}) '
                f'(end {component.x + component.body_width / 2:.3f} {component.y + component.body_height / 2:.3f}) '
                f'(stroke (width 0.25) (type default)) (fill none) (layer "{silk}"))'
            )
        for item in component.pads:
            if item.drill == 0:
                lines.append(
                    f'    (pad "{item.number}" smd rect (at {item.x:.3f} {item.y:.3f}) '
                    f'(size {item.width:.3f} {item.height:.3f}) (layers "F.Cu") '
                    f'(net {net_ids[item.net]} "{item.net}"))'
                )
            else:
                shape = "rect" if item.number == "1" else "circle"
                net_text = f'(net {net_ids[item.net]} "{item.net}")' if item.net else ""
                lines.append(
                    f'    (pad "{item.number}" thru_hole {shape} (at {item.x:.3f} {item.y:.3f}) '
                    f'(size {item.diameter:.3f} {item.diameter:.3f}) (drill {item.drill:.3f}) '
                    f'(layers "*.Cu" "*.Mask") {net_text})'
                )
        lines.append("  )")
    for index, (x, y) in enumerate(registration_holes):
        lines.extend([
            f'  (footprint "Mechanical:RegistrationHole_2mm" (layer "F.Cu") (uuid "{kicad_uuid(f"REG{index}")}") (at 0 0)',
            f'    (property "Reference" "H{index + 1}" (at {x + 3:.3f} {y:.3f}) (layer "F.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12))))',
            f'    (pad "" np_thru_hole circle (at {x:.3f} {y:.3f}) (size 2 2) (drill 2) (layers "*.Cu" "*.Mask"))',
            "  )",
        ])
    for item in tracks:
        for start, end in zip(item.points, item.points[1:]):
            lines.append(
                f'  (segment (start {start[0]:.3f} {start[1]:.3f}) (end {end[0]:.3f} {end[1]:.3f}) '
                f'(width {item.width:.3f}) (layer "{item.layer}") (net {net_ids[item.net]}))'
            )
    for item in vias:
        lines.append(
            f'  (via (at {item.x:.3f} {item.y:.3f}) (size {item.diameter:.3f}) (drill {item.drill:.3f}) '
            f'(layers "F.Cu" "B.Cu") (net {net_ids[item.net]}))'
        )
    lines.extend([
        f'  (gr_rect (start 0 0) (end {BOARD_WIDTH:.3f} {BOARD_HEIGHT:.3f}) (stroke (width 0.1) (type default)) (fill none) (layer "Edge.Cuts"))',
        '  (gr_text "ESPNoise Rev C CNC - USER FACE" (at 51 3) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))))',
        '  (gr_text "INTERNAL - SOLDER WIRE VIAS BOTH FACES" (at 48 23.5) (layer "B.SilkS") (effects (font (size 0.65 0.65) (thickness 0.10)) (justify mirror)))',
        ")",
    ])
    (HERE / f"{BOARD_NAME}.kicad_pcb").write_text("\n".join(lines) + "\n", encoding="utf-8")


def gerber_coord(value: float) -> str:
    return f"{int(round(value * 1_000_000)):010d}"


def panel_point(instance: int, x: float, y: float) -> tuple[float, float]:
    if instance == 0:
        return x, y
    return PANEL_WIDTH - x, PANEL_HEIGHT - y


def write_copper_gerber(layer: str, suffix: str, *, panel: bool = False) -> None:
    layer_tracks = [item for item in tracks if item.layer == layer]
    layer_pads: list[Pad] = []
    for _, item in all_pads():
        if not item.net:
            continue
        if item.side == "both" or item.side == layer:
            layer_pads.append(item)
    aperture_specs: list[tuple[str, tuple[float, ...]]] = []
    for item in layer_tracks:
        aperture_specs.append(("C", (item.width,)))
    for item in layer_pads:
        if item.shape == "rect":
            aperture_specs.append(("R", (item.width or 0, item.height or 0)))
        else:
            aperture_specs.append(("C", (item.diameter,)))
    for item in vias:
        aperture_specs.append(("C", (item.diameter,)))
    unique_specs = list(dict.fromkeys(aperture_specs))
    aperture_ids = {spec: 10 + index for index, spec in enumerate(unique_specs)}
    kind = "two-unit panel" if panel else "unit"
    lines = [f"G04 ESPNoise Rev C {kind} {layer}*", "%FSLAX46Y46*%", "%MOMM*%", "%LPD*%"]
    for spec in unique_specs:
        if spec[0] == "C":
            lines.append(f"%ADD{aperture_ids[spec]}C,{spec[1][0]:.6f}*%")
        else:
            lines.append(f"%ADD{aperture_ids[spec]}R,{spec[1][0]:.6f}X{spec[1][1]:.6f}*%")
    for instance in range(2 if panel else 1):
        for item in layer_tracks:
            track_spec = ("C", (item.width,))
            lines.append(f"D{aperture_ids[track_spec]}*")
            points = [panel_point(instance, x, y) if panel else (x, y) for x, y in item.points]
            start = points[0]
            lines.append(f"X{gerber_coord(start[0])}Y{gerber_coord(start[1])}D02*")
            for x, y in points[1:]:
                lines.append(f"X{gerber_coord(x)}Y{gerber_coord(y)}D01*")
        for item in layer_pads:
            spec = ("R", (item.width or 0, item.height or 0)) if item.shape == "rect" else ("C", (item.diameter,))
            x, y = panel_point(instance, item.x, item.y) if panel else (item.x, item.y)
            lines.extend([f"D{aperture_ids[spec]}*", f"X{gerber_coord(x)}Y{gerber_coord(y)}D03*"])
        for item in vias:
            spec = ("C", (item.diameter,))
            x, y = panel_point(instance, item.x, item.y) if panel else (item.x, item.y)
            lines.extend([f"D{aperture_ids[spec]}*", f"X{gerber_coord(x)}Y{gerber_coord(y)}D03*"])
    lines.append("M02*")
    output_name = PANEL_NAME if panel else BOARD_NAME
    (HERE / "gerbers" / f"{output_name}-{suffix}").write_text("\n".join(lines) + "\n", encoding="ascii")


def write_outline_gerber(*, panel: bool = False) -> None:
    width = PANEL_WIDTH if panel else BOARD_WIDTH
    height = PANEL_HEIGHT if panel else BOARD_HEIGHT
    output_name = PANEL_NAME if panel else BOARD_NAME
    lines = [
        f"G04 ESPNoise Rev C {'panel' if panel else 'unit'} outline*", "%FSLAX46Y46*%", "%MOMM*%", "%LPD*%", "%ADD10C,0.100000*%", "D10*",
        f"X{gerber_coord(0)}Y{gerber_coord(0)}D02*",
        f"X{gerber_coord(width)}Y{gerber_coord(0)}D01*",
        f"X{gerber_coord(width)}Y{gerber_coord(height)}D01*",
        f"X{gerber_coord(0)}Y{gerber_coord(height)}D01*",
        f"X{gerber_coord(0)}Y{gerber_coord(0)}D01*",
    ]
    if panel:
        lines.extend([
            f"X{gerber_coord(0)}Y{gerber_coord(PANEL_CUT_Y)}D02*",
            f"X{gerber_coord(PANEL_WIDTH)}Y{gerber_coord(PANEL_CUT_Y)}D01*",
        ])
    lines.append("M02*")
    (HERE / "gerbers" / f"{output_name}-Edge_Cuts.gm1").write_text("\n".join(lines) + "\n", encoding="ascii")


def write_coupon_files() -> None:
    """Write a 30 mm by 15 mm two-face process coupon."""
    coupon_dir = HERE / "coupon"
    coupon_dir.mkdir(parents=True, exist_ok=True)

    def copper_file(name: str, paths: list[list[tuple[float, float]]], flashes: list[tuple[float, float]]) -> None:
        lines = [
            f"G04 ESPNoise CNC process coupon {name}*", "%FSLAX46Y46*%", "%MOMM*%", "%LPD*%",
            "%ADD10C,0.500000*%", "%ADD11C,1.800000*%", "D10*",
        ]
        for path in paths:
            lines.append(f"X{gerber_coord(path[0][0])}Y{gerber_coord(path[0][1])}D02*")
            for x, y in path[1:]:
                lines.append(f"X{gerber_coord(x)}Y{gerber_coord(y)}D01*")
        lines.append("D11*")
        for x, y in flashes:
            lines.append(f"X{gerber_coord(x)}Y{gerber_coord(y)}D03*")
        lines.append("M02*")
        (coupon_dir / name).write_text("\n".join(lines) + "\n", encoding="ascii")

    copper_file(
        "coupon-F_Cu.gtl",
        [[(3, 4), (27, 4)], [(3, 7.5), (27, 7.5)], [(3, 11), (27, 11)]],
        [(3, 4), (27, 4), (3, 7.5), (27, 7.5), (3, 11), (27, 11), (8, 7.5), (22, 7.5)],
    )
    copper_file(
        "coupon-B_Cu.gbl",
        [[(8, 3), (8, 12)], [(15, 3), (15, 12)], [(22, 3), (22, 12)]],
        [(8, 3), (8, 7.5), (8, 12), (15, 3), (15, 12), (22, 3), (22, 7.5), (22, 12)],
    )
    drill_rows = [
        (15.0, 2.0, 2.0, "registration"), (15.0, 13.0, 2.0, "registration"),
        (8.0, 7.5, 0.8, "via test"), (22.0, 7.5, 0.8, "via test"),
        (5.0, 7.5, 0.9, "0.9 mm fit test"), (12.0, 7.5, 1.0, "1.0 mm fit test"),
    ]
    lines = ["diameter_mm,x_mm,y_mm,purpose"]
    lines.extend(f"{diameter:.1f},{x:.3f},{y:.3f},{purpose}" for x, y, diameter, purpose in drill_rows)
    (coupon_dir / "coupon-drills.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_drills(*, panel: bool = False) -> None:
    holes: list[tuple[float, float, float, str]] = []
    for instance in range(2 if panel else 1):
        unit = "A" if instance == 0 else "B"
        for component, item in all_pads():
            if item.drill > 0:
                x, y = panel_point(instance, item.x, item.y) if panel else (item.x, item.y)
                holes.append((x, y, item.drill, f"{unit}-{component.ref}-{item.number}" if panel else f"{component.ref}-{item.number}"))
        for x, y in registration_holes:
            x, y = panel_point(instance, x, y) if panel else (x, y)
            holes.append((x, y, 2.0, f"{unit}-registration" if panel else "registration"))
        for item in vias:
            x, y = panel_point(instance, item.x, item.y) if panel else (item.x, item.y)
            holes.append((x, y, item.drill, f"{unit}-wire-via" if panel else "wire-via"))
    grouped: dict[float, list[tuple[float, float, str]]] = {}
    for x, y, diameter, label in holes:
        grouped.setdefault(diameter, []).append((x, y, label))
    gerber_dir = HERE / "gerbers"
    output_name = PANEL_NAME if panel else BOARD_NAME
    for diameter, positions in sorted(grouped.items()):
        file_name = gerber_dir / f"{output_name}-drill-{diameter:.1f}mm.drl"
        lines = ["M48", ";DRILL file generated by ESPNoise", "METRIC,TZ", f"T1C{diameter:.3f}", "%", "G90", "G05", "T1"]
        for x, y, _ in positions:
            lines.append(f"X{int(round(x * 1000)):06d}Y{int(round(y * 1000)):06d}")
        lines.extend(["T0", "M30"])
        file_name.write_text("\n".join(lines) + "\n", encoding="ascii")
    csv_lines = ["diameter_mm,x_mm,y_mm,purpose"]
    csv_lines.extend(f"{diameter:.1f},{x:.3f},{y:.3f},{label}" for x, y, diameter, label in sorted(holes, key=lambda row: (row[2], row[1], row[0])))
    (HERE / "gerbers" / f"{output_name}-drills.csv").write_text("\n".join(csv_lines) + "\n", encoding="utf-8")


def write_svg(face: str, layer: str, output: str, *, panel: bool = False) -> None:
    mirror = face == "Internal"
    width = PANEL_WIDTH if panel else BOARD_WIDTH
    height = PANEL_HEIGHT if panel else BOARD_HEIGHT
    transform = f'translate({width} 0) scale(-1 1)' if mirror else ""
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}mm" height="{height}mm" viewBox="0 0 {width} {height}">',
        f'<rect width="{width}" height="{height}" fill="#f0d47a" stroke="#222" stroke-width="0.2"/>',
        f'<g transform="{transform}">',
    ]
    color = "#8b3f12"
    for instance in range(2 if panel else 1):
        instance_transform = f'matrix(-1 0 0 -1 {PANEL_WIDTH} {PANEL_HEIGHT})' if panel and instance == 1 else ""
        svg.append(f'<g transform="{instance_transform}">')
        svg.append(f'<rect width="{BOARD_WIDTH}" height="{BOARD_HEIGHT}" fill="none" stroke="#333" stroke-width="0.15"/>')
        svg.append(f'<line x1="0" y1="{USER_CENTERLINE_Y}" x2="{BOARD_WIDTH}" y2="{USER_CENTERLINE_Y}" stroke="#777" stroke-width="0.12" stroke-dasharray="1,1"/>')
        for item in tracks:
            if item.layer != layer:
                continue
            points = " ".join(f"{x},{y}" for x, y in item.points)
            svg.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{item.width}" stroke-linecap="round" stroke-linejoin="round"/>')
        for component in components:
            if component.face != face:
                continue
            if component.body_shape == "circle":
                svg.append(
                    f'<circle cx="{component.x}" cy="{component.y}" r="{component.body_width / 2}" fill="#e8e8e8" fill-opacity="0.8" stroke="#111" stroke-width="0.25"/>'
                )
                svg.append(
                    f'<path d="M {component.x - 1} {component.y - component.body_height / 2} L {component.x + 1} {component.y - component.body_height / 2}" stroke="#111" stroke-width="0.5"/>'
                )
                if component.ref == "MIC1":
                    acoustic_x = component.x + MIC_ACOUSTIC_OFFSET_X
                    acoustic_y = component.y + MIC_ACOUSTIC_OFFSET_Y
                    svg.append(
                        f'<circle cx="{acoustic_x}" cy="{acoustic_y}" r="0.7" fill="#fff" stroke="#0e7490" stroke-width="0.35"/>'
                    )
            elif component.body_shape == "rect":
                svg.append(
                    f'<rect x="{component.x - component.body_width / 2}" y="{component.y - component.body_height / 2}" width="{component.body_width}" height="{component.body_height}" fill="#e8e8e8" fill-opacity="0.8" stroke="#111" stroke-width="0.25"/>'
                )
            if component.body_shape != "none":
                label_y = component.y + 2.0 if component.ref == "MIC1" else component.y
                svg.append(f'<text x="{component.x}" y="{label_y}" font-size="1.4" text-anchor="middle" dominant-baseline="middle">{component.ref}</text>')
            else:
                for item in component.pads:
                    label_y = item.y + 1.7 if item.y < BOARD_HEIGHT / 2 else item.y - 1.3
                    svg.append(
                        f'<text x="{item.x}" y="{label_y}" font-size="0.65" text-anchor="middle">{component.ref}-{item.number}</text>'
                    )
        for _, item in all_pads():
            if item.drill > 0:
                svg.append(f'<circle cx="{item.x}" cy="{item.y}" r="{item.diameter / 2}" fill="{color}"/><circle cx="{item.x}" cy="{item.y}" r="{item.drill / 2}" fill="#fff"/>')
            elif item.side == layer:
                svg.append(f'<rect x="{item.x - (item.width or 0) / 2}" y="{item.y - (item.height or 0) / 2}" width="{item.width}" height="{item.height}" fill="{color}"/>')
        for item in vias:
            svg.append(f'<circle cx="{item.x}" cy="{item.y}" r="{item.diameter / 2}" fill="{color}"/><circle cx="{item.x}" cy="{item.y}" r="{item.drill / 2}" fill="#fff"/>')
        for x, y in registration_holes:
            svg.append(f'<circle cx="{x}" cy="{y}" r="1" fill="#fff" stroke="#222" stroke-width="0.2"/>')
        svg.append("</g>")
    if panel:
        svg.append(f'<line x1="0" y1="{PANEL_CUT_Y}" x2="{PANEL_WIDTH}" y2="{PANEL_CUT_Y}" stroke="#d22" stroke-width="0.25" stroke-dasharray="1,0.7"/>')
    svg.extend(["</g>", f'<text x="{width / 2}" y="{height - 0.7}" font-size="1.1" text-anchor="middle">ESPNoise Rev C CNC — {face} face{' — two-unit panel' if panel else ''}</text>', "</svg>"])
    (HERE / output).write_text("\n".join(svg) + "\n", encoding="utf-8")


def write_bom() -> None:
    rows = ["ref,quantity,value,face,footprint,note"]
    for component in components:
        note = component.note.replace('"', '""')
        rows.append(f'{component.ref},1,"{component.value}",{component.face},{component.footprint},"{note}"')
    (HERE / f"{BOARD_NAME}-bom.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")


def write_netlist() -> None:
    rows = ["reference,pin,net,description"]
    for component, item in all_pads():
        if not item.net:
            continue
        description = component.value.replace('"', '""')
        rows.append(f'{component.ref},{item.number},{item.net},"{description}"')
    (HERE / f"{BOARD_NAME}-netlist.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")


def write_component_fit_check() -> None:
    """Write a print-scale check that uses the PCB footprint dimensions."""
    mic_radius = MIC_MODULE_DIAMETER / 2
    buzzer_radius = BUZZER_BODY_DIAMETER / 2
    mic_left = 55 - MIC_PIN_PITCH_X
    mic_right = 55 + MIC_PIN_PITCH_X
    mic_top = 65 - MIC_ROW_PITCH_Y / 2
    mic_bottom = 65 + MIC_ROW_PITCH_Y / 2
    buzzer_left = 145 - BUZZER_LEAD_PITCH / 2
    buzzer_right = 145 + BUZZER_LEAD_PITCH / 2
    copper_hole = lambda x, y: (
        f'<circle cx="{x:.2f}" cy="{y:.2f}" r="0.7" fill="#8b3f12"/>'
        f'<circle cx="{x:.2f}" cy="{y:.2f}" r="0.45" fill="#fff"/>'
    )
    lines = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="100mm" viewBox="0 0 210 100">',
        '<style>text { font-family: Arial, sans-serif; fill: #172033; } .title { font-size: 6px; font-weight: 700; } .label { font-size: 4px; font-weight: 700; } .small { font-size: 3px; } .part { fill: #e8e8e8; fill-opacity: 0.8; stroke: #111; stroke-width: 0.5; } .center { stroke: #0e7490; stroke-width: 0.2; stroke-dasharray: 1 1; } .scale { stroke: #172033; stroke-width: 0.5; }</style>',
        '<rect width="210" height="100" fill="white"/>',
        '<text x="8" y="10" class="title">ESPNoise 1:1 component fit check</text>',
        '<text x="8" y="16" class="small">Print at 100% scale. Do not use Fit to page. The 50 mm check line must measure exactly 50 mm.</text>',
        '<line x1="8" y1="25" x2="58" y2="25" class="scale"/><line x1="8" y1="22" x2="8" y2="28" class="scale"/><line x1="58" y1="22" x2="58" y2="28" class="scale"/>',
        '<text x="33" y="22" text-anchor="middle" class="label">50.00 mm</text>',
        '<text x="55" y="40" text-anchor="middle" class="label">MIC1 — label side, notch at top</text>',
        f'<circle cx="55" cy="65" r="{mic_radius:.2f}" class="part"/>',
        f'<path d="M52.5 {65 - mic_radius + 0.35:.2f} Q55 {65 - mic_radius + 2.8:.2f} 57.5 {65 - mic_radius + 0.35:.2f}" fill="none" stroke="#111" stroke-width="0.35"/>',
        '<line x1="45" y1="65" x2="65" y2="65" class="center"/><line x1="55" y1="55" x2="55" y2="75" class="center"/>',
        '<circle cx="55" cy="65" r="0.8" fill="#fff" stroke="#0e7490" stroke-width="0.35"/><text x="63" y="66" class="small">centered acoustic hole</text>',
        copper_hole(mic_left, mic_top) + copper_hole(55, mic_top) + copper_hole(mic_right, mic_top),
        copper_hole(mic_left, mic_bottom) + copper_hole(55, mic_bottom) + copper_hole(mic_right, mic_bottom),
        f'<text x="{mic_left:.2f}" y="{mic_top - 1.9:.2f}" text-anchor="middle" class="small">1</text><text x="55" y="{mic_top - 1.9:.2f}" text-anchor="middle" class="small">2</text><text x="{mic_right:.2f}" y="{mic_top - 1.9:.2f}" text-anchor="middle" class="small">3</text>',
        f'<text x="{mic_left:.2f}" y="{mic_bottom + 3.5:.2f}" text-anchor="middle" class="small">4</text><text x="55" y="{mic_bottom + 3.5:.2f}" text-anchor="middle" class="small">5</text><text x="{mic_right:.2f}" y="{mic_bottom + 3.5:.2f}" text-anchor="middle" class="small">6</text>',
        f'<text x="55" y="80" text-anchor="middle" class="small">APPROXIMATE: body {MIC_MODULE_DIAMETER:.2f} mm</text>',
        f'<text x="55" y="84" text-anchor="middle" class="small">CONFIRMED: row {MIC_ROW_PITCH_Y:.2f} mm; pins {MIC_PIN_PITCH_X:.2f} mm</text>',
        '<text x="145" y="40" text-anchor="middle" class="label">BZ1 — sound-port side</text>',
        f'<circle cx="145" cy="65" r="{buzzer_radius:.2f}" class="part"/>',
        '<line x1="137" y1="65" x2="153" y2="65" class="center"/><line x1="145" y1="57" x2="145" y2="73" class="center"/>',
        copper_hole(buzzer_left, 65) + copper_hole(buzzer_right, 65),
        f'<text x="{buzzer_left:.2f}" y="62" text-anchor="middle" class="small">2 −</text><text x="{buzzer_right:.2f}" y="62" text-anchor="middle" class="small">1 +</text>',
        f'<text x="145" y="80" text-anchor="middle" class="small">MEASURED: body {BUZZER_BODY_DIAMETER:.2f} mm</text>',
        f'<text x="145" y="84" text-anchor="middle" class="small">lead pitch {BUZZER_LEAD_PITCH:.2f} mm; lead {BUZZER_LEAD_DIAMETER:.2f} mm</text>',
        '<rect x="8" y="88" width="194" height="8" fill="#fff7ed" stroke="#c2410c" stroke-width="0.3"/>',
        '<text x="105" y="93" text-anchor="middle" class="label">STOP if a body or lead does not align. Measure the real part and regenerate the PCB.</text>',
        '</svg>',
    ]
    (HERE / "espnoise-component-fit-check.svg").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    (HERE / "gerbers").mkdir(parents=True, exist_ok=True)
    validate()
    write_kicad_board()
    write_copper_gerber("F.Cu", "F_Cu.gtl")
    write_copper_gerber("B.Cu", "B_Cu.gbl")
    write_outline_gerber()
    write_copper_gerber("F.Cu", "F_Cu.gtl", panel=True)
    write_copper_gerber("B.Cu", "B_Cu.gbl", panel=True)
    write_outline_gerber(panel=True)
    write_coupon_files()
    write_drills()
    write_drills(panel=True)
    write_svg("User", "F.Cu", f"{BOARD_NAME}-user.svg")
    write_svg("Internal", "B.Cu", f"{BOARD_NAME}-internal.svg")
    write_svg("User", "F.Cu", f"{PANEL_NAME}-user.svg", panel=True)
    write_svg("Internal", "B.Cu", f"{PANEL_NAME}-internal.svg", panel=True)
    write_bom()
    write_netlist()
    write_component_fit_check()
    print(f"Generated and validated ESPNoise Rev C CNC files in {HERE}")


if __name__ == "__main__":
    main()
