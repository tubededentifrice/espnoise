---
name: maintain-espnoise-hardware
description: Create or change ESPNoise schematics, PCB layouts, footprints, factory exports, and Cubiko CNC files. Use for ESPNoise hardware design and fabrication work, not for firmware-only changes or generic electronics-tool development.
---

# Maintain ESPNoise Hardware

Keep the electrical design easy to inspect. Give each symbol, connector, pad,
and wire a reference, pin number, signal name, and polarity where applicable.
Keep the schematic, PCB, BOM, wiring document, and fabrication notes consistent.

## Physical parts

- Keep product schematics, footprints, dimensions, machine limits, and CAM
  values in this repository. Do not put them in a shared library.
- Use the exact pin pattern and orientation of the selected physical part. Do
  not replace a 2-by-3 module with a 1-by-6 connector or an assumed module.
- Record measured body size, pin pitch, pin diameter, acoustic or optical
  center, polarity, and keep-out data before final CAM. A seller photograph or
  nominal listing is not a measurement.
- If a required measurement is not available, mark the footprint and output as
  provisional. Do not release final CAM or a final case fit from it.

## Electrical design

- Keep only parts that have a stated electrical, safety, signal-integrity, or
  manufacturing purpose. Explain each support part in the design notes.
- Do not remove protection or a required driver only because a breadboard test
  worked without it. Check voltage, current, polarity, and device limits.
- Keep the buzzer power switch as a hard switch in the buzzer power wire.
- Do not change GPIO assignments without the required firmware configuration
  and wiring-document updates.

## Shared-library boundary

- Use the pinned `opendle-electronics` package for reusable KiCad export, CAM,
  G-code checks, and manifests. Keep product facts in `opendle-tools.toml` and
  the local hardware files.
- Put a generic host-tool fix in `../opendle-electronics`, under that
  repository's instructions and tests. Commit and push it there first. Then
  update ESPNoise to a full commit pin and refresh its lock file. Do not copy
  shared implementation into this repository.
- Put reusable embedded drivers or ESP32 helpers in the pinned
  `shared/opendle-esp32` library. Keep ESPNoise electrical policy and physical
  part data in this repository.

## Generate and check

After the schematic and PCB checks pass, use the pinned commands:

```sh
uv run --locked opendle-kicad export --config opendle-tools.toml
uv run --locked opendle-cnc build --config opendle-tools.toml
```

Review the DRC result, pin mapping, board extents, drill groups, tool paths,
output manifest, and changed checksums. For CNC work, measure the blank, use
the coupon, inspect both copper faces, and do a safe-Z dry run before the
panel. Do not state that generated G-code is safe only because software checks
pass.

Before a commit, run:

```sh
uv run --locked opendle-secrets check
```
