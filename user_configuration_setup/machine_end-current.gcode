;===== date: 20250109 =====================
M400 ; wait for buffer to clear
M140 S0 ;Turn-off bed
M106 S255 ;Cooling nozzle
M83
G92 E0 ; zero the extruder
G2 I1 J0 Z{max_layer_z+0.5} E-1 F3000 ; lower z a little
G90
{if max_layer_z > 50}G1 Z{min(max_layer_z+50, printable_height+0.5)} F20000{else}G1 Z100 F20000 {endif}; Move print head up 
M204 S5000
M400
M83
G1 X202 F20000
M400
G1 Y250 F20000
G1 Y264.5 F1200
M400
G92 E0
M104 S0 ;Turn-off hotend
M140 S0 ;Turn-off bed
M106 S0 ; turn off fan
M106 P2 S0 ; turn off remote part cooling fan
M106 P3 S0 ; turn off chamber cooling fan
M84 ;Disable all steppers
;M8212 ; Turn off light