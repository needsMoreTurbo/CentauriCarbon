# G29 Auto-Leveling — Full Procedure Documentation

## Purpose

G29 is the printer's built-in auto-leveling command. It performs two things:

1. **Establishes a consistent Z=0 reference** — the absolute height at which the nozzle is touching the bed surface, using the previously calibrated `position_endstop` value.
2. **Captures a bed mesh** — a 5×5 grid of Z height deviations across the bed surface, used to compensate for bed warp during printing.

Both outputs depend on each other. The mesh values are offsets *relative to Z=0*, so if Z=0 is wrong, the entire mesh is shifted. The procedure is designed to ensure both are captured in a known, repeatable thermal state.

---

## High-Level Step Summary

| Phase | What Happens |
|---|---|
| **1. Safety setup** | Software endstops disabled; all fans off |
| **2. Thermal conditioning** | Nozzle starts heating to 140°C; bed starts heating to 60°C |
| **3. Nozzle purge & clean** | Full `WIPE_NOZZLE` sequence: home → purge 250°C filament → cool → wipe on pad → Z home |
| **4. State reset** | Motion params restored; Z gcode offset cleared; calibrated Z reference restored from saved backup |
| **5. Z re-home** | Z axis homed using the now-correct calibrated reference — establishes Z=0 |
| **6. Thermal stabilization** | Wait for nozzle at 140°C and bed at 60°C before scanning |
| **7. Bed mesh scan** | 5×5 strain-gauge tap probe across bed surface |
| **8. Cleanup** | Fans off, heaters off, software endstops re-enabled |

---

## Detailed Step Documentation

### Phase 1 — Safety Setup

**`M211 S0`** — Disables software endstops.

During leveling the bed and toolhead must be able to move to positions that may be outside normal print limits (e.g. the probe descending past Z=0, or the bed rising above the normal print home). Software endstops would reject these moves. They are re-enabled at the end of the procedure.

> Note: `G29.1 P0` (disabling mesh compensation and Z offset) is only issued if `enable_z_home` is set to `true` in the strain gauge config. In the current configuration this is `0` (disabled), so this step is skipped.

---

### Phase 2 — Thermal Conditioning (Start)

**`M104 S140`** — Begin heating nozzle to 140°C (non-blocking).

**`M140 S60`** — Begin heating bed to 60°C (non-blocking).

**`M106 P1 S0` / `M106 P2 S0` / `M106 P3 S0`** — Turn off all three fan channels.

Fan-induced vibration can interfere with the strain gauge load cell readings during the wipe and probe phases. All fans are silenced before any strain gauge measurement occurs.

---

### Phase 3 — Nozzle Purge and Clean (`WIPE_NOZZLE`)

This is the most complex phase. It calls `wipe_nozzle()` internally, which runs `G28` followed by the full `extrude_feed_gcode` sequence from config. The purpose is to remove degraded or carbonised filament from the nozzle tip and leave it in a clean, controlled state before the mesh scan.

#### 3a — Home All Axes

**`G28`** — Homes X, Y, and Z.

- X and Y home using sensorless homing (TMC2209 stallguard virtual endstop).
- Z homes using the physical Z limit switch (pin PG8). The bed rises until the switch fires. The firmware assigns `position_endstop` to that position (a negative value representing how far below the switch Z=0 is).

At this point the toolhead is parked over the wipe/purge module area.

#### 3b — Move to Purge Position

**`M204 S5000`** — Set acceleration for purge moves.

**`G90`** — Absolute positioning.

**`M106 S0` / `M106 P2 S0`** — Fans off (belt and suspenders).

**`M83`** — Relative extrusion mode.

**`G1 X202 Y250 F20000`** — Move toolhead at high speed to the purge module area.

**`G1 Y264.5 F1200`** — Approach the purge module slowly so the nozzle aligns correctly.

#### 3c — Heat to Purge Temperature

**`M109 S250`** *(blocking)* — Heat nozzle to 250°C and wait.

250°C is used for purging because it fully melts any filament regardless of material, and produces a clean liquid extrusion that flushes the nozzle interior. The blocking wait ensures the purge starts only when the temperature is stable.

#### 3d — Purge Cycle (8 Repetitions)

**`G92 E0`** — Reset extruder position to 0.

**`M106 S255` / `M106 P2 S255`** — Part cooling fans on. Used here to cool extruded filament strings quickly so they don't re-attach to the nozzle.

The following block is repeated **8 times**:
```
G1 E13 F523    ; fast extrude 13mm
G1 E2 F150     ; slow extrude 2mm (improves tip formation)
M400           ; wait for move to complete
```
Total purged: ~120mm of filament. The slow final extrude on each pass produces a cleaner filament tip.

#### 3e — Retract and Cool

**`G1 E-2 F1800`** — Retract 2mm to prevent drip.

**`M109 S180`** *(blocking)* — Wait for nozzle to cool to 180°C.

At 180°C the filament is semi-solid — it won't drip but can still be wiped off cleanly. This is the optimal wipe temperature.

**`M104 S140`** — Begin cooling toward 140°C (non-blocking, continues during wipe).

**`G4 S4`** — Dwell 4 seconds to allow the filament tip to solidify slightly.

#### 3f — Wipe on Pad (M729)

**`M204 S15000`** — High acceleration for fast wipe motion.

**`M729`** — Executes the physical nozzle wipe. This command runs a hardcoded XY motion sequence that drags the nozzle tip across the wipe pad surface, removing the purged filament blob. The specific motion is a series of passes between X173–X202 at Y264.5.

**`M204 S5000`** — Reset acceleration.

**`G1 X128 Y254 F3000`** — Move toolhead away from wipe area to a neutral position.

#### 3g — First Z Home (Strain Gauge)

**`M140 S0`** — Bed heater off temporarily.

**`STRAINGAUGE_Z_HOME`** — Homes Z using the strain gauge system (first pass). This is a coarse Z home:

1. The bed rises toward the toolhead step by step.
2. The 4-channel HX711S strain gauge ADC continuously reads the load cells embedded in the toolhead mount.
3. When any cell detects a force change above the threshold (`g28_min_hold`), motion stops.
4. The exact Z position at the moment of contact is interpolated from the trigger timestamp and stepper position data.
5. The bed lifts back slightly.

This establishes a preliminary Z reference after the wipe.

#### 3h — Physical Strip Wipe

```
G91
G1 Z2 F600      ; lift 2mm
G90
G1 Y261.5 F9000 ; move to wipe strip Y position
G91
G1 Z-2.5 F600   ; lower into wipe strip contact height
M400
G90
```

The following wipe passes are run **5 times**:
```
G1 X140 F2000
G1 X110
```

This drags the nozzle across a rubber or silicone wipe strip at X110–X140, physically scraping off any remaining filament residue. The nozzle is pressed into the strip at Z=-2.5mm relative to current position.

```
G1 X128         ; return to center
M400
G91
G1 Z3 F600      ; lift clear of strip
M400
G90
G1 Y254 F9000   ; move away
G1 X128 F9000   ; center X
```

#### 3i — Second Z Home (Strain Gauge, Fine Pass)

**`STRAINGAUGE_Z_HOME`** — Second, more accurate Z home using the strain gauge. After the wipe the nozzle is clean and the tip geometry is more consistent, so this second home produces a more accurate Z reference than the first.

```
G91
G1 Z-0.5 F600   ; settle 0.5mm below home point
G90
M400
```

#### 3j — End of WIPE_NOZZLE Thermal State

**`M140 S60`** — Restart bed heating to 60°C.

**`M109 S140`** *(blocking)* — Wait for nozzle to reach 140°C.

**`M106 S0` / `M106 P2 S0`** — Fans off.

```
G91
G1 Z2 F600     ; final safety lift
G90
```

WIPE_NOZZLE completes. The nozzle is clean, at 140°C, and Z has been roughly homed via strain gauge.

---

### Phase 4 — State Reset

#### 4a — Re-assert Bed Temperature

**`M140 S60`** — Re-issue bed heat target. WIPE_NOZZLE sets and clears the bed during its sequence; this ensures it is definitely heating.

#### 4b — Reset Motion Parameters

**`RESET_PRINTER_PARAM`** resets two things:

- **`M900 P[value]`** — Restores pressure advance to the configured default. The previous print may have applied a different value.
- **`SET_VELOCITY_LIMIT VELOCITY=... ACCEL=... SQUARE_CORNER_VELOCITY=... ACCEL_TO_DECEL=...`** — Restores all motion limits to the values in `printer.cfg`. Ensures the mesh scan runs at controlled, repeatable speeds.

#### 4c — Wait for Nozzle

**`M109 S140`** *(blocking)* — Wait for nozzle to stabilize at 140°C. Ensures thermal state is settled before the Z reference is applied.

#### 4d — Clear Z Gcode Offset

**`SET_GCODE_OFFSET Z=0 MOVE=0 MOVE_SPEED=5.0`** — Clears any Z offset that was applied at the G-code layer during the previous print.

This is a critical step. Baby-stepping adjustments made during a prior print, or any offset set via `SET_GCODE_OFFSET`, accumulate in memory and persist between prints until explicitly cleared. If not cleared, the entire mesh scan will be offset by that residual value, producing a systematic Z=0 error.

#### 4e — Restore Calibrated Z Reference

**`M8233 S0 P1`** — Restores the calibrated Z position reference from its saved backup.

This command does the following with `S=0` (z_offset=0) and `P=1` (apply immediately):

```
probe/z_offset          ← 0
stepper_z/position_endstop ← (0 - 0) + position_endstop_extra
                           = position_endstop_extra
m_rails[2]->m_position_endstop ← position_endstop_extra + fix_z_offset
m_probe->m_z_offset     ← 0 + fix_z_offset
m_bed_mesh_probe->m_z_offset ← 0 + fix_z_offset
```

`position_endstop_extra` is the persistent backup of the last successfully calibrated Z offset (written by `CALIBRATE_Z_OFFSET`). By setting `position_endstop` equal to it, the firmware knows exactly what Z coordinate to assign when the Z endstop fires. This is the value that defines where Z=0 (nozzle touching bed) is, relative to the physical limit switch position.

The config is written to disk so the value survives a reboot.

---

### Phase 5 — Z Re-Home with Calibrated Reference

**`G28 Z`** — Homes the Z axis using the calibrated `position_endstop` now active in memory.

The bed rises until pin PG8 (the Z limit switch) fires. The firmware assigns `position_endstop` to that position — for example, -4.8mm. From this point, the coordinate system is correctly anchored: Z=0 means the nozzle is at bed level. The mesh scan will be taken relative to this reference.

This step is what actually *applies* the calibration set in Phase 4d/4e. Without it, the restored `position_endstop` value has no effect because the axis has not been homed against it.

---

### Phase 6 — Thermal Stabilization

**`M109 S140`** *(blocking)* — Ensure nozzle is at 140°C.

**`M190 S60`** *(blocking)* — Wait for bed to reach and stabilize at 60°C.

Both waits ensure the printer is in a thermally consistent state before probing. Bed thermal expansion affects mesh values, so measuring at a consistent temperature produces repeatable results across print sessions.

> Note: The built-in G29 always waits at 60°C regardless of print temperature. The user's custom start G-code uses the actual first-layer bed temperature here instead, which is physically more relevant but means mesh values may differ from G29's baseline.

---

### Phase 7 — Bed Mesh Scan

**`BED_MESH_CALIBRATE METHOD=fast`** — Probes a 5×5 grid of points across the bed surface.

Mesh bounds: X35–200, Y6–220 (from config defaults).

For each of the 25 probe points:

1. **Move to XY position** at the configured mesh speed (120mm/s default).
2. **`probe_by_step()`** — the strain gauge tap sequence:
   - The HX711S ADC begins continuous sampling across all 4 load cell channels.
   - The Z stepper descends step by step at `g29_speed` (3mm/s).
   - The firmware polls `m_hx711s->m_is_trigger` continuously.
   - When any load cell detects a force above the threshold, motion stops immediately.
   - `cal_min_z()` interpolates the exact Z at the moment of contact using the trigger timestamp versus stepper position data, correcting for the lag between physical contact and software response.
3. **Record Z position** — the interpolated tap height is stored as the mesh value for this point.
4. **Lift and continue** — the bed drops by `sample_retract_dist` (2mm) and moves to the next point.

At edge points (X<20, X>230, Y<20, Y>230) the sample count increases to `edge_samples` (2 by default) and uses tighter `edge_samples_tolerance` (0.01mm) because edge measurements are less stable.

The completed mesh is a table of Z deviation values. During printing, `MoveSplitter` applies these as real-time Z corrections using bicubic or Lagrange interpolation between probe points, with optional fade-out over the `fade_start` to `fade_end` height range.

---

### Phase 8 — Cleanup

After the mesh scan completes:

```gcode
G90
G1 X10 Y10 F4500   ; park toolhead at front-left corner
M106 S0            ; part cooling fan off
M104 S0            ; nozzle heater off
M140 S0            ; bed heater off
M211 S1            ; re-enable software endstops
```

> Note: `G29.1 P1` (re-enabling mesh and Z offset compensation) is only issued if `enable_z_home` is `true`. In the current config this is `0`, so it is skipped. In custom start G-code the mesh remains active from `BED_MESH_CALIBRATE` itself.

---

## Key Values (from `printer.cfg` and `Define_reference.h`)

| Parameter | Value | Source |
|---|---|---|
| Purge temperature | 250°C | `extrude_feed_gcode` |
| Wipe temperature | ~180°C (wait) → 140°C (target) | `extrude_feed_gcode` |
| Bed temperature (G29) | 60°C fixed | `extrude_feed_gcode` / `cmd_G29` |
| Mesh grid | 5×5 (25 points) | `bed_mesh` config |
| Mesh bounds | X: 35–200, Y: 6–220 | `bed_mesh` config |
| Probe speed | 3mm/s | `strain_gauge` / `bed_mesh_probe` |
| Samples per point | 2 (edge: 2) | `bed_mesh_probe` config |
| Sample tolerance | 0.01mm (edge: 0.01mm) | `bed_mesh_probe` config |
| Interpolation algorithm | Lagrange (default) | `bed_mesh` config |
| Fade distance | `fade_start` → `fade_end` | `bed_mesh` config |

---

## Why Z Offset Is Inconsistent Without This Full Sequence

The three steps most likely to cause Z offset drift between prints if omitted:

1. **`SET_GCODE_OFFSET Z=0`** — Without this, any baby-step or manual Z offset from a prior print persists. It adds directly to every subsequent print's first-layer height.

2. **`M8233 S0 P1`** — Without this, `position_endstop` may hold a modified value from a previous session. The mesh scan then references the wrong Z=0.

3. **`G28 Z`** (after M8233) — Without this, the restored `position_endstop` value is set in memory but never applied to the physical axis. The Z coordinate system remains anchored to the previous home, not the calibrated reference.
