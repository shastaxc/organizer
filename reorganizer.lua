--Copyright (c) 2021-2022, Shasta
--All rights reserved.

--Redistribution and use in source and binary forms, with or without
--modification, are permitted provided that the following conditions are met:

--    * Redistributions of source code must retain the above copyright
--      notice, this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above copyright
--      notice, this list of conditions and the following disclaimer in the
--      documentation and/or other materials provided with the distribution.
--    * Neither the name of <addon name> nor the
--      names of its contributors may be used to endorse or promote products
--      derived from this software without specific prior written permission.

--THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
--ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
--WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
--DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
--DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
--(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
--LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
--ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
--SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

res = require 'resources'
files = require 'files'
require 'pack'
Items = require 'items'
extdata = require 'extdata'
logger = require 'logger'
require 'tables'
require 'lists'
require 'functions'
config = require 'config'
slips = require 'slips'
packets = require 'packets'

_addon.name = 'Reorganizer'
_addon.author = 'Shasta (legacy devs: Byrth, Rooks)'
_addon.version = '2022JAN23'
_addon.commands = {'reorganizer','reorg'}

_static = {
  bag_ids = {
    inventory=0,
    safe=1,
    storage=2,
    temporary=3,
    locker=4,
    satchel=5,
    sack=6,
    case=7,
    wardrobe=8,
    safe2=9,
    wardrobe2=10,
    wardrobe3=11,
    wardrobe4=12,
    wardrobe5=13,
    wardrobe6=14,
    wardrobe7=15,
    wardrobe8=16,
  },
  wardrobe_ids = {[8]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true},
  usable_bags = {1,9,4,2,5,6,7,8,10,11,12,13,14,15,16}
}

_global = {
  language = 'english',
  language_log = 'english_log',
}

_ignore_list = {}
_retain = {}
_valid_pull = {}
_valid_dump = {}

default_settings = {
  dump_bags = {['Safe']=1,['Safe2']=2,['Locker']=3,['Storage']=4},
  bag_priority = {['Safe']=1,['Safe2']=2,['Locker']=3,['Storage']=4,['Satchel']=5,['Sack']=6,['Case']=7,['Inventory']=8,['Wardrobe']=9,['Wardrobe2']=10,['Wardrobe3']=11,['Wardrobe4']=12,['Wardrobe5']=13,['Wardrobe6']=14,['Wardrobe7']=15,['Wardrobe8']=16},
  item_delay = 0,
  ignore = {},
  retain = {
    ["moogle_slip_gear"]=false,
    ["seals"]=false,
    ["items"]=false,
    ["slips"]=false,
  },
  auto_heal = false,
  default_file='default.lua',
  verbose=false,
}

_debugging = {
  debug = {
    ['contains']=true,
    ['command']=true,
    ['find']=true,
    ['find_all']=true,
    ['items']=true,
    ['move']=true,
    ['settings']=true,
    ['stacks']=true
  },
  debug_log = 'data\\organizer-debug.log',
  enabled = false,
  warnings = false, -- This mode gives warnings about impossible item movements and crash conditions.
}

debug_log = files.new(_debugging.debug_log)

function s_to_bag(str)
  if not str and tostring(str) then return end
  for i,v in pairs(res.bags) do
    if v.en:lower():gsub(' ', '') == str:lower() then
      return v.id
    end
  end
end

windower.register_event('load',function()
  debug_log:write('Reorganizer loaded at '..os.date()..'\n')

  if debugging then windower.debug('load') end
  options_load()
end)

function options_load( )
  if not windower.dir_exists(windower.addon_path..'data\\') then
    org_debug("settings", "Creating data directory")
    windower.create_dir(windower.addon_path..'data\\')
    if not windower.dir_exists(windower.addon_path..'data\\') then
      org_error("unable to create data directory!")
    end
  end

  for bag_name, bag_id in pairs(_static.bag_ids) do
    if not windower.dir_exists(windower.addon_path..'data\\'..bag_name) then
      org_debug("settings", "Creating data directory for "..bag_name)
      windower.create_dir(windower.addon_path..'data\\'..bag_name)
      if not windower.dir_exists(windower.addon_path..'data\\'..bag_name) then
        org_error("unable to create"..bag_name.."directory!")
      end
    end
  end

    -- We can't just do a:
    --
    -- settings = config.load('data\\settings.xml', default_settings)
    --
    -- because the config library will try to merge them, and it will
    -- add back anything a user has removed (like items in bag_priority)

    if windower.file_exists(windower.addon_path..'data\\settings.xml') then
        org_debug("settings", "Loading settings from file")
        settings = config.load('data\\settings.xml')
    else
        org_debug("settings", "Saving default settings to file")
        settings = config.load('data\\settings.xml', default_settings)
    end

    -- Build the ignore list
    if(settings.ignore) then
        for bn,i_list in pairs(settings.ignore) do
            bag_name = bn:lower()
            _ignore_list[bag_name] = {}
            for _,ignore_name in pairs(i_list) do
                org_verbose("Adding "..ignore_name.." in the "..bag_name.." to the ignore list")
                _ignore_list[bag_name][ignore_name:lower()] = 1
            end
        end
    end

    -- Build a hard-wired pull list
    for bag_name,_ in pairs(settings.bag_priority) do
         org_verbose("Adding "..bag_name.." to the pull list")
        _valid_pull[s_to_bag(bag_name)] = 1
    end

    -- Build a hard-wired dump list
    for bag_name,_ in pairs(settings.dump_bags) do
         org_verbose("Adding "..bag_name.." to the push list")
        _valid_dump[s_to_bag(bag_name)] = 1
    end

    -- Build the retain lists
    if(settings.retain) then
        if(settings.retain.moogle_slip_gear == true) then
            org_verbose("Moogle slip gear set to retain")
            slip_lists = require('slips')
            for slip_id,slip_list in pairs(slip_lists.items) do
                for item_id in slip_list:it() do
                    if item_id ~= 0 then
                        _retain[item_id] = "moogle slip"
                        org_debug("settings", "Adding ("..res.items[item_id].english..') to slip retain list')
                    end
                end
            end
        end

        if(settings.retain.seals == true) then
            org_verbose("Seals set to retain")
            seals = {1126,1127,2955,2956,2957}
            for _,seal_id in pairs(seals) do
                _retain[seal_id] = "seal"
                org_debug("settings", "Adding ("..res.items[seal_id].english..') to slip retain list')
            end
        end

        if(settings.retain.items == true) then
            org_verbose("Non-equipment items set to retain")
        end
		
        if(settings.retain.slips == true) then
            org_verbose("Slips set to retain")
            for _,slips_id in pairs(slips.storages) do
                _retain[slips_id] = "slips"
                org_debug("settings", "Adding ("..res.items[slips_id].english..') to slip retain list')
            end
        end
    end

    -- Always allow inventory and wardrobe, obviously
    _valid_dump[0] = 1
    _valid_pull[0] = 1
    _valid_dump[8] = 1
    _valid_pull[8] = 1
    _valid_dump[10] = 1
    _valid_pull[10] = 1
    _valid_dump[11] = 1
    _valid_pull[11] = 1
    _valid_dump[12] = 1
    _valid_pull[12] = 1
    _valid_dump[13] = 1
    _valid_pull[13] = 1
    _valid_dump[14] = 1
    _valid_pull[14] = 1
    _valid_dump[15] = 1
    _valid_pull[15] = 1
    _valid_dump[16] = 1
    _valid_pull[16] = 1

end



windower.register_event('addon command',function(...)
    local inp = {...}
    -- get (g) = Take the passed file and move everything to its defined location.
    -- tidy (t) = Take the passed file and move everything that isn't in it out of my active inventory.
    -- organize (o) = get followed by tidy.
    local command = table.remove(inp,1):lower()
    if command == 'eval' then
        assert(loadstring(table.concat(inp,' ')))()
        return
    end

    local bag = 'all'
    if inp[1] and (_static.bag_ids[inp[1]:lower()] or inp[1]:lower() == 'all') then
        bag = table.remove(inp,1):lower()
    end

    org_debug("command", "Using '"..bag.."' as the bag target")


    file_name = table.concat(inp,' ')
    if string.length(file_name) == 0 then
        file_name = default_file_name()
    end

    if file_name:sub(-4) ~= '.lua' then
        file_name = file_name..'.lua'
    end
    org_debug("command", "Using '"..file_name.."' as the file name")


    if (command == 'g' or command == 'get') then
        org_debug("command", "Calling get with file_name '"..file_name.."' and bag '"..bag.."'")
        get(thaw(file_name, bag))
    elseif (command == 't' or command == 'tidy') then
        org_debug("command", "Calling tidy with file_name '"..file_name.."' and bag '"..bag.."'")
        local _, current_items = tidy(thaw(file_name, bag))

        -- Check to see if tidying is successful or if bags filled up
        dump_bags = get_dump_bags()
        if are_bags_full(current_items, dump_bags) then
          windower.add_to_chat(123, 'Reorganizer: All dump bags are full or inaccessible!')
        else
          windower.add_to_chat(008, 'Reorganizer: Finished tidying!')
        end
    elseif (command == 'f' or command == 'freeze') then

        org_debug("command", "Calling freeze command")
        local items = Items.new(windower.ffxi.get_items(),true)
        local frozen = {}
        items[3] = nil -- Don't export temporary items
        if _static.bag_ids[bag] then
            org_debug("command", "Bag: "..bag)
            freeze(file_name,bag,items)
        else
            for bag_id,item_list in items:it() do
                org_debug("command", "Bag ID: "..bag_id)
                -- infinite loop protection
                if(frozen[bag_id]) then
                    org_warning("Tried to freeze ID #"..bag_id.." twice, aborting")
                    return
                end
                frozen[bag_id] = 1
                freeze(file_name,res.bags[bag_id].english:lower():gsub(' ', ''),items)
            end
        end
    elseif (command == 'o' or command == 'organize') then
        org_debug("command", "Calling organize command")
        organize(thaw(file_name, bag))
    elseif command == 'test' then
    end

    if settings.auto_heal and tostring(settings.auto_heal):lower() ~= 'false' then
        org_debug("command", "Automatically healing")
        windower.send_command('input /heal')
    end

    org_debug("command", "Reorganizer complete")

end)

-- Attempt to move each goal item to it's target bag. Count successes and failures.
function get(goal_items,current_items)
    org_verbose('Getting!')
    if goal_items then
        count = 0
        failed = 0
        current_items = current_items or Items.new()
        goal_items, current_items = clean_goal(goal_items,current_items)
        for bag_id,bag in pairs(goal_items) do
            for ind,item in bag:it() do
                if not item:annihilated() then
                    local start_bag, start_ind = current_items:find(item)
                    -- Table contains a list of {bag, pos, count}
                    if start_bag then
                        if not current_items:route(start_bag,start_ind,bag_id) then
                            org_warning('Unable to move item.')
                            failed = failed + 1
                        else
                            count = count + 1
                        end
                        simulate_item_delay()
                    else
                        -- Need to adapt this for stacking items somehow.
                        org_warning(res.items[item.id].english..' not found.')
                    end
                end
            end
        end
        org_verbose("Got "..count.." item(s), and failed getting "..failed.." item(s)")
    end
    return goal_items, current_items
end

--Get the ignore item list for a given bag
function get_ignore_items(bag_id)
  for bag_name,b_id in pairs(_static.bag_ids) do
    if b_id == bag_id then
      return _ignore_list[bag_name]
    end
  end
  return nil
end

-- Attempt to move a goal item to its target bag. If target bag is full, attempt to move a
-- non-goal item out to make room. Return success or failure.
function move_goal_item(goal_items, current_items)
  org_verbose('Attempting to move goal item(s).')
  local is_success
  local processed_count = 0
  if goal_items then
    current_items = current_items or Items.new()
    for bag_id,bag in pairs(goal_items) do
      --Check ignore list items
      local bag_ignore_list = get_ignore_items(bag_id)
      for ind,item in bag:it() do
        processed_count = processed_count+1
        local full_bag
        local is_on_ignore
        if bag_ignore_list then --Valid ignore list for current bag
          is_on_ignore = bag_ignore_list[res.items[item.id].enl]
          if is_on_ignore then --Item is on ignore list
            org_verbose("Item: "..res.items[item.id].enl.." is on ignore list for bag id: "..bag_id)
          end
        end
        -- Only attempt sort if item is not already in right bag, not already failed move, or not in ignore list
        if not item:annihilated() and not item.hasFailed and not is_on_ignore then
          local start_bag, start_ind = current_items:find(item)
          if start_bag then
            is_success, full_bag, start_bag, start_ind = current_items:route(start_bag,start_ind,bag_id)

            local route_status
            goal_items, current_items, route_status = handle_route_result(goal_items, current_items, is_success, full_bag)
            if route_status == 2 then -- Try again
              is_success, full_bag = current_items:route(start_bag,start_ind,bag_id)
              goal_items, current_items, route_status = handle_route_result(goal_items, current_items, is_success, full_bag)
            end
            if route_status == 0 then -- Routing failed
              item.hasFailed = true
              is_success = false
            elseif route_status == 1 then -- Routing succeeded
              local potential_ind = current_items[bag_id]:contains(item)
              if potential_ind then
                -- Item has been moved to target bag. Annihilate item.
                item:annihilate(item.count)
                current_items[bag_id][potential_ind]:annihilate(current_items[bag_id][potential_ind].count)
              else
                org_warning('Attempted move but failed for '..res.items[item.id].english)
                item.hasFailed = true
              end
              is_success = true
              break
            else -- Unknown failure or potential infinite loop
              item.hasFailed = true
              is_success = false
            end
          else
            org_warning(res.items[item.id].english..' not found.')
            item.hasFailed = true
            is_success = false
          end
        end
      end
      if is_success then
        break
      end
    end
  end
  local total_goal_items = 0
  for bag_id,bag in pairs(goal_items) do
    total_goal_items = total_goal_items + bag._info.n
  end
  local did_process_all = processed_count == total_goal_items
  return goal_items, current_items, did_process_all
end

-- Return a status code. 0 = failure, 1 = success, 2 = try again
function handle_route_result(goal_items, current_items, route_did_succeed, full_route_bag)
  local status = -1
  if route_did_succeed then
    status = 1
  elseif full_route_bag and full_route_bag ~= 0 then
    -- Destination bag was full. Attempt to make room and try again.
    local is_make_room_success = make_room(goal_items, current_items, full_route_bag)
    if is_make_room_success then
      status = 2
    else
      status = 0
    end
  else
    org_warning('Unable to move item.')
    status = 0
  end
  return goal_items, current_items, status
end

-- Attempts to make 1 free space in the specified bag by moving a non-goal item to
-- inventory as long as there is at least 1 goal item un-annihilated in a dump bag
-- to ensure room will eventually be made for the non-goal item to be moved there later
function make_room(goal_items, current_items, bag_id)
  org_verbose('Attempting to make room in bag '..bag_id..'.')
  local is_make_room_success
  current_items = current_items or Items.new()
  local dump_bags = get_dump_bags()
  -- Find a non-goal item to move out of bag and into dump bag
  local start_ind
  for i, cur_item in current_items[bag_id]:it() do
    local found_in_goal_list
    for j, goal_item in goal_items[bag_id]:it() do
      if cur_item.id == goal_item.id then
        -- Found a goal item
        found_in_goal_list = true
        break
      end
    end
    if not found_in_goal_list then
      start_ind = i
      break
    end
  end
  -- If only goal-items found in target bag, failure
  if not start_ind then
    org_verbose('Failed to make space in bag '..bag_id)
    is_make_room_success = false
    return is_make_room_success
  end

  -- If all dump bags are full, ensure there will eventually be room made (goal item
  -- yet to be sorted is in there). Check items in each dump bag for an item that is a
  -- goal item, but whose destination bag is not a dump bag.
  local num_full_dump_bags = 0
  local count_dumps = 0
  for bag_id,bag_priority in pairs(dump_bags) do
    count_dumps = count_dumps + 1
    local bag_max = windower.ffxi.get_bag_info(bag_id).max
    if not current_items[bag_id] or current_items[bag_id]._info.n == bag_max then
      num_full_dump_bags = num_full_dump_bags + 1
    end
  end
  if num_full_dump_bags == count_dumps then
    local will_dump_space_be_made
    for i,bag_id in pairs(dump_bags) do
      -- Ensure dump bag is available
      if current_items[bag_id] then
        -- Check that bag to find a goal item that will be moved out later
        for j,cur_item in current_items[bag_id]:it() do
          local goal_bag = goal_items:find(cur_item)
          if goal_bag and not dump_bags[goal_bag] then
            will_dump_space_be_made = true
            break
          end
        end
      end
    end
    if not will_dump_space_be_made then
      is_make_room_success = false
      return is_make_room_success, goal_items, current_items
    end
  end
  
  -- Move non-goal item to inventory, which will eventually be moved to dump bag in next tidy() call
  local bag_max = windower.ffxi.get_bag_info(0).max
  local new_ind
  if bag_id ~= 0 and current_items[0]._info.n < bag_max then
      local item_count = current_items[bag_id][start_ind].count or 1
      new_ind = current_items[bag_id][start_ind]:move(0,0x52,item_count)
      simulate_item_delay()
      if new_ind then
        is_make_room_success = true
      end
  elseif bag_id ~= 0 and current_items[0]._info.n >= bag_max then
    is_make_room_success = false
    org_warning('Inventory is at max capacity.')
  end
  
  return is_make_room_success, goal_items, current_items
end

function freeze(file_name,bag,items)
    org_debug("command", "Entering freeze function with bag '"..bag.."'")
    local lua_export = T{}
    local counter = 0
    for _,item_table in items[_static.bag_ids[bag]]:it() do
        counter = counter + 1
        if(counter > 80) then
            org_warning("We hit an infinite loop in freeze()! ABORT.")
            return
        end
        org_debug("command", "In freeze loop for bag '"..bag.."'")
        org_debug("command", "Processing '"..item_table.log_name.."'")

        local temp_ext,augments = extdata.decode(item_table)
        if temp_ext.augments then
            org_debug("command", "Got augments for '"..item_table.log_name.."'")
            augments = table.filter(temp_ext.augments,-functions.equals('none'))
        end
        lua_export:append({name = item_table.name,log_name=item_table.log_name,
            id=item_table.id,extdata=item_table.extdata:hex(),augments = augments,count=item_table.count})
    end
    -- Make sure we have something in the bag at all
    if lua_export[1] then
        org_verbose("Freezing "..tostring(bag)..".")
        local export_file = files.new('/data/'..bag..'/'..file_name,true)
        export_file:write('return '..lua_export:tovstring({'augments','log_name','name','id','count','extdata'}))
    else
        org_debug("command", "Got nothing, skipping '"..bag.."'")
    end
end

-- Move non-goal items out of inventory and into other bags
function tidy(goal_items,current_items,usable_bags)
  org_debug("command", "Entering tidy()")
  current_items = current_items or Items.new()
  usable_bags = usable_bags or get_dump_bags()
  for index,item in current_items[0]:it() do
    local is_goal_item
    for i,bag in pairs(goal_items) do
      for j,g_item in bag:it() do
        local has_augs = item.augments ~= nil and g_item.augments ~= nil
        local augs_match = has_augs and g_item:compare_augments(item)
        if item.id == g_item.id and (not has_augs or (has_augs and augs_match)) then
          -- Is a goal item
          org_verbose('Not tidying goal item: '..res.items[item.id].english..'.')
          is_goal_item = true
          break
        end
      end
      if is_goal_item then
        break
      end
    end
    if not is_goal_item then
      org_debug("command", "Putting away "..item.log_name)
      current_items[0][index]:put_away(usable_bags)
      simulate_item_delay()
    end
  end
  return goal_items, current_items
end

function organize(goal_items)

  org_message('Starting...')
  local current_items = Items.new()
  local dump_bags = get_dump_bags()
  
  local total_goal_items = 0
  for bag_id,bag in pairs(goal_items) do
    for ind,item in bag:it() do
      total_goal_items = total_goal_items + 1
    end
  end

  local did_process_all = false
  local loop_limit = total_goal_items
  while loop_limit > 0 do
    -- Clear out inventory up until dump bags are full or inv is clean
    goal_items, current_items = tidy(goal_items,current_items,dump_bags)
    -- Check off goal items that are already in correct bag
    goal_items, current_items = clean_goal(goal_items,current_items)

    -- Iterate through goal items to put them into proper bags; if goal bag is
    -- full, move a non-goal item out of it first.
    goal_items, current_items, did_process_all = move_goal_item(goal_items, current_items)

    simulate_item_delay()
    
    if did_process_all then break end
    loop_limit = loop_limit - 1
  end

  goal_items, current_items = tidy(goal_items,current_items,dump_bags)
  
  -- Check to see if all items made it to their intended destinations
  local processed_count,failures = 0,T{}
  for bag_id,bag in pairs(goal_items) do
    for ind,item in bag:it() do
      if item:annihilated() then
        processed_count = processed_count + 1
      end
      if current_items[bag_id]:contains(item) or not item:annihilated() then
        item.bag_id = bag_id
        failures:append(item)
      end
    end
  end
  org_message('Done! - '..processed_count..' items sorted and '..table.length(failures)..' items failed!')
  if table.length(failures) > 0 then
      for i,v in failures:it() do
          org_message('Org Failed: '..i.name..(i.augments and ' '..tostring(T(i.augments)) or '')
            ..(i.id and res.items[i.id].stack and res.items[i.id].stack > 1 and ' (x'..i.count..')' or ''))
      end
  end
end

function clean_goal(goal_items,current_items)
  for i,bag in pairs(goal_items) do
      for ind,item in bag:it() do
          local potential_ind = current_items[i]:contains(item)
          if potential_ind then
              -- If it is already in the right spot, annihilate it.
              item:annihilate(item.count)
              current_items[i][potential_ind]:annihilate(current_items[i][potential_ind].count)
          end
      end
  end
  return goal_items, current_items
end

function incompletion_check(goal_items,remainder)
  -- Does not work. On cycle 1, you fill up your inventory without purging unnecessary stuff out.
  -- On cycle 2, your inventory is full. A gentler version of tidy needs to be in the loop somehow.
  local remaining = 0
  for i,v in pairs(goal_items) do
      for n,m in v:it() do
          if not m:annihilated() then
              remaining = remaining + 1
          end
      end
  end
  return remaining ~= 0 and remaining < remainder and remaining
end

function thaw(file_name,bag)
  local bags = _static.bag_ids[bag] and {[bag]=file_name} or table.reassign({},_static.bag_ids) -- One bag name or all of them if no bag is specified
  if settings.default_file:sub(-4) ~= '.lua' then
      settings.default_file = settings.default_file..'.lua'
  end
  for i,v in pairs(_static.bag_ids) do
      bags[i] = bags[i] and windower.file_exists(windower.addon_path..'data/'..i..'/'..file_name) and file_name or default_file_name()
  end
  bags.temporary = nil
  local inv_structure = {}
  for cur_bag,file in pairs(bags) do
      local f,err = loadfile(windower.addon_path..'data/'..cur_bag..'/'..file)
      if f and not err then
          local success = false
          success, inv_structure[cur_bag] = pcall(f)
          if not success then
              org_warning('User File Error (Syntax) - '..inv_structure[cur_bag])
              inv_structure[cur_bag] = nil
          end
      elseif bag and cur_bag:lower() == bag:lower() then
          org_warning('User File Error (Loading) - '..err)
      end
  end
  -- Convert all the extdata back to a normal string
  for i,v in pairs(inv_structure) do
      for n,m in pairs(v) do
          if m.extdata then
              inv_structure[i][n].extdata = string.parse_hex(m.extdata)
          end
      end
  end
  return Items.new(inv_structure)
end

function org_message(msg,col)
  windower.add_to_chat(col or 8,'Reorganizer: '..msg)
  flog(_debugging.debug_log, 'Reorganizer [MSG] '..msg)
end

function org_warning(msg)
  if _debugging.warnings then
      windower.add_to_chat(123,'Reorganizer: '..msg)
  end
  flog(_debugging.debug_log, 'Reorganizer [WARN] '..msg)
end

function org_debug(level, msg)
  if(_debugging.enabled) then
      if (_debugging.debug[level]) then
          flog(_debugging.debug_log, 'Reorganizer [DEBUG] ['..level..']: '..msg)
      end
  end
end


function org_error(msg)
  error('Reorganizer: '..msg)
  flog(_debugging.debug_log, 'Reorganizer [ERROR] '..msg)
end

function org_verbose(msg,col)
  if tostring(settings.verbose):lower() ~= 'false' then
      windower.add_to_chat(col or 8,'Reorganizer: '..msg)
  end
  flog(_debugging.debug_log, 'Reorganizer [VERBOSE] '..msg)
end

function default_file_name()
  player = windower.ffxi.get_player()
  job_name = res.jobs[player.main_job_id]['english_short']
  return player.name..'_'..job_name..'.lua'
end

function simulate_item_delay()
  if settings.item_delay and settings.item_delay > 0 then
      coroutine.sleep(settings.item_delay)
  end
end

function get_dump_bags()
  local dump_bags = {}
  for i,v in pairs(settings.dump_bags) do
      if i and s_to_bag(i) then
          dump_bags[tonumber(v)] = s_to_bag(i)
      elseif i then
          org_error('The bag name ("'..tostring(i)..'") in dump_bags entry #'..tostring(v)..' in the ../addons/reorganizer/data/settings.xml file is not valid.\nValid options are '..tostring(res.bags))
          return
      end
  end
  return dump_bags
end

function are_bags_full(current_items, bags_to_check)
  current_items = current_items or {}
  bags_to_check = bags_to_check or {}
  -- Check to see if tidying is successful or if bags filled up
  for bag_id,bag_value in pairs(dump_bags) do
    local bag_max = windower.ffxi.get_bag_info(bag_value).max
    local is_bag_accessible = (current_items[bag_id] and true) or false
    local is_bag_full = (is_bag_accessible and current_items[bag_id]._info.n == bag_max)
    -- If at least one bag is accessible and not full, then exit the loop
    if is_bag_accessible and not is_bag_full then
      return false
    end
  end
  return true
end