#!/usr/bin/env python3
"""Generate the ESPNoise Rev C board for a two-face CNC process.

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
BOARD_WIDTH = 70.0
BOARD_HEIGHT = 50.0
MIN_TRACK_WIDTH = 0.50
MIN_CLEARANCE = 0.40


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
    diameter: float = 1.8
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


def th_pad(number: int | str, x: float, y: float, net: str, *, drill: float = 0.9) -> Pad:
    return Pad(str(number), x, y, net, diameter=max(1.6, drill + 0.6), drill=drill)


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
        9.0,
        10.0,
        7.0,
        7.0,
        (
            th_pad(1, 7.0, 7.5, "+5V_BUZZER_SW", drill=1.0),
            th_pad(2, 9.0, 7.5, "+5V_PERIPH", drill=1.0),
            th_pad(3, 11.0, 7.5, "" , drill=1.0),
            th_pad(4, 7.0, 12.5, "", drill=1.0),
            th_pad(5, 9.0, 12.5, "", drill=1.0),
            th_pad(6, 11.0, 12.5, "", drill=1.0),
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
        22.0,
        10.0,
        7.0,
        7.0,
        (
            th_pad(1, 20.0, 7.5, "", drill=1.0),
            th_pad(2, 22.0, 7.5, "MUTE_N", drill=1.0),
            th_pad(3, 24.0, 7.5, "GND", drill=1.0),
            th_pad(4, 20.0, 12.5, "", drill=1.0),
            th_pad(5, 22.0, 12.5, "", drill=1.0),
            th_pad(6, 24.0, 12.5, "", drill=1.0),
        ),
        "Momentary mute button.",
        "ESPNoise:7x7_DPDT_Pushbutton",
    )
)

mic_x = [6.0 + 2.54 * index for index in range(6)]
mic_nets = ["MIC_SCK", "MIC_WS", "GND", "MIC_SD", "+3V3", "GND"]
mic_labels = ["SCK", "WS", "L/R", "SD", "VDD", "GND"]
add_component(
    Component(
        "MIC1",
        "INMP441 1x6 MODULE",
        "User",
        sum(mic_x) / len(mic_x),
        31.0,
        18.0,
        14.0,
        tuple(th_pad(index + 1, x, 31.0, net) for index, (x, net) in enumerate(zip(mic_x, mic_nets))),
        "Pin order from left: " + ", ".join(mic_labels) + ". Confirm the module labels before soldering.",
        "ESPNoise:INMP441_1x6_P2.54mm",
    )
)
add_component(
    Component(
        "BZ1",
        "FUET-1370F-05",
        "User",
        57.0,
        13.0,
        12.8,
        12.8,
        (
            smd_pad(1, 62.325, 13.0, "+5V_BUZZER_SW", 4.15, 3.0),
            smd_pad(2, 51.675, 13.0, "BUZZER_COLLECTOR", 4.15, 3.0),
        ),
        "Top sound port. Pad 1 is positive.",
        "ESPNoise:FUET-1370F-05",
    )
)

# Internal face: all other components and all external connectors.
j2_x = [3.5 + 2.5 * index for index in range(10)]
j2_nets = [
    "+5V_IN", "GND", "+3V3", "MIC_SCK", "MIC_WS", "MIC_SD",
    "LED_DATA_3V3", "BUZZER_PWM", "MUTE_N", "GND",
]
add_component(
    Component(
        "J2", "CONTROLLER JST XH 1x10", "Internal", 14.75, 45.0, 25.0, 5.0,
        tuple(th_pad(index + 1, x, 45.0, net) for index, (x, net) in enumerate(zip(j2_x, j2_nets))),
        "Cable entry is on the internal face.", "JST:B10B-XH-A",
    )
)
add_component(
    Component(
        "J3", "LED STRIP JST XH 1x5", "Internal", 35.0, 45.0, 12.5, 5.0,
        tuple(
            th_pad(index + 1, 30.0 + 2.5 * index, 45.0, net)
            for index, net in enumerate(["+5V_PERIPH", "GND", "LED_DATA_5V", "+5V_PERIPH", "GND"])
        ),
        "Pins 1 and 4 supply the two strip ends.", "JST:B5B-XH-A",
    )
)
add_component(
    Component(
        "J1", "USB-C 5V JST XH 1x2", "Internal", 46.25, 45.0, 5.0, 5.0,
        (th_pad(1, 45.0, 45.0, "+5V_IN"), th_pad(2, 47.5, 45.0, "GND")),
        "Power-only input. Keep it separate from the ESP32 service port.", "JST:B2B-XH-A",
    )
)

dip_left_x = 30.0
dip_right_x = 37.62
dip_y = [4.5 + 2.54 * index for index in range(7)]
u1_pad_positions = [(index + 1, dip_left_x, y) for index, y in enumerate(dip_y)]
u1_pad_positions += [(14 - index, dip_right_x, y) for index, y in enumerate(dip_y)]
u1_nets = {
    1: "GND", 2: "LED_DATA_3V3", 3: "LED_DATA_5V_RAW", 4: "+5V_PERIPH",
    5: "GND", 6: "", 7: "GND", 8: "", 9: "GND", 10: "+5V_PERIPH",
    11: "", 12: "GND", 13: "+5V_PERIPH", 14: "+5V_PERIPH",
}
add_component(
    Component(
        "U1", "SN74AHCT125N", "Internal", 33.81, 12.12, 10.0, 19.0,
        tuple(th_pad(number, x, y, u1_nets[number]) for number, x, y in u1_pad_positions),
        "Use AHCT. Do not replace it with HC.", "Package_DIP:DIP-14_W7.62mm",
    )
)

def axial(ref: str, value: str, x1: float, y1: float, x2: float, y2: float, net1: str, net2: str) -> None:
    add_component(
        Component(ref, value, "Internal", (x1 + x2) / 2, (y1 + y2) / 2, abs(x2 - x1) + 2, 2.5,
                  (th_pad(1, x1, y1, net1), th_pad(2, x2, y2, net2)), footprint="THT:Axial")
    )


axial("R1", "330R", 43.0, 16.0, 50.0, 16.0, "LED_DATA_5V_RAW", "LED_DATA_5V")
axial("R2", "1K", 43.0, 28.0, 50.0, 28.0, "BUZZER_PWM", "BUZZER_BASE")
axial("R3", "100K", 50.0, 32.0, 57.0, 32.0, "BUZZER_BASE", "GND")
axial("D1", "1N5819", 50.0, 23.0, 60.0, 23.0, "+5V_BUZZER_SW", "BUZZER_COLLECTOR")

add_component(
    Component("C1", "100nF", "Internal", 41.0, 5.5, 5.0, 3.0,
              (th_pad(1, 40.0, 5.5, "+5V_PERIPH"), th_pad(2, 42.0, 5.5, "GND")),
              "Place it close to U1 pins 14 and 7.", "THT:C_Disc_P2.00mm")
)
add_component(
    Component("F1", "0.5A PTC MF-R050", "Internal", 58.0, 40.0, 6.0, 4.0,
              (th_pad(1, 55.5, 40.0, "+5V_IN", drill=1.0), th_pad(2, 60.5, 40.0, "+5V_PERIPH", drill=1.0)),
              footprint="THT:Fuse_Radial_P5.00mm")
)
add_component(
    Component("C2", "1000uF 10V", "Internal", 64.0, 34.0, 10.0, 10.0,
              (th_pad(1, 61.5, 34.0, "+5V_PERIPH", drill=1.0), th_pad(2, 66.5, 34.0, "GND", drill=1.0)),
              "Pad 1 is positive.", "THT:CP_Radial_D8_P5.00mm")
)
add_component(
    Component("Q1", "2N3904", "Internal", 55.0, 28.0, 5.0, 4.0,
              (th_pad(1, 52.46, 28.0, "GND"), th_pad(2, 55.0, 28.0, "BUZZER_BASE"),
               th_pad(3, 57.54, 28.0, "BUZZER_COLLECTOR")),
              "Flat-face pin order is E-B-C. Confirm the transistor data sheet.", "THT:TO-92_Inline_EBC")
)

# Registration holes are also usable as mounting holes. They have no copper.
registration_holes = [(35.0, 2.5), (35.0, 47.5)]


def all_pads() -> Iterable[tuple[Component, Pad]]:
    for component in components:
        for item in component.pads:
            yield component, item


ROUTER_GRID = 0.50
LAYER_NAMES = ("F.Cu", "B.Cu")


def grid_point(x: float, y: float, layer: int) -> tuple[int, int, int]:
    return (round(x / ROUTER_GRID), round(y / ROUTER_GRID), layer)


def world_point(node: tuple[int, int, int]) -> tuple[float, float]:
    return (node[0] * ROUTER_GRID, node[1] * ROUTER_GRID)


def preferred_layer(component: Component, item: Pad) -> int:
    if item.drill == 0:
        return 0
    # Put the solder joint and the connected track on the face opposite the body.
    return 1 if component.face == "User" else 0


def route_board() -> None:
    """Route all nets with a deterministic two-layer Manhattan grid router."""
    endpoints: dict[str, list[tuple[int, int, int]]] = {}
    for component, item in all_pads():
        if item.net:
            endpoints.setdefault(item.net, []).append(grid_point(item.x, item.y, preferred_layer(component, item)))

    occupied: dict[int, list[tuple[str, tuple[float, float], tuple[float, float], float]]] = {0: [], 1: []}
    occupied_vias: list[tuple[str, float, float, float]] = []
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
        if x < 1.5 or x > BOARD_WIDTH - 1.5 or y < 1.5 or y > BOARD_HEIGHT - 1.5:
            return True
        candidate_width = 0.6 if net in {"GND", "+5V_IN", "+5V_PERIPH", "+5V_BUZZER_SW"} else MIN_TRACK_WIDTH
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
            raise SystemExit(f"Router failed on net {net}")
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

    # Escape the 2 mm controller header first. Route the large rails after the
    # fine-pitch signals have clear paths.
    route_order = [
        "+3V3", "MIC_SCK", "MIC_WS", "MIC_SD", "LED_DATA_3V3", "MUTE_N", "BUZZER_PWM",
        "+5V_BUZZER_SW", "LED_DATA_5V_RAW", "LED_DATA_5V", "BUZZER_BASE",
        "BUZZER_COLLECTOR", "+5V_IN", "+5V_PERIPH", "GND",
    ]
    priority = {net: index for index, net in enumerate(route_order)}
    ordered_nets = sorted(endpoints, key=lambda net: priority.get(net, 100))
    for net in ordered_nets:
        net_points = endpoints[net]
        tree: set[tuple[int, int, int]] = {net_points[0]}
        remaining = set(net_points[1:])
        while remaining:
            goal = min(
                remaining,
                key=lambda item: min(abs(item[0] - root[0]) + abs(item[1] - root[1]) + 10 * (item[2] != root[2]) for root in tree),
            )
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
                width = 0.6 if net in {"GND", "+5V_IN", "+5V_PERIPH", "+5V_BUZZER_SW"} else MIN_TRACK_WIDTH
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
        lines.extend([
            f'  (footprint "{component.footprint}"', f'    (layer "{layer}")',
            f'    (uuid "{kicad_uuid(component.ref)}")', '    (at 0 0)',
            f'    (property "Reference" "{component.ref}" (at {component.x:.3f} {component.y - component.body_height / 2 - 1.3:.3f} 0) (layer "{silk}") (effects (font (size 1 1) (thickness 0.15))))',
            f'    (property "Value" "{component.value}" (at {component.x:.3f} {component.y + component.body_height / 2 + 1.3:.3f} 0) (layer "{silk}") (effects (font (size 0.8 0.8) (thickness 0.12))))',
            f'    (fp_rect (start {component.x - component.body_width / 2:.3f} {component.y - component.body_height / 2:.3f}) (end {component.x + component.body_width / 2:.3f} {component.y + component.body_height / 2:.3f}) (stroke (width 0.25) (type default)) (fill none) (layer "{silk}"))',
        ])
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
        '  (gr_text "INTERNAL FACE - WIRE VIAS: SOLDER BOTH FACES" (at 35 48.5) (layer "B.SilkS") (effects (font (size 0.8 0.8) (thickness 0.12)) (justify mirror)))',
        ")",
    ])
    (HERE / f"{BOARD_NAME}.kicad_pcb").write_text("\n".join(lines) + "\n", encoding="utf-8")


def gerber_coord(value: float) -> str:
    return f"{int(round(value * 1_000_000)):010d}"


def write_copper_gerber(layer: str, suffix: str) -> None:
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
    lines = [
        f"G04 ESPNoise Rev C {layer}*", "%FSLAX46Y46*%", "%MOMM*%", "%LPD*%",
    ]
    for spec in unique_specs:
        if spec[0] == "C":
            lines.append(f"%ADD{aperture_ids[spec]}C,{spec[1][0]:.6f}*%")
        else:
            lines.append(f"%ADD{aperture_ids[spec]}R,{spec[1][0]:.6f}X{spec[1][1]:.6f}*%")
    for item in layer_tracks:
        track_spec = ("C", (item.width,))
        lines.append(f"D{aperture_ids[track_spec]}*")
        start = item.points[0]
        lines.append(f"X{gerber_coord(start[0])}Y{gerber_coord(start[1])}D02*")
        for x, y in item.points[1:]:
            lines.append(f"X{gerber_coord(x)}Y{gerber_coord(y)}D01*")
    for item in layer_pads:
        spec = ("R", (item.width or 0, item.height or 0)) if item.shape == "rect" else ("C", (item.diameter,))
        lines.extend([f"D{aperture_ids[spec]}*", f"X{gerber_coord(item.x)}Y{gerber_coord(item.y)}D03*"])
    for item in vias:
        spec = ("C", (item.diameter,))
        lines.extend([f"D{aperture_ids[spec]}*", f"X{gerber_coord(item.x)}Y{gerber_coord(item.y)}D03*"])
    lines.append("M02*")
    (HERE / "gerbers" / f"{BOARD_NAME}-{suffix}").write_text("\n".join(lines) + "\n", encoding="ascii")


def write_outline_gerber() -> None:
    lines = [
        "G04 ESPNoise Rev C board outline*", "%FSLAX46Y46*%", "%MOMM*%", "%LPD*%", "%ADD10C,0.100000*%", "D10*",
        f"X{gerber_coord(0)}Y{gerber_coord(0)}D02*",
        f"X{gerber_coord(BOARD_WIDTH)}Y{gerber_coord(0)}D01*",
        f"X{gerber_coord(BOARD_WIDTH)}Y{gerber_coord(BOARD_HEIGHT)}D01*",
        f"X{gerber_coord(0)}Y{gerber_coord(BOARD_HEIGHT)}D01*",
        f"X{gerber_coord(0)}Y{gerber_coord(0)}D01*", "M02*",
    ]
    (HERE / "gerbers" / f"{BOARD_NAME}-Edge_Cuts.gm1").write_text("\n".join(lines) + "\n", encoding="ascii")


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


def write_drills() -> None:
    holes: list[tuple[float, float, float, str]] = []
    for component, item in all_pads():
        if item.drill > 0:
            holes.append((item.x, item.y, item.drill, f"{component.ref}-{item.number}"))
    holes.extend((x, y, 2.0, "registration") for x, y in registration_holes)
    holes.extend((item.x, item.y, item.drill, "wire-via") for item in vias)
    grouped: dict[float, list[tuple[float, float, str]]] = {}
    for x, y, diameter, label in holes:
        grouped.setdefault(diameter, []).append((x, y, label))
    gerber_dir = HERE / "gerbers"
    for diameter, positions in sorted(grouped.items()):
        file_name = gerber_dir / f"{BOARD_NAME}-drill-{diameter:.1f}mm.drl"
        lines = ["M48", ";DRILL file generated by ESPNoise", "METRIC,TZ", f"T1C{diameter:.3f}", "%", "G90", "G05", "T1"]
        for x, y, _ in positions:
            lines.append(f"X{int(round(x * 1000)):06d}Y{int(round(y * 1000)):06d}")
        lines.extend(["T0", "M30"])
        file_name.write_text("\n".join(lines) + "\n", encoding="ascii")
    csv_lines = ["diameter_mm,x_mm,y_mm,purpose"]
    csv_lines.extend(f"{diameter:.1f},{x:.3f},{y:.3f},{label}" for x, y, diameter, label in sorted(holes, key=lambda row: (row[2], row[1], row[0])))
    (HERE / "gerbers" / f"{BOARD_NAME}-drills.csv").write_text("\n".join(csv_lines) + "\n", encoding="utf-8")


def write_svg(face: str, layer: str, output: str) -> None:
    mirror = face == "Internal"
    transform = f'translate({BOARD_WIDTH} 0) scale(-1 1)' if mirror else ""
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{BOARD_WIDTH}mm" height="{BOARD_HEIGHT}mm" viewBox="0 0 {BOARD_WIDTH} {BOARD_HEIGHT}">',
        '<rect width="70" height="50" fill="#f0d47a" stroke="#222" stroke-width="0.2"/>',
        f'<g transform="{transform}">',
    ]
    color = "#8b3f12"
    for item in tracks:
        if item.layer != layer:
            continue
        points = " ".join(f"{x},{y}" for x, y in item.points)
        svg.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{item.width}" stroke-linecap="round" stroke-linejoin="round"/>')
    for component in components:
        if component.face != face:
            continue
        svg.append(
            f'<rect x="{component.x - component.body_width / 2}" y="{component.y - component.body_height / 2}" width="{component.body_width}" height="{component.body_height}" fill="#e8e8e8" fill-opacity="0.8" stroke="#111" stroke-width="0.25"/>'
        )
        text_transform = f' transform="translate({2 * component.x} 0) scale(-1 1)"' if mirror else ""
        svg.append(f'<text x="{component.x}" y="{component.y}" font-size="1.6" text-anchor="middle" dominant-baseline="middle"{text_transform}>{component.ref}</text>')
    for _, item in all_pads():
        if item.drill > 0:
            svg.append(f'<circle cx="{item.x}" cy="{item.y}" r="{item.diameter / 2}" fill="{color}"/><circle cx="{item.x}" cy="{item.y}" r="{item.drill / 2}" fill="#fff"/>')
        elif item.side == layer:
            svg.append(f'<rect x="{item.x - (item.width or 0) / 2}" y="{item.y - (item.height or 0) / 2}" width="{item.width}" height="{item.height}" fill="{color}"/>')
    for item in vias:
        svg.append(f'<circle cx="{item.x}" cy="{item.y}" r="{item.diameter / 2}" fill="{color}"/><circle cx="{item.x}" cy="{item.y}" r="{item.drill / 2}" fill="#fff"/>')
    for x, y in registration_holes:
        svg.append(f'<circle cx="{x}" cy="{y}" r="1" fill="#fff" stroke="#222" stroke-width="0.2"/>')
    svg.extend(["</g>", f'<text x="35" y="49" font-size="1.4" text-anchor="middle">ESPNoise Rev C CNC — {face} face</text>', "</svg>"])
    (HERE / output).write_text("\n".join(svg) + "\n", encoding="utf-8")


def write_bom() -> None:
    rows = ["ref,quantity,value,face,footprint,note"]
    for component in components:
        note = component.note.replace('"', '""')
        rows.append(f'{component.ref},1,"{component.value}",{component.face},{component.footprint},"{note}"')
    (HERE / f"{BOARD_NAME}-bom.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")


def main() -> None:
    (HERE / "gerbers").mkdir(parents=True, exist_ok=True)
    validate()
    write_kicad_board()
    write_copper_gerber("F.Cu", "F_Cu.gtl")
    write_copper_gerber("B.Cu", "B_Cu.gbl")
    write_outline_gerber()
    write_coupon_files()
    write_drills()
    write_svg("User", "F.Cu", f"{BOARD_NAME}-user.svg")
    write_svg("Internal", "B.Cu", f"{BOARD_NAME}-internal.svg")
    write_bom()
    print(f"Generated and validated ESPNoise Rev C CNC files in {HERE}")


if __name__ == "__main__":
    main()
