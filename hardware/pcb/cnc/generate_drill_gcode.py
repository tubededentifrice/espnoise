#!/usr/bin/env python3
"""Generate one simple GRBL drill job for each drill diameter."""

from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path


HERE = Path(__file__).resolve().parent
INPUT = HERE / "gerbers" / "espnoise-cnc-drills.csv"
OUTPUT = HERE / "machine"
SAFE_Z = 2.0
DRILL_Z = -1.8
DRILL_FEED = 60
SPINDLE_RPM = 10000


def main() -> None:
    grouped: dict[float, list[tuple[float, float, str]]] = defaultdict(list)
    with INPUT.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            grouped[float(row["diameter_mm"])].append(
                (float(row["x_mm"]), float(row["y_mm"]), row["purpose"])
            )
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for diameter, holes in sorted(grouped.items()):
        lines = [
            f"(ESPNoise Rev C {diameter:.1f} mm drill job)",
            "(Origin is the user-face lower-left board corner)",
            "G21", "G90", "G94", f"G0 Z{SAFE_Z:.3f}", f"M3 S{SPINDLE_RPM}", "G4 P2",
        ]
        for x, y, purpose in holes:
            lines.extend([
                f"({purpose})", f"G0 X{x:.3f} Y{y:.3f}",
                f"G1 Z{DRILL_Z:.3f} F{DRILL_FEED}", f"G0 Z{SAFE_Z:.3f}",
            ])
        lines.extend(["M5", "G0 X0 Y0", "M2"])
        (OUTPUT / f"espnoise-cnc-drill-{diameter:.1f}mm.nc").write_text(
            "\n".join(lines) + "\n", encoding="ascii"
        )
    with (HERE / "coupon" / "coupon-drills.csv").open(newline="", encoding="utf-8") as handle:
        coupon_holes = list(csv.DictReader(handle))
    coupon_grouped: dict[float, list[dict[str, str]]] = defaultdict(list)
    for row in coupon_holes:
        coupon_grouped[float(row["diameter_mm"])].append(row)
    for diameter, rows in sorted(coupon_grouped.items()):
        coupon_lines = [
            f"(ESPNoise coupon {diameter:.1f} mm drill job)", "G21", "G90", "G94",
            f"G0 Z{SAFE_Z:.3f}", f"M3 S{SPINDLE_RPM}", "G4 P2",
        ]
        for row in rows:
            x, y = float(row["x_mm"]), float(row["y_mm"])
            coupon_lines.extend([
                f"({row['purpose']})", f"G0 X{x:.3f} Y{y:.3f}",
                f"G1 Z{DRILL_Z:.3f} F{DRILL_FEED}", f"G0 Z{SAFE_Z:.3f}",
            ])
        coupon_lines.extend(["M5", "G0 X0 Y0", "M2"])
        (OUTPUT / f"coupon-drill-{diameter:.1f}mm.nc").write_text(
            "\n".join(coupon_lines) + "\n", encoding="ascii"
        )
    print(f"Generated {len(grouped)} drill jobs in {OUTPUT}")


if __name__ == "__main__":
    main()
