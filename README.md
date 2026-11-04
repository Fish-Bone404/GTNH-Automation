# GTNH Automation

This is my OpenComputers stocking system for GT New Horizons 2.9.

It checks how many items and fluids are in AE2 and turns machines on or off when needed. It can also give Redstone I/O blocks names so you know which one controls what.

## Getting the program

In the OpenComputers terminal, I need to be at the normal command prompt, not inside `lua`.

I can download the program with:

```sh
wget https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

Then I can open the setup menu:

```sh
stock setup
```

In the menu, I choose the AE2 connection that can see my main storage, find my Redstone I/O blocks, and give them names like "Chemical Plant" or "Farms".

After that, the menu shows which sides are already used and which ones are free. I can pick a free side and choose what item or fluid it controls.

## Commands

```sh
stock setup
```
Opens the menu to add blocks and set up stocking.

```sh
stock scan
```
Shows the redstone devices the server can see.

```sh
stock list
```
Shows all my saved stocking rules.

```sh
stock run
```
Starts checking AE2 and controlling the machines.

If `stock` isn't found, I can type `cd /home` first.

To change stocking amounts later, I use **9. Edit stocking amounts** in the setup menu. I don't have to delete the rule.

If I break and replace a Redstone I/O block, the new block gets a different address. The old rules will show **MISSING** in the rule list. I can use **10. Clean up rules for missing I/O blocks** to remove those old rules without affecting the new ones. The menu asks me to type `REMOVE` first. I should only use this when I'm sure the old block is gone, since unloaded or disconnected blocks can also show as missing.

## How stocking works

For example, I could set Sulfur Dust to:

- **Below 30,000:** Turn the farm on.
- **Between 30,000 and 50,000:** Keep doing what it was already doing.
- **50,000 or more:** Turn the farm off.

The program checks AE2 every 15 seconds **while `stock run` is running**. It does not automatically start when something gets low. The optional startup service below runs it automatically after OpenOS boots.

I can connect a wireless transmitter to each Redstone I/O output and put a matching receiver at the machine. Machines I want to control separately need their own outputs and wireless frequencies.

If I add another Redstone I/O block later, the program can detect it. I still need to name it and set up its outputs before it controls anything.

## Where my settings are saved

My block names, addresses, and stocking limits are saved on the in-game hard drive:

```text
/home/stock-config.dat
```

The program also keeps a backup at:

```text
/home/stock-config.dat.bak
```

Those files stay on my Minecraft server. They're not uploaded to GitHub, so updating the program won't replace my setup.

## Updating the program

First, I stop the running program with **Ctrl+C**.

Then I can download the newest version:

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

My saved settings should still be there afterward. Once the update is done, I can start it again with `stock run`.

## Fast item and fluid lookups in version 0.7

My stocking program now uses exact item and fluid lookups during its normal 15-second checks. It no longer reads the whole fluid inventory every cycle.

For the first upgrade, I stop the automatic stocking service and download the current program:

```sh
rc stocking stop
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

I can test an item or a fluid already stored in AE2 without changing Redstone I/O outputs:

```sh
stock testitem Sulfur Dust
stock testfluid Benzene
```

The test compares the previous inventory-list lookup against the new exact lookup. A PASS means they returned the same stored amount at the time of testing. If amounts are changing rapidly, the test can fail even if the new lookup works. I can pause transfers briefly and retry.

Before running any older fluid or item rules with this version, I migrate them once:

```sh
stock optimize
```

This identifies and saves the internal registry name for each fluid, or the item ID and damage for each item. It only saves if all pending rules pass validation. I need to keep a sample of each monitored material in AE2 during registration. If a fluid is temporarily empty, I add a sample and retry. Tagged variants and ambiguous item labels aren't automatically registered.

Then I restart the service:

```sh
rc stocking start
rc stocking status
cat /home/stock-service.log
```

New rules are automatically identified when I add them. The saved thresholds, outputs, GregTech wireless setup, and 15-second interval do not change. There is no need to recreate my registered rules.

## Starting stocking automatically when OpenOS boots

The `stocking.lua` service starts my stocking program in the background, so I can still use the computer.

I first stop any manually running `stock run` and install the current files in OpenOS:

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stocking.lua /etc/rc.d/stocking.lua
```

Then enable it at boot:

```sh
rc stocking enable
```

To test it immediately without rebooting:

```sh
rc stocking start
```

It starts after a short delay. To see the log or check the service status:

```sh
cat /home/stock-service.log
rc stocking status
```

To pause stocking while changing the rules, stop the service first. This also asks all reachable configured redstone outputs to turn off:

```sh
rc stocking stop
stock setup
rc stocking start
```

To stop starting it automatically on future boots:

```sh
rc stocking stop
rc stocking disable
```

The service waits a few seconds after boot and retries every 30 seconds if the program exits, such as when the AE2 network is temporarily unavailable. It still needs the OpenComputers server powered on, with its chunk and the relevant AE2/Redstone I/O chunks loaded. Don't run a separate manual `stock run` at the same time as this service.
