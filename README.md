# GTNH Automation

OpenComputers AE2 stocking controller for GT New Horizons 2.9.

This project discovers connected redstone components, lets you register physical Redstone I/O blocks by unique address and friendly name, and controls their six separate faces based on AE2 inventory quantities.

## Before starting

The OpenComputers server must have OpenOS, a hard drive, a screen and keyboard, a working ME Controller or ME Interface component on your **main** AE2 network, and at least one external Redstone I/O block. For Server Racks, ensure the screen, adapter, and Redstone I/O are on the server's configured OpenComputers network connection.

**Important:** The component list includes internal Redstone Cards as well as external I/O blocks. Use an OpenComputers Analyzer to match each physical block's address before registering it.

## Install inside OpenOS

From the normal OpenOS shell, not the interactive Lua prompt:

```sh
wget https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

To set up:

```sh
stock setup
```

Select the AE2 component with access to your main item inventory. Then discover and register external Redstone I/O blocks, give them descriptive names, and assign item or fluid stocking rules to individual faces.

Other commands:

```sh
stock scan
stock list
stock run
```

If the shell cannot locate `stock`, use `cd /home` first.

## Stocking logic

For an item with lower limit 30,000 and upper limit 50,000:

- Below 30,000, enable the assigned redstone output.
- Between those values, maintain the previous state.
- At 50,000 or above, disable it.

A separate wireless transmitter can be attached to each Redstone I/O output and paired with receiver(s) on its frequency. Use separate outputs and frequencies for independently controlled machines.

The program checks inventories every 10 seconds. It discovers newly connected redstone components during operation, but **does not activate or register them automatically**.

## Local configuration

Names, component addresses, thresholds and AE2 component selection are saved on the OpenComputers drive at:

```text
/home/stock-config.dat
```

A backup is kept at `/home/stock-config.dat.bak` when changes are saved. This configuration file does **not** belong in the public GitHub repository.

## Updating

Stop the running controller with Ctrl+C and download the latest program:

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
```

Your saved configuration remains in place.

## Safety notes

This is an initial version and has not yet been tested on the user's actual GTNH 2.9 server. Test with a redstone lamp or otherwise disconnected output before controlling production. The setup menu's output test activates one selected face for one second.

The program initializes managed outputs OFF at startup. If an AE2 read fails or another runtime error occurs, it attempts to turn reachable managed outputs OFF. A disconnected, unloaded, or broken component may retain its last physical redstone state. Use physical fail-safe wiring for any machine that must reliably turn off.

The current item query uses display labels, so different variants with identical labels may be counted together. Fluid rules require a name present in your AE2 fluid inventory when registered. This version controls redstone but does not request AE2 autocrafting jobs. Do not enable unattended startup until the actual output behavior has been verified.
