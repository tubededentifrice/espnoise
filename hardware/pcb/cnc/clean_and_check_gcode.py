#!/usr/bin/env python3
"""Remove interactive tool stops and check the generated GRBL coordinates."""

from __future__ import annotations

import re
from hashlib import sha256
from pathlib import Path


HERE = Path(__file__).resolve().parent
MACHINE = HERE / "machine"
NUMBER = re.compile(r"([XYZ])(-?[0-9]+(?:\.[0-9]+)?)")


def main() -> None:
    files = sorted(MACHINE.glob("espnoise-cnc-*.nc")) + sorted(MACHINE.glob("coupon-*.nc"))
    if not files:
        raise SystemExit("No G-code files were found")
    for path in files:
        clean: list[str] = []
        extents: dict[str, list[float]] = {axis: [] for axis in "XYZ"}
        for line in path.read_text(encoding="ascii").splitlines():
            stripped = line.strip()
            command = stripped.split(maxsplit=1)[0] if stripped else ""
            if command in {"M0", "M00", "M6", "M06"}:
                continue
            if stripped.startswith("T") and stripped[1:].isdigit():
                continue
            if stripped.startswith("(MSG, Change tool bit"):
                continue
            for axis, value in NUMBER.findall(line):
                extents[axis].append(float(value))
            clean.append(line)
        while clean and not clean[-1].strip():
            clean.pop()
        if extents["X"] and (min(extents["X"]) < -0.01 or max(extents["X"]) > 70.01):
            raise SystemExit(f"Unsafe X range in {path.name}: {min(extents['X'])} to {max(extents['X'])}")
        if extents["Y"] and (min(extents["Y"]) < -0.01 or max(extents["Y"]) > 50.01):
            raise SystemExit(f"Unsafe Y range in {path.name}: {min(extents['Y'])} to {max(extents['Y'])}")
        if extents["Z"] and (min(extents["Z"]) < -1.81 or max(extents["Z"]) > 10.01):
            raise SystemExit(f"Unsafe Z range in {path.name}: {min(extents['Z'])} to {max(extents['Z'])}")
        path.write_text("\n".join(clean) + "\n", encoding="ascii")
        ranges = ", ".join(
            f"{axis} {min(values):.2f}..{max(values):.2f}" for axis, values in extents.items() if values
        )
        print(f"Checked {path.name}: {ranges}")
    checksums = []
    for path in files:
        checksums.append(f"{sha256(path.read_bytes()).hexdigest()}  {path.name}")
    (MACHINE / "SHA256SUMS").write_text("\n".join(checksums) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()
