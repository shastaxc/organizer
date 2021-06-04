--Copyright (c) 2015, Byrthnoth and Rooks
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

local Items = {}
local items = {}
local bags = {}
local item_tab = {}

local function validate_bag(bag_table)
    if (bag_table.access == 'Everywhere' or (bag_table.access == 'Mog House' and windower.ffxi.get_info().mog_house)) and
        windower.ffxi.get_bag_info(bag_table.id) then
        return true
    end
    return false
end

local function validate_id(id)
    return (id and id ~= 0 and id ~= 0xFFFF) -- Not empty or gil
end

local function wardrobecheck(bag_id,id)
    return _static.wardrobe_ids[bag_id]==nil or ( res.items[id] and (res.items[id].type == 4 or res.items[id].type == 5) )
end

function Items.new(loc_items,bool)
    loc_items = loc_items or windower.ffxi.get_items()
    new_instance = setmetatable({}, {__index = function (t, k) if rawget(t,k) then return rawget(t,k) else return rawget(items,k) end end})
    for bag_id,bag_table in pairs(res.bags) do
        org_debug("items", "Items.new::bag_id: "..bag_id)
        bag_name = bag_table.english:lower():gsub(' ', '')
        org_debug("items", "Items.new::bag_name: "..bag_name)
        if (bool or validate_bag(bag_table)) and (loc_items[bag_id] or loc_items[bag_name]) then
            org_debug("items", "Items.new: new_instance for ID#"..bag_id)
            local cur_inv = new_instance:new(bag_id)
            for inventory_index,item_table in pairs(loc_items[bag_id] or loc_items[bag_name]) do
                if type(item_table) == 'table' and validate_id(item_table.id) then
                    org_debug("items", "Items.new: inventory_index="..inventory_index.." item_table.id="..item_table.id.." ("..res.items[item_table.id].english..")")
                    cur_inv:new(item_table.id,item_table.count,item_table.extdata,item_table.augments,item_table.status,inventory_index)
                end
            end
        end
    end
    return new_instance
end

function items:new(key)
    org_debug("items", "New items instance with key "..key)
    local new_instance = setmetatable({_parent = self,_info={n=0,bag_id=key}}, {__index = function (t, k) if rawget(t,k) then return rawget(t,k) else return rawget(bags,k) end end})
    self[key] = new_instance
    return new_instance
end

function items:find(item)
    for bag_name,bag_id in pairs(settings.bag_priority) do
      real_bag_id = s_to_bag(bag_name)
      org_debug("find", "Searching "..bag_name.." for "..res.items[item.id].english..".")
        if self[real_bag_id] and self[real_bag_id]:contains(item) then
          org_debug("find", "Found "..res.items[item.id].english.." in "..bag_name..".")
            return real_bag_id, self[real_bag_id]:contains(item)
        else
          org_debug("find", "Didn't find "..res.items[item.id].english.." in "..bag_name..".")
        end
    end
    org_debug("find", "Didn't find "..res.items[item.id].english.." in any bags.")
    return false
end

function items:route(start_bag,start_ind,end_bag,count)
    count = count or self[start_bag][start_ind].count
    local success = true
    local full_bag
    local initial_bag = start_bag
    local initial_ind = start_ind
    local limbo_ind
    local limbo_bag
    local inventory_max = windower.ffxi.get_bag_info(0).max
    -- If not in inventory and inventory not full, move it to inventory
    if start_bag ~= 0 and self[0]._info.n < inventory_max then
      -- Also get the new slot number of item after moving to inventory
      limbo_ind = self[start_bag][start_ind]:move(0,0x52,count)
      start_ind = limbo_ind
      if limbo_ind then
        limbo_bag = 0
      else
        limbo_bag = nil
        limbo_ind = nil
      end
    elseif start_bag ~= 0 and self[0]._info.n >= inventory_max then
        success = false
        full_bag = 0
        org_warning('Cannot move more than '..inventory_max..' items into inventory')
        return success, full_bag, limbo_bag, limbo_ind
    end

    -- At this point, item is guaranteed to be in inventory

    -- Get destination bag info
    local destination_enabled = windower.ffxi.get_bag_info(end_bag).enabled
    local destination_max = windower.ffxi.get_bag_info(end_bag).max

    -- If you don't have access to the destination bag, operation fails
    if not destination_enabled then
        success = false
        org_warning('Cannot move to '..tostring(end_bag)..' because it is disabled')
    -- If destination bag is not inventory, ensure there is room in bag then transfer item
    elseif start_ind and end_bag ~= 0 and self[end_bag]._info.n < destination_max then
        start_ind = self[0][start_ind]:move(end_bag,0x52,count)
        if start_ind then
          success = true
          limbo_ind = nil
          limbo_bag = nil
        else
          success = false
        end
    elseif not start_ind then
        success = false
        org_warning('Initial movement of the route failed. ('..tostring(start_bag)..' '..tostring(initial_ind)..' '..tostring(start_ind)..' '..tostring(end_bag)..')')
    elseif self[end_bag]._info.n >= destination_max then
        full_bag = end_bag
        success = false
        org_warning('Cannot move more than '..destination_max..' items into that inventory ('..end_bag..')')
    end
    return success, full_bag, limbo_bag, limbo_ind
end

function items:it()
    local i = 0
    local bag_priority_list = {}
    for i,v in pairs(settings.bag_priority) do
        bag_priority_list[v] = i
    end
    return function ()
        while i < #bag_priority_list do
            i = i + 1
            local id = s_to_bag(bag_priority_list[i])
            if not id then
                org_error('The bag name ("'..tostring(bag_priority_list[i])..'") with priority '..tostring(i)..' in the ../addons/organizer/data/settings.xml file is not valid.\nValid options are '..tostring(res.bags))
            end
            if self[id] and validate_bag(res.bags[id]) then
                return id, self[id]
            end
        end
    end

end

function bags:new(id,count,ext,augments,status,index)
    local max_size = windower.ffxi.get_bag_info(self._info.bag_id).max
    if self._info.n >= max_size then org_warning('Attempting to add another item to a full bag') return end
    if index and table.with(self,'index',index) then org_warning('Cannot assign the same index twice') return end
    self._info.n = self._info.n + 1
    index = index or self:first_empty()
    status = status or 0
    augments = augments or ext and id and extdata.decode({id=id,extdata=ext}).augments
    if augments then augments = table.filter(augments,-functions.equals('none')) end
    self[index] = setmetatable({_parent=self,id=id,count=count,extdata=ext,index=index,status=status,
        name=res.items[id][_global.language]:lower(),log_name=res.items[id][_global.language_log]:lower(),augments=augments},
        {__index = function (t, k) 
            if not t or not k then print('table index is nil error',t,k) end
            if rawget(t,k) then
                return rawget(t,k)
            else
                return rawget(item_tab,k)
            end
        end})
    return index
end

function bags:it()
    local max = windower.ffxi.get_bag_info(self._info.bag_id).max
    local i = 0
    return function ()
        while i < max do
            i = i + 1
            if self[i] then return i, self[i] end
        end
    end
end

function bags:first_empty()
    local max = windower.ffxi.get_bag_info(self._info.bag_id).max
    for i=1,max do
        if not self[i] then return i end
    end
end

function bags:remove(index)
    if not rawget(self,index) then org_warning('Attempting to remove an index that does not exist') return end
    self._info.n = self._info.n - 1
    rawset(self,index,nil)
end

function bags:find_all_instances(item,bool,first)
    local instances = L{}
    for i,v in self:it() do
        org_debug("find_all", "find_all_instances: slot="..i.." v="..res.items[v.id].english.." item="..res.items[item.id].english.." ")
        if (bool or not v:annihilated()) and v.id == item.id then -- and v.count >= item.count then
            if not item.augments or table.length(item.augments) == 0 or v.augments and extdata.compare_augments(item.augments,v.augments) then
                -- May have to do a higher level comparison here for extdata.
                -- If someone exports an enchanted item when the timer is
                -- counting down then this function will return false for it.
                instances:append(i)
                if first then
                    return instances
                end
            end
        end
    end
    if instances.n ~= 0 then
        return instances
    else
        return false
    end
end

function bags:contains(item,bool)
    bool = bool or false -- Default to only looking at unannihilated items
    org_debug("contains", "contains: searching for "..res.items[item.id].english.." in "..self._info.bag_id)
    local instances = self:find_all_instances(item,bool,true)
    if instances then
        return instances:it()()
    end
    return false
end

function bags:find_unfinished_stack(item,bool)
    local tab = self:find_all_instances(item,bool,false)
    if tab then
        for i in tab:it() do
            if res.items[self[i].id] and res.items[self[i].id].stack > self[i].count then
                return i
            end
        end
    end
    return false
end

function item_tab:transfer(dest_bag,count)
    -- Transfer an item to a specific bag.
    if not dest_bag then org_warning('Destination bag is invalid.') return false end
    count = count or self.count
    local parent = self._parent
    local targ_inv = parent._parent[dest_bag]

    local parent_bag_id = parent._info.bag_id
    local target_bag_id = targ_inv._info.bag_id

    if not (target_bag_id == 0 or parent_bag_id == 0) then
        org_warning('Cannot move between two bags that are not inventory bags.')
    else
        while parent[self.index] and targ_inv:find_unfinished_stack(parent[self.index]) do
            org_debug("stacks", "Moving ("..res.items[self.id].english..') from '..res.bags[parent_bag_id].en..' to '..res.bags[target_bag_id].en..'')
            local rv = parent[self.index]:move(dest_bag,targ_inv:find_unfinished_stack(parent[self.index]),count)
            if not rv then
                org_debug("stacks", "FAILED moving ("..res.items[self.id].english..') from '..res.bags[parent_bag_id].en..' to '..res.bags[target_bag_id].en..'')
                break
            end
        end
        if parent[self.index] then
            parent[self.index]:move(dest_bag)
        end
        return true
    end
    return false
end

function item_tab:move(dest_bag,dest_slot,count)
    if not dest_bag then org_warning('Destination bag is invalid.') return false end
    count = count or self.count
    local parent = self._parent
    local targ_inv = parent._parent[dest_bag]
    dest_slot = dest_slot or 0x52

    local parent_bag_id = parent._info.bag_id
    local parent_bag_name = res.bags[parent_bag_id].en:lower()

    local target_bag_id = targ_inv._info.bag_id

    org_debug("move", "move(): Item: "..res.items[self.id].english)
    org_debug("move", "move(): Parent bag: "..parent_bag_id)
    org_debug("move", "move(): Target bag: "..target_bag_id)

    -- issues with bazaared items makes me think we shouldn't screw with status'd items at all
    if(self.status > 0) then
        if(self.status == 5) then
            org_verbose('Skipping item: ('..res.items[self.id].english..') because it is currently equipped.')
            return false
        elseif(self.status == 19) then
            org_verbose('Skipping item: ('..res.items[self.id].english..') because it is an equipped linkshell.')
            return false
        elseif(self.status == 25) then
            org_verbose('Skipping item: ('..res.items[self.id].english..') because it is in your bazaar.')
            return false
        end
    end

    -- check the 'retain' lists
    if((parent_bag_id == 0) and _retain[self.id]) then
        org_verbose('Skipping item: ('..res.items[self.id].english..') because it is set to be retained ('.._retain[self.id]..')')
        return false
    end

    if((parent_bag_id == 0) and settings.retain and settings.retain.items) then
        local cat = res.items[self.id].category
        if(cat ~= 'Weapon' and cat ~= 'Armor') then
            org_verbose('Skipping item: ('..res.items[self.id].english..') because non-equipment is set be retained')
            return false
        end
    end

    -- respect the ignore list
    if(_ignore_list[parent_bag_name] and _ignore_list[parent_bag_name][res.items[self.id].english]) then
        org_verbose('Skipping item: ('..res.items[self.id].english..') because it is on the ignore list')
        return false
    end

    -- Make sure the source can be pulled from
    if not _valid_pull[parent_bag_id] then
        org_verbose('Skipping item: ('..res.items[self.id].english..') - can not be pulled from '..res.bags[parent_bag_id].en..') ')
        return false
    end

    -- Make sure the target can be pushed to
    if not _valid_dump[target_bag_id] then
        org_verbose('Skipping item: ('..res.items[self.id].english..') - can not be pushed to '..res.bags[target_bag_id].en..') ')
        return false
    end

    if not self:annihilated() and
        (not dest_slot or not targ_inv[dest_slot] or (targ_inv[dest_slot] and res.items[targ_inv[dest_slot].id].stack < targ_inv[dest_slot].count + count)) and
        (targ_inv._info.bag_id == 0 or parent._info.bag_id == 0) and
        wardrobecheck(targ_inv._info.bag_id,self.id) and
        self:free() then
        windower.packets.inject_outgoing(0x29,string.char(0x29,6,0,0)..'I':pack(count)..string.char(parent._info.bag_id,dest_bag,self.index,dest_slot))
        org_verbose('Moving item! ('..res.items[self.id].english..') from '..res.bags[parent._info.bag_id].en..' '..parent._info.n..' to '..res.bags[dest_bag].en..' '..targ_inv._info.n..')')
        local new_index = targ_inv:new(self.id, count, self.extdata, self.augments)
        --print(parent._info.bag_id,dest_bag,self.index,new_index)
        parent:remove(self.index)
        return new_index
    elseif not dest_slot then
        org_warning('Cannot move the item ('..res.items[self.id].english..'). Target inventory is full ('..res.bags[dest_bag].en..')')
    elseif targ_inv[dest_slot] and res.items[targ_inv[dest_slot].id].stack < targ_inv[dest_slot].count + count then
        org_warning('Cannot move the item ('..res.items[self.id].english..'). Target inventory slot would be overly full ('..(targ_inv[dest_slot].count + count)..' items in '..res.bags[dest_bag].en..')')
    elseif (targ_inv._info.bag_id ~= 0 and parent._info.bag_id ~= 0) then
        org_warning('Cannot move the item ('..res.items[self.id].english..'). Attempting to move from a non-inventory to a non-inventory bag ('..res.bags[parent._info.bag_id].en..' '..res.bags[dest_bag].en..')')
    elseif self:annihilated() then
        org_warning('Cannot move the item ('..res.items[self.id].english..'). It has already been moved.')
    elseif not wardrobecheck(targ_inv._info.bag_id,self.id) then
        org_warning('Cannot move the item ('..res.items[self.id].english..') to the wardrobe. Wardrobe cannot hold an item of its type ('..tostring(res.items[self.id].type)..').')
    elseif not self:free() then
        org_warning('Cannot free the item ('..res.items[self.id].english..'). It has an unaddressable item status ('..tostring(self.status)..').')
    end
    return false
end

function item_tab:put_away(usable_bags)
    org_debug("move", "Putting away "..res.items[self.id].english)
    local current_items = self._parent._parent
    usable_bags = usable_bags or _static.usable_bags
    local bag_free
    for _,v in pairs(usable_bags) do
        local bag_max = windower.ffxi.get_bag_info(v).max
        if current_items[v]._info.n < bag_max and wardrobecheck(v,self.id) then
            bag_free = v
            break
        end
    end
    if bag_free then
        self:transfer(bag_free,self.count)
    end
end

function item_tab:free()
    if self.status == 5 then
        local eq = windower.ffxi.get_items().equipment
        for _,v in pairs(res.slots) do
            local ind_name = v.english:lower():gsub(' ','_')
            local bag_name = ind_name..'_bag'
            local ind, bag = eq[ind_name],eq[bag_name]
            if self.index == ind and self._parent._info.bag_id == bag then
                windower.packets.inject_outgoing(0x50,string.char(0x50,0x04,0,0,self._parent._info.bag_id,v.id,0,0))
                break
            end
        end
    elseif self.status ~= 0 then
        return false
    end
    return true
end

function item_tab:annihilate(count)
    count = count or rawget(item_tab,'count')
    local a_count = (rawget(item_tab,'a_count') or 0) + count
    if a_count >count then
        org_warning('Moving more of an item ('..item_tab.id..' : '..a_count..') than possible ('..count..'.')
    end
    rawset(self,'a_count',a_count)
end

function item_tab:annihilated()
    return ( (rawget(self,'a_count') or 0) >= rawget(self,'count') )
end

function item_tab:available_amount()
    return ( rawget(self,'count') - (rawget(self,'a_count') or 0) )
end

-- Returns boolean after comparing the augment lists on both items.
-- Assumes both items have augment table keyed as "augments"
function item_tab:compare_augments(other_item)
  if #self.augments ~= #other_item.augments then
    return false
  end
  if #self.augments == 1 then
    return self.augments == other_item.augments
  end

  local matches = {}
  for i,self_aug in pairs(self.augments) do
    for j,other_aug in pairs(other_item.augments) do
      -- Only counts as a match if the values are the same and hasn't matched before
      if self_aug == other_aug and not matches[j] then
        -- Found a matching augment, note the index in matches table
        matches[j]=true
      end
    end
  end

  -- If number of matches equals number of augments, all augments match
  return #matches == #self.augments
end

return Items
