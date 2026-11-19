# GTNH 2.9 Assembly Line Manager v4

The previous separate item v3 and fluid v1 scripts are superseded for combined operation.
This is an unverified first release intended for staged in-game testing, NOT a proven unattended system.

## In-world layout

1. Keep the current AE2 Dual Interface, item staging Gold Chest, item Transposer, conduit distribution chest, and priority-filtered Ender IO item routes to Assembly Line buses.
2. Keep the OpenComputers Adapter attached to the Assembly Line controller.
3. The AE2 Dual Interface should output fluids into TWO SEPARATE source tanks, Indalloy 140 and Lubricant for current Pump/Motor tests. Do not pump the contents directly into input hatches.
4. Place a DIFFERENT fluid Transposer touching both source tanks and two output tanks. The output tanks may drain through isolated pumps/pipes or other tested transfers to Assembly Line Hatch 1 and Hatch 2, respectively.
5. The fluid Transposer must also connect to the Creative Computer's OC network. Do not connect output tank lines to each other.
6. Configure exact fluid source sides and output hatch destinations from a real scan. Output tanks must be empty at the beginning of each dispatch.

Each station has one to four source tank faces and output tank faces, within the six sides available on a Transposer. You can add a second Transposer for recipes requiring Hatch 3 or Hatch 4. Source and destination must be on the same Transposer for a direct transfer.

AE2 outputs the bulk amount for a multi-item request, but the manager releases only a single craft's fluid quantities per machine cycle, based on the currently approved AE2 pattern. It will wait until total staged fluid equals exactly the total needed for all currently staged item batches.

For example, 10 Pumps LuV require staging at least 1,440 L Indalloy 140 and 2,500 L Lubricant. The manager transfers 144 L and 250 L for one craft, waits until the Assembly Line finishes, then repeats.

## Install on OpenOS terminal

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/al-assembly-manager-v4.lua /home/al-assembly-manager.lua
    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/al-fluid-config-v4.example.lua /home/al-fluid-config.lua

The existing /home/al-item-config.lua retains all its tested addresses and chest sides.

Run:

    lua /home/al-assembly-manager.lua fluid-probe

Identify the FLUID Transposer address, source sides, and output sides. Then:

    edit /home/al-fluid-config.lua

Fill in the REAL addresses and side numbers. Do not use the example values without matching them to the world.

Read-only validation, with at least one exact staged crafting request:

    lua /home/al-assembly-manager.lua check
    lua /home/al-assembly-manager.lua fluid-check

After verifying item buses and numbered fluid hatches, start the manager:

    lua /home/al-assembly-manager.lua run

This is a foreground process, not an autostart service. Do not run v3 at the same time.

## Safety

The manager stops rather than guesses if multiple different recipes are mixed, pattern approval is invalid, a tank is unknown, an output tank is not empty, or staged fluid amounts do not exactly correspond to the staged item batch count.

Both item and fluid movements are logged in safety journals. The journals are only cleared automatically after the Assembly Line is observed running and returning idle. A crash or an interrupted transfer requires physical inspection and an explicit reset.

Assembly Line activity is NOT the same as confirmed output import to AE2. Actual output return is a separate requirement. The program also does not verify the contents of distant item buses or hatches.

Fluid amounts are OpenComputers mB units. The GTNH UI may display these as L. Fluid output tanks must have enough capacity for one recipe and stage tanks enough for the total AE2 batch.

This setup has not been validated in Minecraft. Run fluid-probe, then fluid-check, before using run.
