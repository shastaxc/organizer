--Copyright (c) 2021-2022, Shasta
-- All rights reserved.

-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:

--     * Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--     * Neither the name of WSBinder nor the
--       names of its contributors may be used to endorse or promote products
--       derived from this software without specific prior written permission.

-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
-- LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

res = include('resources')

--Debug
debug_gear_list = false --Dump the generated gear set
debug_move_list = false --Dump the unassigned gear list
debug_found_list = false --Dump the list of found equipment from scanning wardrobes

local org = {}
register_unhandled_command(function(...)
    local cmds = {...}
    for _,v in ipairs(cmds) do
        if S{'reorganizer','reorganize','reorg'}:contains(v:lower()) then
            org.export_set()
            return true
        end
    end
    return false
end)

-- Make lists which will tell Reorganizer where gear should go.
-- If an item is already in wardrobe, it will be left there.
-- If there are items needed that aren't in wardrobes, they will be assigned to empty space in wardrobes.
-- If there are still items that need assignment, they will be assigned to wardrobes until they hit max capacity, and
-- any items currently in that wardrobe that aren't part of needed items for the job will attempt to move to dump bags.
-- These item assignments are saved to file for Reorganizer addon to use, and then reorganizer command is called to do so.
function org.export_set()
    if not sets then
        windower.add_to_chat(123,'Reorganizer Library: Cannot export your sets for collection because the table is nil.')
        return
    elseif not windower.dir_exists(windower.windower_path..'addons/reorganizer/') then
        windower.add_to_chat(123,'Reorganizer Library: The Reorganizer addon is not installed. Activate it in the launcher.')
        return
    end
    
    -- Make a table filled with the items from the sets table.
    local item_list = org.unpack_names({},'L1',sets,{})
    
    local trans_item_list = org.identify_items(item_list)
    
    for i,v in pairs(trans_item_list) do
        trans_item_list[i] = org.simplify_entry(v)
    end

    if trans_item_list:length() == 0 then
        windower.add_to_chat(123,'Reorganizer Library: Your sets table is empty.')
        return
    end
    
    local flattab = T{}
    for name,tab in pairs(trans_item_list) do
        for _,info in ipairs(tab) do
            flattab:append({id=tab.id,name=tab.name,log_name=tab.log_name,augments=info.augments,count=info.count})
        end
    end

    if debug_gear_list then --Dump parsed gearset from player-job.lua
      org.debug_gear_table(flattab,"gs-parsed-gearsets.log")
    end

    -- See if we have any non-equipment items to drag along
    if organizer_items then
        local organizer_item_list = org.unpack_names({}, 'L1', organizer_items, {})

        for _,tab in pairs(org.identify_items(organizer_item_list)) do
            count = gearswap.res.items[tab.id].stack
            flattab:append({id=tab.id,name=tab.name,log_name=tab.log_name,count=count})
        end
    end

    -- Get all player's available items
    local available_items = {}
    local all_bag_info = {}
    
    -- Get available bags only (Ex: not Mog Safe if not near moogle)
    for _,bag in pairs(res.bags) do
      all_bag_info[bag.id] = windower.ffxi.get_bag_info(bag.id)
      if all_bag_info[bag.id].enabled then
        available_items[bag.id] = windower.ffxi.get_items(bag.id)
      end
    end
    -- Check if all goal items exist in player's available bags
    local unavailable_items = T{}
    for i,v in ipairs(flattab) do
      local found
      for bag_id,bag in pairs(available_items) do
        for item_index,item_data in ipairs(bag) do
          if item_data.id == v.id and (not v.augments or v.augments and gearswap.extdata.decode(item_data).augments and gearswap.extdata.compare_augments(v.augments,gearswap.extdata.decode(item_data).augments)) then
            found = true
            break
          end
        end
        if found then
          break
        end
      end
      if not found then
        -- Add item to unavailable items list
        unavailable_items:append(v)
      end
    end
    -- Print message about unavailable items
    if #unavailable_items > 0 then
      local unavailable_msg = #unavailable_items..' item(s) unavailable: '
      for i,v in pairs(unavailable_items) do
        unavailable_msg = unavailable_msg..v.name
        if i ~= #unavailable_items then
          unavailable_msg = unavailable_msg..', '
        end
      end
      windower.add_to_chat(8, unavailable_msg)
      
      -- Update list of items to be processed by removing unavailable items
      local temp = T{}
      for i,v in ipairs(flattab) do
        local is_unavailable
        for n,m in ipairs(unavailable_items) do
          if m.id == v.id and (not v.augments or v.augments and m.augments and gearswap.extdata.compare_augments(v.augments,m.augments)) then
            is_unavailable = true
          end
        end
        if not is_unavailable then
          temp:append(v)
        end
      end
      flattab = table.reassign({}, temp)
    end
    
    -- At this point I have a table of equipment pieces indexed by the inventory name.
    -- I need to make a function that will translate that into a list of pieces in
    -- inventory or wardrobe.
    local ward_ids = {8,10,11,12}
    local current_wards = {}
    local assigned_items = {}

    for _,id in pairs(ward_ids) do
        current_wards[id] = available_items[id]
        current_wards[id].max = all_bag_info[id].max
        assigned_items[id] = T{}
    end
    
    -- Note: Empty slots in current_wards is formatted like an item with ID == 0.
    -- Remove empty slot entries.
    local temp = T{}
    for bag_id,bag in pairs(current_wards) do
      temp[bag_id] = T{}
      for item_index,item_data in ipairs(bag) do
        if item_data.id ~= 0 then
          temp[bag_id]:append(item_data)
        end
      end
    end
    current_wards = nil
    current_wards = table.copy(temp, true)
    temp = nil
    local movable_items = table.copy(current_wards, true) -- Deep copy table

    -- Add max counts for each wardrobe
    for _,id in pairs(ward_ids) do
      current_wards[id].max = windower.ffxi.get_bag_info(id).max
    end
  
    local unassigned_items = T{}
    for i,v in ipairs(flattab) do
        local found
        local ward_id
        local list_index
        for id,wardrobe in pairs(current_wards) do
            for n,m in ipairs(wardrobe) do
                if m.id == v.id and (not v.augments or v.augments and gearswap.extdata.decode(m).augments and gearswap.extdata.compare_augments(v.augments,gearswap.extdata.decode(m).augments)) then
                    found = true
                    list_index = n
                    break
                end
            end
            if found then
                ward_id = id
                break
            end
        end
        if found then
          -- Item is in the right bag!
          -- Set nil in movable_items to be removed later.
          movable_items[ward_id][list_index] = nil
          -- Add to list of assigned_items.
          assigned_items[ward_id]:append(v)
          if debug_found_list then
            org.debug("Found "..v.name.." (id: "..v.id..") in bag id "..ward_id)
          end
        else
          -- List as an unassigned item.
          unassigned_items:append(v)
          if debug_found_list then
            org.debug(v.name.." (id: "..v.id..") not found. Adding to unassigned list")
          end
        end
    end

    -- Remove nil entries from movable_items
    local temp = T{}
    for bag_id,bag in pairs(movable_items) do
      temp[bag_id] = T{}
      for item_index,item_data in pairs(bag) do
        if item_data then
          temp[bag_id]:append(item_data)
        end
      end
    end
    movable_items = nil
    movable_items = table.copy(temp, true)
    temp = nil

    -- Dump list of gear targetted for move
    if debug_move_list then
      org.debug_gear_table(unassigned_items,"gear-to-move.log")
    end

    -- Allocate gear that's not already in wardrobes to the wardrobes' empty space
    for _,ward_id in ipairs(ward_ids) do
      if #unassigned_items > 0 then
        local available_in_ward = current_wards[ward_id].max - #assigned_items[ward_id] - #movable_items[ward_id]
        local amount_to_assign = math.min(#unassigned_items, available_in_ward)
        if amount_to_assign > 0 then
          local moving = unassigned_items:slice(0-amount_to_assign)
          unassigned_items = unassigned_items:slice(1,#unassigned_items-amount_to_assign)
          assigned_items[ward_id]:extend(moving)
        end
      end
    end
    
    -- If there is still unassigned gear, fill out wardrobes to max capacity
    -- (room will be made by moving items to dump bags later)
    for _,ward_id in ipairs(ward_ids) do
      if #unassigned_items > 0 then
        local available_in_ward = current_wards[ward_id].max - #assigned_items[ward_id]
        local amount_to_assign = math.min(#unassigned_items, available_in_ward)
        if amount_to_assign > 0 then
          local moving = unassigned_items:slice(0-amount_to_assign)
          unassigned_items = unassigned_items:slice(1,#unassigned_items-amount_to_assign)
          assigned_items[ward_id]:extend(moving)
        end
      end
    end

    if #unassigned_items > 0 then
      windower.add_to_chat(123, 'Reorganizer Library: Your sets table contains too many items.')
      return
    end
    
    for _,id in ipairs(ward_ids) do
        local fw = file.new('../reorganizer/data/'..gearswap.res.bags[id].command..'/organizer-lib-file.lua')
        fw:write('-- Generated by the Reorganizer Library ('..os.date()..')\nreturn '..(assigned_items[id]:tovstring({'augments','log_name','name','id','count'})))
    end

    windower.send_command('wait 0.5;reorg o organizer-lib-file')
end

function org.simplify_entry(tab)
    -- Some degree of this needs to be done in unpack_names or I won't be able to detect when two identical augmented items are equipped.
    local output = T{id=tab.id,name=tab.name,log_name=tab.log_name}
    local rare = gearswap.res.items[tab.id].flags:contains('Rare')
    for i,v in ipairs(tab) do
        local handled = false
        if v.augment then
            v.augments = {v.augment}
            v.augment = nil
        end
        
        for n,m in ipairs(output) do
            if (not v.bag or v.bag and v.bag == m.bag) and v.slot == m.slot and
                (not v.augments or ( m.augments and gearswap.extdata.compare_augments(v.augments,m.augments))) then
                output[n].count = math.min(math.max(output[n].count,v.count),gearswap.res.items[tab.id].stack)
                handled = true
                break
            elseif (not v.bag or v.bag and v.bag == m.bag) and v.slot == m.slot and v.augments and not m.augments then
                -- v has augments, but there currently exists a matching version of the
                -- item without augments in the output table. Replace the entry with the augmented entry
                local countmax = math.min(math.max(output[n].count,v.count),gearswap.res.items[tab.id].stack)
                output[n] = v
                output[n].count = countmax
                handled = true
                break
            elseif rare then
                handled = true
                break
            end
        end
        if not handled then
            output:append(v)
        end
        
    end
    return output
end

function org.identify_items(tab)
    local name_to_id_map = {}
    local items = windower.ffxi.get_items()
    for id,inv in pairs(items) do
        if type(inv) == 'table' then
            for ind,item in ipairs(inv) do
                if type(item) == 'table' and item.id and item.id ~= 0 then
                    name_to_id_map[gearswap.res.items[item.id][gearswap.language]:lower()] = item.id
                    name_to_id_map[gearswap.res.items[item.id][gearswap.language..'_log']:lower()] = item.id
                end
            end
        end
    end
    local trans = T{}
    for i,v in pairs(tab) do
        local item = name_to_id_map[i:lower()] and table.reassign({},gearswap.res.items[name_to_id_map[i:lower()]]) --and org.identify_unpacked_name(i,name_to_id_map)
        if item then
            local n = gearswap.res.items[item.id][gearswap.language]:lower()
            local ln = gearswap.res.items[item.id][gearswap.language..'_log']:lower()
            if not trans[n] then
                trans[n] = T{id=item.id,
                    name=n,
                    log_name=ln,
                    }
            end
            trans[n]:extend(v)
        end
    end
    return trans
end

function org.unpack_names(ret_tab,up,tab_level,unpacked_table)
    for i,v in pairs(tab_level) do
        local flag = false
        if type(v)=='table' and i ~= 'augments' and not ret_tab[tostring(tab_level[i])] then
            ret_tab[tostring(tab_level[i])] = true
            unpacked_table, ret_tab = org.unpack_names(ret_tab,i,v,unpacked_table)
        elseif i=='name' then
            -- v is supposed to be a name, then.
            flag = true
        elseif type(v) == 'string' and v~='augment' and v~= 'augments' and v~= 'priority' then
            -- v is a string that's not any known option of gearswap, so treat it as an item name.
            -- I really need to make a set of the known advanced table options and use that instead.
            flag = true
        end
        if flag then
            local n = tostring(v):lower()
            if not unpacked_table[n] then unpacked_table[n] = {} end
            local ind = #unpacked_table[n] + 1
            if i == 'name' and gearswap.slot_map[tostring(up):lower()] then -- Advanced Table
                unpacked_table[n][ind] = tab_level
                unpacked_table[n][ind].count = unpacked_table[n][ind].count or 1
                unpacked_table[n][ind].slot = gearswap.slot_map[up:lower()]
            elseif gearswap.slot_map[tostring(i):lower()] then
                unpacked_table[n][ind] = {slot=gearswap.slot_map[i:lower()],count=1}
            end
        end
    end
    return unpacked_table, ret_tab
end

function org.string_augments(tab)
    local aug_str = ''
    if tab.augments then
        for aug_ind,augment in pairs(tab.augments) do
            if augment ~= 'none' then aug_str = aug_str..'['..aug_ind..'] = '..'"'..augment..'",\n' end
        end
    end
    if tab.augment then
        if tab.augment ~= 'none' then aug_str = aug_str.."'"..augment.."'," end
    end
    if aug_str ~= '' then return '{\n'..aug_str..'}' end
end

function org.debug_gear_table(gear_table,filename)
  local fw = file.new('../reorganizer/data/debug/'..filename)
  if fw and gear_table then
    fw:write("Dumping gear table contents:\nreturn")
    fw:write(org.serialize(gear_table,nil,nil,filename))
  end
end

function org.debug(s)
  local fw = file.new('../reorganizer/data/debug/debug.log')
  if fw and s then
    fw:append(s.."\n")
  end
end

-- serialize ~ by YellowAfterlife (https://yal.cc/lua-serializer/)
-- Converts value back into according Lua presentation
-- Accepts strings, numbers, boolean values, and tables.
-- Table values are serialized recursively, so tables linking to themselves or
-- linking to other tables in "circles". Table indexes can be numbers, strings,
-- and boolean values.
function org.serialize(object, multiline, depth, name)
	depth = depth or 0
	if multiline == nil then multiline = true end
	local padding = string.rep('    ', depth) -- can use '\t' if printing to file
	local r = padding -- result string
	if name then -- should start from name
		r = r .. (
			-- enclose in brackets if not string or not a valid identifier
			-- thanks to Boolsheet from #love@irc.oftc.net for string pattern
			(type(name) ~= 'string' or name:find('^([%a_][%w_]*)$') == nil)
			and ('[' .. (
				(type(name) == 'string')
				and string.format('%q', name)
				or tostring(name))
				.. ']')
			or tostring(name)) .. ' = '
	end
	if type(object) == 'table' then
		r = r .. '{' .. (multiline and '\n' or ' ')
		local length = 0
		for i, v in ipairs(object) do
			r = r .. org.serialize(v, multiline, multiline and (depth + 1) or 0) .. ','
				.. (multiline and '\n' or ' ')
			length = i
		end
		for i, v in pairs(object) do
			local itype = type(i) -- convert type into something easier to compare:
			itype =(itype == 'number') and 1
				or (itype == 'string') and 2
				or (itype == 'boolean') and 3
				or error('Serialize: Unsupported index type "' .. itype .. '"')
			local skip = -- detect if item should be skipped
				((itype == 1) and ((i % 1) == 0) and (i >= 1) and (i <= length)) -- ipairs part
				or ((itype == 2) and (string.sub(i, 1, 1) == '_')) -- prefixed string
			if not skip then
				r = r .. org.serialize(v, multiline, multiline and (depth + 1) or 0, i) .. ','
					.. (multiline and '\n' or ' ')
			end
		end
		r = r .. (multiline and padding or '') .. '}'
	elseif type(object) == 'string' then
		r = r .. string.format('%q', object)
	elseif type(object) == 'number' or type(object) == 'boolean' then
		r = r .. tostring(object)
	else
		error('Unserializeable value "' .. tostring(object) .. '"')
	end
	return r
end