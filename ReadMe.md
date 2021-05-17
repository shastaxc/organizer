# Note from Shasta regarding rework of Organizer

After reworking this addon, the old and cumbersome `org freeze` method may no longer work. The primary purpose of this addon is now to allow `//gs org` to work more efficiently. All your bags must be loaded (so wait after zoning) in order to work. Unlike previously, you now only need to have 2 empty spaces in your `inventory` bag for this to work. All other bags may be full as long as you don't have any equipment in your inventory. If you have equipment in your inventory, you'll need that many free spaces in your dump bags for them to be placed.

You will need the corresponding updated `organizer-lib.lua` in the `GearSwap/libs` folder. Move it from the `addons/organizer` folder to the `addons/GearSwap/libs` folder and overwrite the existing file. Reload gearswap after this is done with `//lua r gearswap`.

If you have special gear that is equipped in your scripts via `equip()` functions but are not part of a `sets.whatever` table, it will not be sorted properly (will be put into a dump bag). To overcome this, simply add it to a dummy set. I use the syntax `sets.org.job[1]`, `sets.org.job[2]`, etc. You'll also need a `sets.org = {}` and `sets.org.job = {}` to avoid getting errors.

This rework is intended to work with gear only. I recommend configuring your settings to retain items:
```
<retain>
    <items>true</items>
</retain>
```

If gear for your job ends up in a dump bag when you think it shouldn't, ensure that it is in a `sets` table in your gearswap lua, and make sure it is spelled and formatted properly.

I would not recommend setting any wardrobes or inventory as dump bags. Also, you will need access to all your defined dump bags when running the `//gs org` command or it will error out.

# OLD NOTES

## Organizer (//org)

A multi-purpose inventory management solution. Similar to GearCollector; uses packets.

For the purpose of this addon, a `bag` is: "Safe", "Storage", "Locker", "Satchel", "Sack", "Case", "Wardrobe", "Safe 2". 

For commands that use a filename, if one is not specified, it defaults to Name_JOB.lua, e.g., Rooks_PLD.lua
For commands that specify a bag, if one is not specified, it defaults to all, and will cycle through all of them.

The addon command is `org`, so `org freeze` will freeze, etc.

This utility is still in development and there are at least a couple of known issues (it does not always move out gear that is currently equipped, argument parsing could be better). It is designed to work simplest as a snapshotting utility (freeze and organize without arugments), but it should work no matter what you want to do with it.

### Settings

#### auto_heal
Setting this feature to anything other than false will cause Organizer to use /heal after getting/storing gear.

#### bag_priority
The order that bags will be looked in for requested gear.

#### dump_bags
The order that bags will be filled with unspecified gear from your inventory.

#### item_delay
A delay, in seconds, between item storage/retrieval. Defaults to 0 (no delay)


### Commands
Commands below are written with their arguments indicated using square brackets, but you should not use square brackets when entering the commands in game. Default options are italicized.

#### Freeze

```
freeze [bag] [filename]
```

Freezes the current contents of a `bag` or **all bags** to the specified `filename` or **Name_ShortJob.lua** in the respective data directory/directories. This effectively takes a snapshot of your inventory for that job. So using `//org freeze` as a Dancer named Pablo would result in freezing all of your bags in files named Pablo_DNC.lua.

#### Get

```
get [bag] [filename]
```

Thaws the frozen state specified by `filename` or **Name_ShortJob.lua** and `bag` or **all bags** and makes one attempt to move towards that state.


#### Tidy

```
tidy [bag] [filename]
```

Thaws a frozen state specified by `filename` or **Name_ShortJob.lua** and `bag` or **all bags** and makes one attempt to purge anything currently in inventory that shouldn't be into dump bags.

#### Organize

```
organize [bag] [filename]
```

Thaws a frozen state specified by `filename` or **Name_ShortJob.lua** and `bag` or **all bags** and executes repeated Get and Tidy commands until a steady state is reached (aka. you have your gear). With no arguments, it will attempt to restore the entire thawed snapshot.

### Gearswap integration
Additionally, Organizer integrates with GearSwap. In your lua, just add this:

```
include('organizer-lib')
```

And then in your Mog House, after changing jobs:

```
//gs org
```

And it will fill your inventory with the items from your sets, and put everything else away (it does a very good job, even when there are space concerns, but it's not perfect. Make sure to do a "//gs validate" after!)

Additionally, if you have extra items you want to bring along, simply define a table named `organizer_items` like so:

```
organizer_items = {
    echos="Echo Drops",
    shihei="Shihei",
    orb="Macrocosmic Orb"
}
```
