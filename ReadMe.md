# Reorganizer

The purpose of this addon is to move all the gear you need for your job into your wardrobes with just 1 command. The magic is that it determines what gear you will need based on your current job's gearswap file!

# Installation / Setup
1. If you already had the old `organizer` addon, unload it, and disable automatic loading. This is a conflicting addon.
2. Download the latest version of `reorganizer` addon here: https://github.com/shastaxc/organizer/releases/latest
3. Move the `reorganizer-lib.lua` file into your `addons/gearswap/libs` folder. Overwrite if there is already a file there by that name.
4. Put the following line at the very top of your gearswap's job lua so the `//gs reorg` command can be recognized: `include('reorganizer-lib')`
5. Load the addon by executing the following command in game chat `//lua load reorganizer` or `//lua reload reorganizer` if you already had the old version loaded.
6. To enable automatic loading, either use the `plugin_manager` addon and add this to its `settings.xml` file, or add the following line to your Windower's `init.txt` script: `//lua load reorganizer`
7. After loading the addon in game for the first time, a `data` folder will be generated in your `addons/reorganizer` folder, and inside will be a `settings.xml` file. This file needs to be configured. See the "Settings Configuration" section below.

## Settings Configuration
The full list of bag names recognized in settings are as follows:
`Safe, Safe2, Storage, Locker, Satchel, Sack, Case, Wardrobe, Wardrobe2, Wardrobe3, Wardrobe4`

### Bag Priority
This section defines bags that are allowed to have gear pulled *from* them in order to equip your job.

In the `bag_priority` section, always keep the wardrobes there (the ones you have unlocked). Add to this section the bags you want to use for storing gear. It's highly recommended that you use Satchel, Sack, and Case before any others because you always have access to those 3 bags regardless of where you are. If you use Mog Safe (for example), this addon will only work properly when in range of a moogle that has access to it. To add a bag to your `bag_priority` list, add its opening and closing tags (the content between the tags is irrelevant but must be something). For example: `<Case>7</Case>`.

### Dump Bags
Dump bags are bags where items are allowed to be moved *into* to make space for gear you need for your job. Gear from the "Inventory" bag will get put there too if it's in Inventory when the `//gs reorg` command is run.

In the `dump_bags` section, it's highly recommended to simply make this list the same as `bag_priority`, but remove all the wardrobes. It is not recommended to set any wardrobes or inventory as dump bags.

### Retain
This section must contain `<items>true</items>`

This is because when this addon was split from `organizer`, it was only ever intended to work with gear (AKA "items").

# How To Use
1. Make sure you don't have junk gear in your inventory, or it will be sorted away into a random bag by mistake.
2. Change to a job you want to use.
3. Run the `//gs reorg` command.

# Restrictions
* You must have at least 2 free spaces in your inventory (specifically inventory, not the other bags).
* You must have a gearswap file defined for the job which you want the gear pulled.
* You may run into issues if you run `//gs reorg` without first allowing your items to fully load after zoning.
* You will need access to all your defined dump bags when running the `//gs reorg` command or it will error out.
* Only gear defined in the global `sets` table will be automatically pulled for your job. If you want gear that is not in a `sets` table (such as Warp Ring), you must create a dummy set and add those items. You can do this by creating sets like the following:
```
  sets.org = {}
  sets.org.job = {}
  sets.org.job[1] = {ring1="Warp Ring"}
  sets.org.job[2] = {back="Nexus Cape"}
```

# Note from the developer regarding rework of Organizer

After reworking this addon, the old and cumbersome `org freeze` and `org thaw` method no longer works. The purpose of the rework of this addon is to allow `//gs reorg` to work more efficiently and make day-to-day operation less cumbersome. 

# Troubleshooting
If gear for your job ends up in a dump bag when you think it shouldn't, ensure that it is in a `sets` table in your gearswap lua, and make sure it is spelled and formatted properly.

There are a couple debug tools you can use to help you figure things out on your own. In the file `addons/gearswap/lib/reorganizer-lib.lua` near the top there are three settings you can set to `true` which will create log files when you run `//gs reorg`. These variables are called `debug_gear_list`, `debug_move_list`, and `debug_found_list`

You can also turn on the verbose setting in the file `addons/reorganizer/data/settings.xml` by adding this to the "global" section: `<verbose>true</verbose>`

## Known Issues
* Will not work if gear you need for your job is in Inventory and already equipped.
