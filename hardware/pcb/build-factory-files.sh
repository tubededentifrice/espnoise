#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PCB_DIR="$PROJECT_ROOT/hardware/pcb"
OUTPUT_DIR="$PCB_DIR/jlcpcb"
GERBER_DIR="$OUTPUT_DIR/gerbers"

if [ -x "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli" ]; then
    KICAD_CLI="/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
    KICAD_PYTHON="/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9"
    KICAD_FOOTPRINT_DIR="/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
elif [ -x "/Volumes/KiCad/KiCad/KiCad.app/Contents/MacOS/kicad-cli" ]; then
    KICAD_CLI="/Volumes/KiCad/KiCad/KiCad.app/Contents/MacOS/kicad-cli"
    KICAD_PYTHON="/Volumes/KiCad/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3.9"
    KICAD_FOOTPRINT_DIR="/Volumes/KiCad/KiCad/KiCad.app/Contents/SharedSupport/footprints"
else
    echo "KiCad 10 was not found. Install KiCad 10 and run this script again." >&2
    exit 1
fi

export KICAD_FOOTPRINT_DIR
KICAD_CONFIG_HOME="${TMPDIR:-/tmp}/espnoise-kicad-config"
export KICAD_CONFIG_HOME
mkdir -p "$KICAD_CONFIG_HOME"
mkdir -p "$GERBER_DIR"
rm -f "$OUTPUT_DIR/espnoise-carrier-drc.txt"
rm -f "$OUTPUT_DIR/espnoise-carrier-gerbers.zip"
find "$GERBER_DIR" -type f -delete
"$KICAD_PYTHON" "$PCB_DIR/generate_board.py"

"$KICAD_CLI" pcb drc --exit-code-violations --severity-error --output "$OUTPUT_DIR/espnoise-carrier-drc.txt" "$PCB_DIR/espnoise-carrier.kicad_pcb"
"$KICAD_CLI" pcb export gerbers --output "$GERBER_DIR/" --layers F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts "$PCB_DIR/espnoise-carrier.kicad_pcb"
"$KICAD_CLI" pcb export drill --output "$GERBER_DIR/" "$PCB_DIR/espnoise-carrier.kicad_pcb"
"$KICAD_CLI" pcb export svg --page-size-mode 2 --exclude-drawing-sheet --layers F.Cu,F.Silkscreen,F.Mask,Edge.Cuts --output "$OUTPUT_DIR/espnoise-carrier-top.svg" "$PCB_DIR/espnoise-carrier.kicad_pcb"
"$KICAD_CLI" pcb export svg --page-size-mode 2 --exclude-drawing-sheet --mirror --layers B.Cu,B.Silkscreen,B.Mask,Edge.Cuts --output "$OUTPUT_DIR/espnoise-carrier-bottom.svg" "$PCB_DIR/espnoise-carrier.kicad_pcb"
"$KICAD_CLI" pcb render --side top --width 1800 --height 900 --background opaque --output "$OUTPUT_DIR/espnoise-carrier-top.png" "$PCB_DIR/espnoise-carrier.kicad_pcb"
"$KICAD_CLI" pcb render --side bottom --width 1800 --height 900 --background opaque --output "$OUTPUT_DIR/espnoise-carrier-bottom.png" "$PCB_DIR/espnoise-carrier.kicad_pcb"

(cd "$GERBER_DIR" && zip -q -9 -FS "$OUTPUT_DIR/espnoise-carrier-gerbers.zip" ./*)
echo "Factory files are in $OUTPUT_DIR"
