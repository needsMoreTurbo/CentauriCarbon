# G29 Full Sequence
*Source: firmware/core/klippy/extras/auto_leveling.cpp — cmd_G29() lines 532–635*

---

## Pre-conditions (UI calibration flow only)

Before G29 is queued, the UI always calls:

- **Platform selected (A):** `BED_MESH_SET_INDEX TYPE=standard INDEX=0`
- **Platform selected (B):** `BED_MESH_SET_INDEX TYPE=enhancement INDEX=0`

Each of these:
1. `SET_GCODE_OFFSET Z=0 MOVE=0` — clears live Z offset
2. `M8233 S{standard_z_offset} P1` — applies saved z_offset from config:
   `position_endstop = (0 - standard_z_offset) + position_endstop_extra + fix_z_offset`
3. Loads saved mesh profile from config

---

## Phase 1 — Reset & Preheat

| Step | Command | Notes |
|------|---------|-------|
| 1 | `G29.1 P0` | Zeros `position_endstop`, `probe.z_offset`, and `bed_mesh_probe.z_offset` in memory; clears active mesh. Only runs if `enable_z_home = true` in config. |
| 2 | `M211 S0` | Disable software endstops |
| 3 | `M104 S140` | Start nozzle preheat to 140°C (non-blocking) |
| 4 | `M140 S60` | Start bed preheat to 60°C (non-blocking) |
| 5 | `M106 P1/P2/P3 S0` | All fans off |

---

## Phase 2 — Nozzle Wipe (`WIPE_NOZZLE`)

*Source: wipe_nozzle() + extrude_feed_gcode from printer.cfg*

| Step | Command | Notes |
|------|---------|-------|
| 6 | `G28` | Home all axes |
| 7 | Move to X202 Y264.5 | Move to purge bucket position |
| 8 | `M109 S250` | Heat nozzle to 250°C and wait (blocking) |
| 9 | `M106 S255`, `M106 P2 S255` | Part cooling + aux fan on full to cool purge strings |
| 10 | Extrude 8× (`G1 E13 F523` + `G1 E2 F150`) | ~120mm total purge |
| 11 | `G1 E-2 F1800` | Retract |
| 12 | `M109 S180`, then `M104 S140` | Cool nozzle — wait to 180°C then set to 140°C non-blocking |
| 13 | `G4 S4` | 4-second dwell |
| 14 | `M729` | Wipe nozzle on silicone pad (scrub back and forth at X173–X202) |
| 15 | Move to X128 Y254 | Position for strain gauge probe |
| 16 | `M140 S0` | Bed heater off temporarily |
| 17 | `STRAINGAUGE_Z_HOME` | Probe nozzle Z position against bed (does not write config) |
| 18 | Nozzle wipe sequence | Lower Z to Y261.5, wipe back and forth X110–X140 × 4 passes |
| 19 | `STRAINGAUGE_Z_HOME` | Second probe (does not write config) |
| 20 | `G91 G1 Z-0.5 F600 G90` | Lower bed 0.5mm |
| 21 | `M140 S60` | Bed back to 60°C |
| 22 | `M109 S140` | Wait for nozzle to stabilize at 140°C (blocking) |
| 23 | `M106 S0`, `M106 P2 S0` | Fans off |
| 24 | `G91 G1 Z2 F600 G90` | Lift bed 2mm |

---

## Phase 3 — Z Reference Setup

| Step | Command | Notes |
|------|---------|-------|
| 25 | `M140 S60` | Re-assert bed at 60°C (WIPE_NOZZLE may have changed it) |
| 26 | `RESET_PRINTER_PARAM` | Reset internal printer parameters |
| 27 | `M109 S140` | Wait for nozzle at 140°C (blocking) |
| 28 | `SET_GCODE_OFFSET Z=0` | Clear any live Z offset |
| 29 | `position_endstop = position_endstop_extra` | Set in memory only — base hardware reference, no standard_z_offset applied |
| 30 | `M8233 S0 P1` | Apply z_offset=0: `position_endstop = position_endstop_extra + fix_z_offset` (in memory only) |
| 31 | Write config to disk | Persists current state — note: position_endstop in config is NOT changed here |
| 32 | `G28 Z` | Home Z axis — strain gauge triggers at nozzle-bed contact; assigns Z = current in-memory `position_endstop` |

---

## Phase 4 — Mesh Scan

| Step | Command | Notes |
|------|---------|-------|
| 33 | `M109 S140` | Wait for nozzle stable at 140°C |
| 34 | `M190 S60` | Wait for bed at 60°C (blocking) |
| 35 | `BED_MESH_CALIBRATE` (normal or fast) | Calls `BED_MESH_SET_INDEX INDEX=0` internally first (re-applies `standard_z_offset` from config), then probes all 121 points (11×11 grid, 20–246mm), saves mesh profile |

> **fast mode** (used when "Heated Bed Leveling" toggle is ON at print start): uses the previous mesh's edge points as a reference and probes only a subset, then blends with the prior mesh.  
> **normal mode** (used from UI calibration menu): probes all points fresh.

---

## Phase 5 — Cleanup & Restore

| Step | Command | Notes |
|------|---------|-------|
| 36 | `G90` | Absolute mode |
| 37 | `G1 X10 Y10 F4500` | Move toolhead to front-left corner |
| 38 | `M106 S0` | Part cooling fan off |
| 39 | `M104 S0` | Nozzle heater off |
| 40 | `M140 S0` | Bed heater off |
| 41 | `G29.1 P1` | Restores `position_endstop` from config (overwrites the in-memory value set in steps 29–30); restores `probe.z_offset` from config; loads saved mesh. Only runs if `enable_z_home = true`. |
| 42 | `M211 S1` | Re-enable software endstops |

---

## Notes

### CALIBRATE_Z_OFFSET (commented out)
Line 562 in cmd_G29 has `CALIBRATE_Z_OFFSET` commented out. When active, this command:
1. Temporarily zeros `position_endstop`
2. Does `G28 Z` to find the actual trigger position
3. Probes the bed with `PROBE`
4. Computes and **writes** the measured position to both `position_endstop` and `position_endstop_extra` in config

This is the only mechanism that would update `position_endstop_extra` to reflect actual nozzle geometry. Since it is commented out, `position_endstop_extra` is only ever set by factory calibration (`M8823`) or manually via terminal.

### standard_z_offset is never modified by G29
`standard_z_offset` is only written by `M8233` (user baby-step save via UI) or `M8823` (factory calibration). G29 reads and temporarily applies it but never changes it.

### BED_MESH_CALIBRATE re-applies standard_z_offset
Step 35 calls `BED_MESH_SET_INDEX INDEX=0` internally, which re-applies `standard_z_offset` from config via `M8233`. This means the mesh is probed with the full `standard_z_offset` applied — effectively overriding the zeroed state set in steps 29–30.
