SET_GCODE_OFFSET Z=0.100 MOVE=0 ;Z-offset correction for thermal expansion

; Filament gcode
{if activate_air_filtration[current_extruder] && support_air_filtration}
M106 P3 S{during_print_exhaust_fan_speed_num[current_extruder]} 
{endif}