-- BCN3D Sigma R19 profile
-- Bedell Pierre 09/07/2020

current_extruder = 0
current_z = 0.0
current_frate = 0
changed_frate = false
current_fan_speed = -1

extruder_e = {} -- table of extrusion values for each extruder
extruder_e_reset = {} -- table of extrusion values for each extruder for e reset (to comply with G92 E0)
extruder_e_swap = {} -- table of extrusion values for each extruder before to keep track of e at an extruder swap
extruder_stored = {} -- table to store the state of the extruders after the purge procedure (to prevent additionnal retracts)

for i = 0, extruder_count -1 do
  extruder_e[i] = 0.0
  extruder_e_reset[i] = 0.0
  extruder_e_swap[i] = 0.0
  extruder_stored[i] = false
end

purge_string = ''
n_selected_extruder = 0 -- counter to track the selected / prepared extruders

extruder_changed = false
processing = false

path_type = {
--{ 'default',    'Craftware'}
  { ';perimeter',  ';segType:Perimeter' },
  { ';shell',      ';segType:HShell' },
  { ';infill',     ';segType:Infill' },
  { ';raft',       ';segType:Raft' },
  { ';brim',       ';segType:Skirt' },
  { ';shield',     ';segType:Pillar' },
  { ';support',    ';segType:Support' },
  { ';tower',      ';segType:Pillar'}
}

craftware_debug = true

--##################################################

function comment(text)
  output('; ' .. text)
end

function round(number, decimals)
  local power = 10^decimals
  return math.floor(number * power) / power
end

function header()
  -- workaround for materials name using "custom" profile
  if name_en == nil then 
    if extruder_temp_degree_c[0] >= 170 and extruder_temp_degree_c[0] < 230 then 
      name_en = 'PLA' -- PLA
    elseif extruder_temp_degree_c[0] >= 230 and extruder_temp_degree_c[0] <= 270 then
      name_en = 'ABS' -- ABS
    else
      name_en = 'PLA' -- PLA
    end
  end

  local filament_total_length = 0
  local extruders_info_string = ''
  local materials_info_string = ''
  local tool_temp_string = ''
  -- Fetching print job informations
  if filament_tot_length_mm[0] > 0 then 
    filament_total_length = filament_total_length + filament_tot_length_mm[0]
    extruders_info_string = extruders_info_string .. ' T0 ' .. round(nozzle_diameter_mm_0,2)
    materials_info_string = materials_info_string .. ' T0 ' .. name_en
    tool_temp_string = tool_temp_string .. 'M104 T0 S' .. extruder_temp_degree_c[0] .. '\nM109 T0 S' .. extruder_temp_degree_c[0] .. ' ;Fixed T0 temperature\n'
  end
  if filament_tot_length_mm[1] > 0 or (mirror_mode == true or duplication_mode == true) then 
    filament_total_length = filament_total_length + filament_tot_length_mm[1]
    extruders_info_string = extruders_info_string .. ' T1 ' .. round(nozzle_diameter_mm_1,2)
    materials_info_string = materials_info_string .. ' T1 ' .. name_en
    tool_temp_string = tool_temp_string .. 'M104 T1 S' .. extruder_temp_degree_c[1] .. '\nM109 T1 S' .. extruder_temp_degree_c[1] .. ' ;Fixed T1 temperature\n'
  end

  output(';FLAVOR:Marlin')
  output(';TIME:' .. time_sec)
  output(';Filament used: ' .. round(filament_total_length / 1000, 5) .. 'm')
  output(';Layer height: ' .. round(z_layer_height_mm,2))
  output(';Extruders used:' .. extruders_info_string)
  output(';Materials used:' .. materials_info_string)
  --output(';BCN3D_FIXES') -- doesn't seems to be mandatory
  output(';Generated with ' .. slicer_name .. ' ' .. slicer_version)

  output('M141 S' .. 50 .. ' ;chamber temperature')
  --output('T0')
  output('M190 S' .. bed_temp_degree_c .. ' ;bed temperature')
  output(tool_temp_string)

  local h = file('header.gcode')
  if mirror_mode == true then
    h = h:gsub('<PRINT_MODE>', 'M605 S6      ;enable mirror mode\n')
  elseif duplication_mode == true then
    h = h:gsub('<PRINT_MODE>', 'M605 S5      ;enable duplication mode\n')
  else
    h = h:gsub('<PRINT_MODE>', '')
  end
  h = h:gsub('<ACC>', default_acc)
  h = h:gsub('<JERK>', 'X' .. default_jerk .. ' Y' .. default_jerk)
  h = h:gsub('<BUCKET_PURGE>', purge_string)
  output(h)
  current_frate = travel_speed_mm_per_sec * 60
  changed_frate = true
end

function footer()
  local f = file('footer.gcode')
  f = h:gsub('<ACC>', default_acc)
  f = h:gsub('<JERK>', 'X' .. default_jerk .. ' Y' .. default_jerk)
  output(f)
end

function retract(extruder,e)
  local len   = filament_priming_mm[extruder]
  local speed = priming_mm_per_sec[extruder] * 60
  local e_value = e - extruder_e_swap[current_extruder]
  if extruder_stored[extruder] then 
    comment('retract on extruder ' .. extruder .. ' skipped')
  else
    comment('retract')    
    output('G1 F' .. speed .. ' E' .. ff(e_value - extruder_e_reset[current_extruder] - len))
    extruder_e[current_extruder] = e_value - len
    current_frate = speed
    changed_frate = true
  end  
  return e - len
end

function prime(extruder,e)
  local len   = filament_priming_mm[extruder]
  local speed = priming_mm_per_sec[extruder] * 60
  local e_value = e - extruder_e_swap[current_extruder]
  if extruder_stored[extruder] then 
    comment('prime on extruder ' .. extruder .. ' skipped')
  else
    comment('prime')    
    output('G1 F' .. speed .. ' E' .. ff(e_value - extruder_e_reset[current_extruder] + len))
    extruder_e[current_extruder] = e_value + len
    current_frate = speed
    changed_frate = true
  end  
  return e + len
end

function layer_start(zheight)
  output('; <layer ' .. layer_id .. '>')
  local frate = 100
  if layer_id == 0 then
    frate = 600
    output('G0 F' .. frate .. ' Z' .. f(zheight))
  else
    output('G0 F' .. frate ..' Z' .. f(zheight))
  end
  current_z = zheight
  current_frate = frate
  changed_frate = true
end

function layer_stop()
  extruder_e_reset[current_extruder] = extruder_e[current_extruder]
  output('G92 E0')
  output('; </layer>')
end

-- this is called once for each used extruder at startup
function select_extruder(extruder)
  extruder_side = ''
  if extruder == 0 then 
    extruder_side = 'left'
  elseif extruder == 1 then 
    extruder_side = 'right'
  end

  n_selected_extruder = n_selected_extruder + 1

  purge_string = purge_string .. "\nT" .. extruder .. "           ;switch to the " .. extruder_side ..  " extruder"
  purge_string = purge_string .. "\nG92 E0       ;zero the extruded length"
  purge_string = purge_string .. "\nG1 E10 F35   ;extrude 10mm of filament"
  purge_string = purge_string .. "\nG92 E0       ;zero the extruded length"

  -- number_of_extruders is an IceSL internal Lua global variable 
  -- which is used to know how many extruders will be used for a print job
  if n_selected_extruder == number_of_extruders then
    purge_string = purge_string .. "\nG4 S2        ;stabilize hotend's pressure"
    --purge_string = purge_string .. "\nG1 E-0.5\n"
    extruder_stored[extruder] = false
  else
    purge_string = purge_string .. "\nG1 E-" .. filament_priming_mm[extruder] .. " F1000 ;store filament"
    purge_string = purge_string .. "\nG92 E0       ;zero the extruded length\n"
    extruder_stored[extruder] = true
  end

  current_extruder = extruder
  current_frate = travel_speed_mm_per_sec * 60
  changed_frate = true
end

function swap_extruder(from,to,x,y,z)
  output('\n;swap_extruder')
  extruder_e_swap[from] = extruder_e_swap[from] + extruder_e[from] - extruder_e_reset[from]

  -- swap extruder
  output('T' .. to)
  output('G91')
  output('G1 F12000 Z2')
  output('G90')
  output('G92 E0')
  output('G1 E'.. filament_priming_mm[to] .. ' F1000 ;release stored filament')
  output('G1 E1.0 F100 ;default purge')
  output('G92 E0')
  output('G4 S3')
  output('G1 E-'.. filament_priming_mm[to] .. ' F1000\n')

  extruder_stored[to] = false

  current_extruder = to
  extruder_changed = true
  current_frate = travel_speed_mm_per_sec * 60
  changed_frate = true
end

function move_xyz(x,y,z)
  if processing == true then
    processing = false
    output(';travel')
    output('M204 S' .. travel_acc .. '\nM205 X' .. travel_jerk .. ' Y' .. travel_jerk)
  end

  if z ~= current_z or extruder_changed == true then
    if changed_frate == true then
      output('G0 F' .. current_frate .. ' X' .. f(x) .. ' Y' .. f(y) .. ' Z' .. f(z))
      changed_frate = false
    else
      output('G0 X' .. f(x) .. ' Y' .. f(y) .. ' Z' .. f(z))
    end
    extruder_changed = false
    current_z = z
  else
    if changed_frate == true then 
      output('G0 F' .. current_frate .. ' X' .. f(x) .. ' Y' .. f(y))
      changed_frate = false
    else
      output('G0 X' .. f(x) .. ' Y' .. f(y))
    end
  end
end

function move_xyze(x,y,z,e)
  extruder_e[current_extruder] = e - extruder_e_swap[current_extruder]

  local e_value = extruder_e[current_extruder] - extruder_e_reset[current_extruder]

  if processing == false then 
    processing = true
    local p_type = 1 -- default paths naming
    if craftware_debug then p_type = 2 end
    if      path_is_perimeter then output(path_type[1][p_type]) output('M204 S' .. perimeter_acc .. '\nM205 X' .. perimeter_jerk .. ' Y' .. perimeter_jerk)
    elseif  path_is_shell     then output(path_type[2][p_type]) output('M204 S' .. perimeter_acc .. '\nM205 X' .. perimeter_jerk .. ' Y' .. perimeter_jerk)
    elseif  path_is_infill    then output(path_type[3][p_type]) output('M204 S' .. infill_acc .. '\nM205 X' .. infill_jerk .. ' Y' .. infill_jerk)
    elseif  path_is_raft      then output(path_type[4][p_type]) output('M204 S' .. default_acc .. '\nM205 X' .. default_jerk .. ' Y' .. default_jerk)
    elseif  path_is_brim      then output(path_type[5][p_type]) output('M204 S' .. default_acc .. '\nM205 X' .. default_jerk .. ' Y' .. default_jerk)
    elseif  path_is_shield    then output(path_type[6][p_type]) output('M204 S' .. default_acc .. '\nM205 X' .. default_jerk .. ' Y' .. default_jerk)
    elseif  path_is_support   then output(path_type[7][p_type]) output('M204 S' .. default_acc .. '\nM205 X' .. default_jerk .. ' Y' .. default_jerk)
    elseif  path_is_tower     then output(path_type[8][p_type]) output('M204 S' .. default_acc .. '\nM205 X' .. default_jerk .. ' Y' .. default_jerk)
    end
  end

  if z == current_z then
    if changed_frate == true then 
      output('G1 F' .. current_frate .. ' X' .. f(x) .. ' Y' .. f(y) .. ' E' .. ff(e_value))
      changed_frate = false
    else
      output('G1 X' .. f(x) .. ' Y' .. f(y) .. ' E' .. ff(e_value))
    end
  else
    if changed_frate == true then
      output('G1 F' .. current_frate .. ' X' .. f(x) .. ' Y' .. f(y) .. ' Z' .. f(z) .. ' E' .. ff(e_value))
      changed_frate = false
    else
      output('G1 X' .. f(x) .. ' Y' .. f(y) .. ' Z' .. f(z) .. ' E' .. ff(e_value))
    end
    current_z = z
  end
end

function move_e(e)
  extruder_e[current_extruder] = e - extruder_e_swap[current_extruder]

  local e_value =  extruder_e[current_extruder] - extruder_e_reset[current_extruder]

  if changed_frate == true then 
    output('G1 F' .. current_frate .. ' E' .. ff(e_value))
    changed_frate = false
  else
    output('G1 E' .. ff(e_value))
  end
end

function set_feedrate(feedrate)
  if feedrate ~= current_frate then
    current_frate = feedrate
    changed_frate = true
  end
end

function extruder_start()
end

function extruder_stop()
end

function progress(percent)
end

function set_extruder_temperature(extruder,temperature)
  output('M104 T' .. extruder .. ' S' .. f(temperature))
end

function set_and_wait_extruder_temperature(extruder,temperature)
  output('M109 T' .. extruder .. ' S' .. f(temperature))
end

function set_fan_speed(speed)
  if speed ~= current_fan_speed then
    output('M106 S'.. math.floor(255 * speed/100))
    current_fan_speed = speed
  end
end
