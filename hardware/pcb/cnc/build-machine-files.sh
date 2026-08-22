#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACHINE_DIR="$SCRIPT_DIR/machine"

command -v pcb2gcode >/dev/null 2>&1 || {
    echo "pcb2gcode was not found." >&2
    echo "On macOS, install it with: brew install pcb2gcode" >&2
    exit 1
}

python3 "$SCRIPT_DIR/generate_cnc_board.py"
mkdir -p "$MACHINE_DIR"
rm -f "$MACHINE_DIR"/espnoise-panel-*.nc
rm -f "$MACHINE_DIR"/espnoise-cnc-*.nc
rm -f "$MACHINE_DIR"/coupon-*.nc
rm -f "$MACHINE_DIR"/contentions_*.svg
rm -f "$MACHINE_DIR"/processed_*.svg
rm -f "$MACHINE_DIR"/traced_*.svg
rm -f "$MACHINE_DIR"/outp*_original_*.svg
rm -f "$MACHINE_DIR"/*.png

(cd "$SCRIPT_DIR" && pcb2gcode --config millproject)
(cd "$SCRIPT_DIR" && pcb2gcode --config millproject-coupon)
if find "$MACHINE_DIR" -maxdepth 1 -name 'contentions_*.svg' | grep -q .; then
    echo "pcb2gcode found a clearance contention. Check the contention SVG file." >&2
    exit 1
fi
python3 "$SCRIPT_DIR/generate_drill_gcode.py"
python3 "$SCRIPT_DIR/clean_and_check_gcode.py"
rm -f "$MACHINE_DIR"/processed_*.svg
rm -f "$MACHINE_DIR"/traced_*.svg
rm -f "$MACHINE_DIR"/outp*_original_*.svg

echo "Machine files are in $MACHINE_DIR"
echo "Do not run them until the coupon and the preflight checks pass."
