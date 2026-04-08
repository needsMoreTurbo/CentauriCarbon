;;===== date: 20240520 =====================
;printer_model:[printer_model]
;initial_filament:{filament_type[initial_extruder]}
;curr_bed_type:{curr_bed_type}
M8213 ; Turn on light
M400 ; wait for buffer to clear
M220 S100 ;Set the feed speed to 100%
M221 S100 ;Set the flow rate to 100%
M104 S140 ;Preheat nozzle to prevent ooze
G90

{if chamber_temperature[0] > 0}
;=============chamber heat soak (high-temp materials)============
G28 ;home (parks toolhead over purge bucket)
M729 ;Clean Nozzle
M190 S[bed_temperature_initial_layer_single] ;Heat bed to print temp and wait
M400
M106 P2 S128 ;Aux fan on at 50% to recirculate
M400
G4 P1000 ;Dwell 1s to let fan spin up
M140 S110 ;Set bed to 110°C — do not wait
G1 Z10 F900 ;Lower bed to Z10 for safe toolhead move
M400
G1 X128 Y50 F12000 ;Center X, 50mm from front
M400
G1 Z2 F900 ;Raise bed to 2mm from nozzle for max heat transfer
M400
M106 S204 ;Part cooling fan on at 80%
M400
G4 P1000 ;Dwell 1s to let fan spin up
TEMPERATURE_WAIT SENSOR=box MINIMUM={chamber_temperature[0]} MAXIMUM=90 ;Wait for chamber target
M400
;=============transition to print temp===============================
M190 S[bed_temperature_initial_layer_single] ;Set bed to print temp and wait (fans help cool from 110)
M400
M106 P2 S0 ;Aux fan off
M106 S0 ;Part cooling fan off
M400
{endif}

;=============auto-level (replicates built-in G29)=================
M211 S0 ;Disable software endstops — G29 does this before any leveling
M140 S[bed_temperature_initial_layer_single] ;Bed to print temp (G29 uses fixed 60°C)
M106 P1 S0 ;All fans off before wipe — G29 explicitly clears these
M106 P2 S0
M106 P3 S0
WIPE_NOZZLE ;Home, full purge, and clean nozzle (mirrors G29's wipe_nozzle() call)
M190 S[bed_temperature_initial_layer_single] ;Re-assert bed temp — WIPE_NOZZLE hardcodes M140 S60 at end
M400
RESET_PRINTER_PARAM ;Reset printer parameters — G29 calls this after wipe
M109 S140 ;Wait for nozzle to stabilize at 140°C (blocking) — G29 does this
;SET_GCODE_OFFSET Z=0 MOVE=0 MOVE_SPEED=5.0 ;DISABLED: redundant — firmware calls BED_MESH_SET_INDEX before gcode starts (which calls SET_GCODE_OFFSET Z=0), and BED_MESH_CALIBRATE calls it again internally
;M8233 S0 P1 ;DISABLED: silently blocked when executing from SD card (printer_para.cpp checks is_cmd_from_sd() and returns immediately) — has no effect here
G28 Z ;Re-home Z with calibrated position_endstop now applied — critical for consistent Z=0
M190 S[bed_temperature_initial_layer_single] ;Wait for bed at print temp (G29 waits at 60°C)
M400
M8210 S[bed_temperature_initial_layer_single] ;Set bed mesh temp to match print temp
BED_MESH_CALIBRATE METHOD=fast ;Run mesh scan
M211 S1 ;Re-enable software endstops — G29 does this after mesh completes

;=============turn on fans to prevent PLA jamming=================
{if filament_type[initial_no_support_extruder]=="PLA"}
    {if (bed_temperature[initial_no_support_extruder] >50)||(bed_temperature_initial_layer[initial_no_support_extruder] >50)}
    M106 P3 S180
    {elsif (bed_temperature[initial_no_support_extruder] >45)||(bed_temperature_initial_layer[initial_no_support_extruder] >45)}
    M106 P3 S180
    {endif};Prevent PLA from jamming
{endif}

;enable_pressure_advance:{enable_pressure_advance[initial_extruder]}
;This value is called if pressure advance is enabled
{if enable_pressure_advance[initial_extruder] == "true"}
SET_PRESSURE_ADVANCE ADVANCE=[pressure_advance] ;
M400
{endif}
M204 S{min(20000,max(1000,outer_wall_acceleration))} ;Call exterior wall print acceleration


G1 X{print_bed_max[0]*0.5+40+50} Y-1.2 F20000
G1 Z0.3 F900
M109 S[nozzle_temperature_initial_layer]
M83
G92 E0 ;Reset Extruder
G1 F{min(6000, max(900, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))}
G1 X60 E12 ;Draw the first line
G1 Y-0.3
G1 X{print_bed_max[0]*0.5+40-50} E4.284
G1 F{0.2*min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))}
G1 X{print_bed_max[0]*0.5+40-30} E2
G1 F{min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))}
G1 X{print_bed_max[0]*0.5+40-10} E2
G1 F{0.2*min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))}
G1 X{print_bed_max[0]*0.5+40+10} E2
G1 F{min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))}
G1 X{print_bed_max[0]*0.5+40+30} E2
G1 F{min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))}
G1 X{print_bed_max[0]*0.5+40+50} E2
;End PA test.


G3 I-1 J0 Z0.6 F1200.0 ;Move to side a little
G1 F20000
G92 E0 ;Reset Extruder
;LAYER_COUNT:[total_layer_count]
;LAYER:0
SET_PRINT_STATS_INFO TOTAL_LAYER=[total_layer_count]
