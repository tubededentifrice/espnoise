#!/usr/bin/env python3
"""Run PlatformIO only after the repository dependency policy is enforced."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    subprocess.run(
        [sys.executable, str(root / "tools" / "check_dependency_age.py")],
        check=True,
        cwd=root,
    )

    pio = shutil.which("pio")
    if not pio:
        print("PlatformIO is not installed in the locked uv environment.", file=sys.stderr)
        return 1
    return subprocess.run([pio, *sys.argv[1:]], cwd=root / "firmware").returncode


if __name__ == "__main__":
    raise SystemExit(main())
