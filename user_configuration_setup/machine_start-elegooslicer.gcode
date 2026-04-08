;;===== date: 20251011 =====================
;printer_model:[printer_model]
;initial_filament:{filament_type[initial_extruder]}
;curr_bed_type:{curr_bed_type}
;bed_level_temp:[bed_temperature_initial_layer_single]
M400 ; wait for buffer to clear
M220 S100 ;Set the feed speed to 100%
M221 S100 ;Set the flow rate to 100%
M104 S140
M140 S[bed_temperature_initial_layer_single]
G90
G28 ;home
M729 ;Clean Nozzle
M190 S[bed_temperature_initial_layer_single]


;=============turn on fans to prevent PLA jamming=================
{if filament_type[initial_no_support_extruder]=="PLA"}
    {if (bed_temperature[initial_no_support_extruder] >50)||(bed_temperature_initial_layer[initial_no_support_extruder] >50)}
    M106 P3 S255
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


G1 X{print_bed_max[0]*0.5} Y-1.2 F20000
G1 Z0.3 F900
M109 S[nozzle_temperature_initial_layer]
M83
G92 E0 ;Reset Extruder
G1 F{min(6000, max(900, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))} 
G1 X-1.2 E10.156 ;Draw the first line
G1 Y98.8 E7.934
G1 X-0.5 Y100 E0.1
G1 Y-0.3 E7.934
G1 X{print_bed_max[0]*0.5-50} E6.284
G1 F{0.2*min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))} 
G1 X{print_bed_max[0]*0.5-30} E2
G1 F{min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))} 
G1 X{print_bed_max[0]*0.5-10} E2
G1 F{0.2*min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))} 
G1 X{print_bed_max[0]*0.5+10} E2
G1 F{min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))} 
G1 X{print_bed_max[0]*0.5+30} E2
G1 F{min(12000, max(1200, filament_max_volumetric_speed[initial_no_support_extruder]/0.5/0.3*60))} 
G1 X{print_bed_max[0]*0.5+50} E2
;End PA test.


G3 I-1 J0 Z0.6 F1200.0 ;Move to side a little
G1 F20000
G92 E0 ;Reset Extruder
;LAYER_COUNT:[total_layer_count]
;LAYER:0