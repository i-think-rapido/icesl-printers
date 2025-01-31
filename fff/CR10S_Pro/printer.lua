-- Creality CR10S pro
-- 30/07/2020

current_extruder = 0
last_extruder_selected = 0 -- counter to track the selected / prepared extruders

current_frate = 0
current_fan_speed = -1

extruder_e = {} -- table of extrusion values for each extruder
extruder_e_restart = {} -- table of extrusion values for each extruder for e reset (to comply with G92 E0)

for i = 0, extruder_count -1 do
  extruder_e[i] = 0.0
  extruder_e_restart[i] = 0.0
end

processing = false
skip_prime_retract = false

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

craftware = true -- allow the use of Craftware paths naming convention
debug = false -- output T commands for gcode debugging

--##################################################

function e_to_mm_cube(filament_diameter, e)
  local r = filament_diameter / 2
  return (math.pi * r^2 ) * e
end

function vol_to_mass(volume, density)
  return density * volume
end

function comment(text)
  output('; ' .. text)
end

function header()
  local h = file('header.gcode')

  h = h:gsub( '<TOOLTEMP>', extruder_temp_degree_c[extruders[0]] )
  h = h:gsub( '<HBPTEMP>', bed_temp_degree_c )

  if auto_bed_leveling == true and reload_bed_mesh == false then
    h = h:gsub( '<BEDLVL>', 'G29 ; auto bed leveling\nG0 F6200 X0 Y0 ; back to the origin to begin the purge')
  elseif reload_bed_mesh == true then
    h = h:gsub( '<BEDLVL>', 'M420 S1 ; enable bed leveling (was disabled y G28)\nM420 L ; load previous mesh / bed level' )
  else
    h = h:gsub( '<BEDLVL>', "G0 F6200 X0 Y0" )
  end

  output(h)

  -- additionnal informations for Klipper web API (Moonraker)
  -- if feedback from Moonraker is implemented in the choosen web UI (Mainsail, Fluidd, Octoprint), this info will be used for gcode previewing 
  output("; Additionnal informations for Mooraker API")
  output("; Generated by <" .. slicer_name .. " " .. slicer_version .. ">")
  output("; print_height_mm :\t" .. f(extent_z))
  output("; layer_count :\t" .. f(extent_z/z_layer_height_mm))
  output("; filament_type : \t" .. name_en)
  output("; filament_name : \t" .. name_en)
  output("; filament_used_mm : \t" .. f(filament_tot_length_mm[0]) )
  -- caution! density is in g/cm3, convertion to g/mm3 needed!
  output("; filament_used_g : \t" .. f(vol_to_mass(e_to_mm_cube(filament_diameter_mm[0], filament_tot_length_mm[0]), filament_density/1000)) )
  output("; estimated_print_time_s : \t" .. time_sec)
  output("") 

  current_frate = travel_speed_mm_per_sec * 60
  changed_frate = true
end

function footer()
  output(file('footer.gcode'))
end

function layer_start(zheight)
  local frate = 600
  comment('<layer ' .. layer_id ..'>')
  if not layer_spiralized then
    output('G0 F' .. frate .. ' Z' .. f(zheight))
  end
  current_frate = frate
  changed_frate = true
end

function layer_stop()
  extruder_e_restart[current_extruder] = extruder_e[current_extruder]
  output('G92 E0')
  comment('<layer ' .. layer_id ..'>')
  -- Klipper macro for DSLR timelapses
  --output('TAKE_SNAPSHOT')
end

function retract(extruder,e)
  if skip_prime_retract then
    output('; retract skipped')
    extruder_e[current_extruder] = e
    skip_prime_retract = false
    return e
  else
    output(';retract')
    local len   = filament_priming_mm[extruder]
    local speed = priming_mm_per_sec[extruder] * 60
    local e_value = e - len - extruder_e_restart[current_extruder]
    output('G1 F' .. speed .. ' E' .. ff(e_value))
    extruder_e[current_extruder] = e - len
    current_frate = speed
    changed_frate = true
    return e - len
  end
end

function prime(extruder,e)
  if skip_prime_retract then
    output('; prime skipped')
    extruder_e[current_extruder] = e
    skip_prime_retract = false
    return e
  else
    output(';prime')
    local len   = filament_priming_mm[extruder]
    local speed = priming_mm_per_sec[extruder] * 60
    local e_value = e + len - extruder_e_restart[current_extruder]
    output('G1 F' .. speed .. ' E' .. ff(e_value))
    extruder_e[current_extruder] = e + len
    current_frate = speed
    changed_frate = true
    return e + len
  end
end

function select_extruder(extruder)
  last_extruder_selected = last_extruder_selected + 1
  -- skip unnecessary prime/retract and ratios setup
  skip_prime_retract = true

  -- number_of_extruders is an IceSL internal Lua global variable which is used to know how many extruders will be used for a print job
  if last_extruder_selected == number_of_extruders then
    skip_prime_retract = false
    current_extruder = extruder
    if debug then output('T' .. extruder) end
  end
end

function swap_extruder(from,to,x,y,z)
  output('G92 E0')
  output('; Filament change')
  output('; Extruder change from vE' .. from .. ' to vE' .. to)
  output('M600') -- call filament swap
  if debug then output('T' .. to) end
  current_extruder = to
  output('G92 E'..extruder_e[current_extruder] - extruder_e_restart[current_extruder])
  skip_prime_retract = true
end

function move_xyz(x,y,z)
  if processing == true then
    output(';travel')
    processing = false
  end
  output('G0 F' .. f(current_frate) .. ' X' .. f(x) .. ' Y' .. f(y) .. ' Z' .. ff(z))
end

function move_xyze(x,y,z,e)
  extruder_e[current_extruder] = e
  local e_value = extruder_e[current_extruder] - extruder_e_restart[current_extruder]

  if processing == false then 
    processing = true
    p_type = craftware and 2 or 1 -- select path type
    if      path_is_perimeter then output(path_type[1][p_type])
    elseif  path_is_shell     then output(path_type[2][p_type])
    elseif  path_is_infill    then output(path_type[3][p_type])
    elseif  path_is_raft      then output(path_type[4][p_type])
    elseif  path_is_brim      then output(path_type[5][p_type])
    elseif  path_is_shield    then output(path_type[6][p_type])
    elseif  path_is_support   then output(path_type[7][p_type])
    elseif  path_is_tower     then output(path_type[8][p_type])
    end
  end

  output('G1 F' .. f(current_frate) .. ' X' .. f(x) .. ' Y' .. f(y) .. ' Z' .. ff(z) .. ' E' .. ff(e_value))
end

function move_e(e)
  extruder_e[current_extruder] = e
  local e_value = extruder_e[current_extruder] - extruder_e_restart[current_extruder]
  output('G1 F' .. f(current_frate) .. ' E' .. ff(e_value))
end

function set_feedrate(feedrate)
  current_frate = feedrate
end

function extruder_start()
end

function extruder_stop()
end

function progress(percent)
end

function set_extruder_temperature(extruder,temperature)
  output('M104 S' .. temperature)
end

function set_and_wait_extruder_temperature(extruder,temperature)
  output('M109 S' .. temperature)
end

function set_fan_speed(speed)
  if speed ~= current_fan_speed then
    output('M106 S'.. math.floor(255 * speed/100))
    current_fan_speed = speed
  end
end

function wait(sec,x,y,z)
  output("; WAIT --" .. sec .. "s remaining" )
  output("G0 F" .. travel_speed_mm_per_sec .. " X10 Y10")
  output("G4 S" .. sec .. "; wait for " .. sec .. "s")
  output("G0 F" .. travel_speed_mm_per_sec .. " X" .. f(x) .. " Y" .. f(y) .. " Z" .. ff(z))
end
