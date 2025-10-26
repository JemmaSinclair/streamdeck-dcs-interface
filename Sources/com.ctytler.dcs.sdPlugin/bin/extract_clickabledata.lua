-- Calling script must define dcs_install_path and module_name as global variables.
-- Examples below:
        -- dcs_install_path = [[C:\Program Files\Eagle Dynamics\DCS World OpenBeta]]
        -- module_name = "A-10C"

-- Define global class type for clickabledata.
class_type = 
{
	NULL   = 0,
	BTN    = 1,
	TUMB   = 2,
	SNGBTN = 3,
	LEV    = 4
}

-- Mock out the get_option_value and get_aircraft_type functions that don't exist in this environment.
function get_aircraft_type()
	return module_name
end
function get_option_value(x)
	return nil
end

-- Some modules call this to read aircraft properties; provide a safe stub that returns nil so
-- modules can fall back to defaults when running in the extractor environment.
function get_aircraft_property_or_nil(name)
	return nil
end

-- Protect against relative path "dofile" calls by inspecting paths before running.
-- All should use the configured "LockOn_Options.script_path" variable.
call_dofile = dofile
function inspect_and_dofile(path)
	local is_absolute_path = (string.match(path, dcs_install_path))
	if is_absolute_path then
		call_dofile(path)
	else

		call_dofile(dcs_install_path .. path)
	end
end
--Overwrite function so any dofile function calls by module scripts will go through inspect first.
dofile = inspect_and_dofile


function len(table)
	local count = 0
    for _ in pairs(table) do
	    count = count + 1
	end
	return count
end

function file_exists(filename)
    local file = io.open(filename, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function get_device_name(device_id)
    device_name = ""
	for device,id in pairs(devices) do
		if (id == device_id) then
			if (device ~= nil) then
				device_name = device
			end
		end
    end
    return device_name
end

function get_class_enum_label(class)
	if class == 0 then
		return "NULL"
	elseif class == 1 then
		return "BTN"
	elseif class == 2 then
		return "TUMB"
	elseif class == 3 then
		return "SNGBTN"
	elseif class == 4 then
		return "LEV"
	else
		return ""
	end
end

function get_index_value(table, index)
	if (table ~= nil) then
        value = table[index]
        if (value ~= nil) then
            return value
        end
	end
	return ""
end

function collect_element_attributes(elements)
	collected_element_attributes = {}
	local count = 0
	for element_id,_ in pairs(elements) do
		local element_name = element_id
		local hint = elements[element_id].hint
		local classes = elements[element_id].class
		local args = elements[element_id].arg
		local arg_values = elements[element_id].arg_value
		local arg_lims = elements[element_id].arg_lim
		local device_id = elements[element_id].device
		local device_name = get_device_name(device_id)
		local command_ids = elements[element_id].action
		
		-- Iterate through classes
		for idx,class in pairs(classes) do
			local class_name = get_class_enum_label(class)
			local command_id = get_index_value(command_ids,idx)
			local arg = get_index_value(args,idx)
			local arg_value = get_index_value(arg_values,idx)
			local arg_lim = get_index_value(arg_lims,idx)
			local arg_lim1 = ""
			local arg_lim2 = ""
			if (arg_lim ~= nil) then
				if (type(arg_lim) == "table") then
					arg_lim1 = arg_lim[1]
					arg_lim2 = arg_lim[2]
					-- Repeat this for further nesting (found in JF-17)
					if (type(arg_lim1) == "table") then
						arg_lim = arg_lim1
						arg_lim1 = arg_lim[1]
						arg_lim2 = arg_lim[2]
					end
				elseif (type(arg_lim) == "number") then
					arg_lim1 = arg_lim
				end
			end
            if (device_id == nil) then
                device_id = "" 
            end
			count = count + 1
			collected_element_attributes[count] = string.format('%s(%s),%s,%s,%s,%s,%s,%s,%s,%s',
					device_name, device_id, command_id, element_name, class_name, arg, arg_value, arg_lim1, arg_lim2, hint)
		end
	end
	return collected_element_attributes
end

function load_module(module_name)
	LockOn_Options = {}

	-- Allow module_name to include a variant suffix separated by '|', e.g. "Mirage-F1|Mirage-F1\Mirage-F1BE".
	local variant_subpath = nil
	local base_module = module_name
	-- Split module_name on literal '|' into base_module and variant_subpath
	local sep = string.find(module_name, "|", 1, true)
	if sep then
		base_module = string.sub(module_name, 1, sep - 1)
		variant_subpath = string.sub(module_name, sep + 1)
	end

	-- Specialty case handling for odd multi-version modules.
	if string.match(base_module, "C-101") then
		LockOn_Options.script_path = dcs_install_path..[[\Mods\aircraft\C-101\Cockpit\]]..base_module..[[\]]
	elseif string.match(base_module, "L-39") then
		L_39ZA = string.match(base_module, "L-39ZA")
		LockOn_Options.script_path = dcs_install_path..[[\Mods\aircraft\L-39C\Cockpit\]]
		dofile(LockOn_Options.script_path.."devices.lua")
	else
		LockOn_Options.script_path = dcs_install_path..[[\Mods\aircraft\]]..base_module..[[\Cockpit\]]
	end
	

	-- Try several locations for clickabledata.lua: directly in Cockpit, in Cockpit/Scripts,
	-- and in subdirectories (up to 2 levels deep) to support modules like Mirage-F1 which
	-- place clickabledata in variant subfolders.
	local tried_paths = {}
	local function try_load(path)
		tried_paths[#tried_paths + 1] = path
		local f = loadfile(path)
		if f ~= nil then
			LockOn_Options.script_path = string.sub(path, 1, #path - string.len("clickabledata.lua"))
			return f
		end
		return nil
	end

	-- 1) Directly under Cockpit\
	-- If a variant subpath was provided (module_name contained '|'), try the variant first.
	if variant_subpath ~= nil then
		-- Try variant clickabledata direct and under Scripts
		script_to_run = try_load(LockOn_Options.script_path .. variant_subpath .. [[\]] .. "clickabledata.lua")
		if script_to_run == nil then
			script_to_run = try_load(LockOn_Options.script_path .. variant_subpath .. [[\Scripts\]] .. "clickabledata.lua")
		end
		-- Also try one level deeper inside the variant subpath
		if script_to_run == nil then
			local function list_dir(path)
				local entries = {}
				local p = io.popen('dir "'..path..'" /b')
				if p then
					for name in p:lines() do
						if name ~= '.' and name ~= '..' then
							entries[#entries + 1] = name
						end
					end
					p:close()
				end
				return entries
			end
			local base = LockOn_Options.script_path .. variant_subpath .. [[\]]
			local subs = list_dir(base)
			for _, sub in ipairs(subs) do
				local subpath = base .. sub .. [[\]]
				script_to_run = try_load(subpath .. "clickabledata.lua")
				if script_to_run ~= nil then break end
				script_to_run = try_load(subpath .. [[Scripts\]] .. "clickabledata.lua")
				if script_to_run ~= nil then break end
			end
		end
	end

	-- 1) Directly under Cockpit\
	if script_to_run == nil then
		script_to_run = try_load(LockOn_Options.script_path.."clickabledata.lua")
	end

	-- 2) Under Cockpit\Scripts\
	if script_to_run == nil then
		script_to_run = try_load(LockOn_Options.script_path..[[Scripts\]].."clickabledata.lua")
	end

	-- 3) Search immediate subdirectories and their subdirectories (depth 2)
	if script_to_run == nil then
		-- Helper to iterate directory entries using Windows 'dir /b'
		local function list_dir(path)
			local entries = {}
			local p = io.popen('dir "'..path..'" /b')
			if p then
				for name in p:lines() do
					-- skip '.' and '..' entries
					if name ~= '.' and name ~= '..' then
						entries[#entries + 1] = name
					end
				end
				p:close()
			end
			return entries
		end

		local subs = list_dir(LockOn_Options.script_path)
		for _, sub in ipairs(subs) do
			local subpath = LockOn_Options.script_path .. sub .. [[\]]
			-- try clickabledata in first-level subdir
			script_to_run = try_load(subpath .. "clickabledata.lua")
			if script_to_run ~= nil then break end
			-- try clickabledata in Scripts under first-level subdir
			script_to_run = try_load(subpath .. [[Scripts\]] .. "clickabledata.lua")
			if script_to_run ~= nil then break end
			-- list second-level subdirs and try there
			local subs2 = list_dir(subpath)
			for _, sub2 in ipairs(subs2) do
				local subpath2 = subpath .. sub2 .. [[\]]
				script_to_run = try_load(subpath2 .. "clickabledata.lua")
				if script_to_run ~= nil then break end
				-- also try Scripts in second-level
				script_to_run = try_load(subpath2 .. [[Scripts\]] .. "clickabledata.lua")
				if script_to_run ~= nil then break end
			end
			if script_to_run ~= nil then break end
		end
	end

	if script_to_run == nil then
		local msg = "Could not find clickabledata.lua from "..LockOn_Options.script_path..". Tried paths:\n"
		for _, p in ipairs(tried_paths) do
			msg = msg .. "  " .. p .. "\n"
		end
		error(msg, 2)
	end

	-- Execute the discovered clickabledata script
	-- Ensure common globals expected by module shared files exist in this environment.
	-- Some modules expect _LAST_CLICK_SOUND_ to be defined (used by Common/sounds_common.lua).
	if _G["_LAST_CLICK_SOUND_"] == nil then
		_LAST_CLICK_SOUND_ = 0
	end

	script_to_run()
	
	element_list = collect_element_attributes(elements)
	return element_list
end

list = load_module(module_name)
return table.unpack(list)