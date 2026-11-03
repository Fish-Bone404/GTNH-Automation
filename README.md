# GTNH Automation

This is my OpenComputers stocking system for GT New Horizons 2.9.

It checks how many items and fluids I have in AE2 and turns machines on or off when I need more. I can also give my Redstone I/O blocks names so I know which one controls what.

## What I need

Before using it, I need:

- An OpenComputers server with OpenOS, a hard drive, a screen, and a keyboard.
- An OpenComputers Adapter connected to my **main AE2 network**.
- At least one Redstone I/O block.
- OpenComputers cables connecting everything to the server.

If I'm using a Server Rack, all those parts need to be on a network side the server can access.

The computer also lists Redstone Cards that are inside it. I need to make sure I'm registering the actual Redstone I/O block, not one of those cards. I can use an OpenComputers Analyzer to check each block's address.

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

After that, I can pick an output side for each block and choose what item or fluid it should control.

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

## How stocking works

For example, I could set Sulfur Dust to:

- **Below 30,000:** Turn the farm on.
- **Between 30,000 and 50,000:** Keep doing what it was already doing.
- **50,000 or more:** Turn the farm off.

The program checks AE2 every 10 seconds.

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

My saved settings should still be there afterward.

## Things to know

This is the first version, so I still need to test it in GTNH before trusting it to run my whole factory.

I'll test new outputs with a redstone lamp first. The setup menu has a test option that turns an output on for one second. I shouldn't use that test on a machine unless it's safe for the machine to turn on.

When the program starts, it sets its managed outputs to OFF. If it runs into an error, it tries to turn them off again. If a Redstone I/O block disconnects or its chunk unloads, though, the program might not be able to turn it off. Anything that must shut down safely needs a separate backup way to stop.

The program checks items by their displayed names, so items with the same name might get counted together. For fluids, I need to use a name the computer can see in AE2.

Right now this program handles redstone stocking. It doesn't start AE2 autocrafting jobs yet. I'll test everything before setting it to start automatically when the server boots.
