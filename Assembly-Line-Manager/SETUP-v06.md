# Assembly Line Manager v0.6: physical test

GTNH 2.9, OpenComputers, AE2 Dual Interface. Data Sticks remain manual.

This is a *direct transfer test*, not yet a full autobatching manager.

## Hardware for the first test

1. Keep your working Creative Computer connected to the ME Dual Interface through OpenComputers.
2. Make an **item staging chest** that receives ingredients delivered when AE2 processes a pattern. Do not use the research-stick chest while research items are stored there.
3. Place an OpenComputers **Transposer** with two touching faces: the item staging chest and the first ULV Assembly Line Input Bus. Connect the Transposer to your Creative Computer with OC cable.
4. Deliver the first recipe fluid into its own **Super Tank**. Place a second Transposer between that tank and the intended **Fluid Input Hatch**. Connect it to the same OC cable network.
5. Disable any automatic item and fluid pipes that would bypass Transposer control during the test.
6. Import the Assembly Line's finished product into AE2 through a suitable output bus/import path. This path must be on the same crafting network.
7. Keep the recipe Data Stick manually available in the Data Access Hatch.

One Transposer moves materials only between its adjacent containers. More buses and hatches will require more physical routes, for example relay inventories with additional Transposers, or a separate verified item/fluid distribution system. The current single item test does not imply one Transposer can feed every bus.

## Install in OpenOS terminal

```
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Manager/al-route-v06.lua /home/al-route-v06.lua
lua /home/al-route-v06.lua probe
lua /home/al-route-v06.lua patterns
```

The `probe` command lists Transposers, component addresses, side numbers, inventory slots, and fluid tanks. It is read-only.

## Commands after confirming sides

```
lua /home/al-route-v06.lua item-check 1 1 ADDRESS SOURCE_SIDE BUS_SIDE
lua /home/al-route-v06.lua fluid-check 1 1 ADDRESS TANK_SIDE HATCH_SIDE
```

Replace ADDRESS with a unique Transposer address prefix from `probe` and each side with the number from `probe`. `1 1` means pattern slot 1, first ingredient of that type, not inventory slot 1.

Once item and fluid check commands show the expected source and destination, and ingredient positions have been checked against NEI, the `item-move` and `fluid-move` commands attempt one ingredient each. Each requires you to enter MOVE at a confirmation prompt.

Do not enable any unattended routing yet. Confirm that the machine can process one batch and that the product imports into the main AE2 network. The next program revision can build recipe matching, multiple destination routes, and counted repeated batches on top of these verified paths.
