# GTNH Automation

This is my OpenComputers stocking system for GT New Horizons 2.9.

It checks how many items and fluids are in AE2 and turns machines on or off when needed. It can also give Redstone I/O blocks names so you know which one controls what.

## Getting the program

In the OpenComputers terminal,   need to be at the normal command prompt, not inside `lua`.

  can download the program with:

```sh
wget https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

Then   can open the setup menu:

```sh
stock setup
```

In the menu,   choose the AE2 connection that can see my main storage, find my Redstone  /O blocks, and give them names like "Chemical Plant" or "Farms".

After that,   can pick an output side for each block and choose what item or fluid it should control.

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

If `stock` isn't found,   can type `cd /home` first.

## How stocking works

For example,   could set Sulfur Dust to:

- **Below 30,000:** Turn the farm on.
- **Between 30,000 and 50,000:** Keep doing what it was already doing.
- **50,000 or more:** Turn the farm off.

The program checks AE2 every 10 seconds.

  can connect a wireless transmitter to each Redstone  /O output and put a matching receiver at the machine. Machines   want to control separately need their own outputs and wireless frequencies.

If   add another Redstone  /O block later, the program can detect it.   still need to name it and set up its outputs before it controls anything.

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

First,   stop the running program with **Ctrl+C**.

Then   can download the newest version:

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

My saved settings should still be there afterward.
