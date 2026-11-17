# Assembly Line Manager

Dedicated GTNH 2.9 OpenComputers Assembly Line automation. The current v0.2 program is a SAFE READ-ONLY discovery tool; it never moves ingredients or starts a crafting job.

## Initial in-game build

1. Keep your dedicated Creative Computer near the Assembly Line.
2. Connect an ME Dual Interface to the existing main AE2 network. Give it the unique custom name Assembly Line Manager.
3. Place an ME Interface Terminal on that AE2 network. Place an OC Adapter adjacent to the block hosting that terminal, then connect the Adapter to your Creative Computer with OC Cable.
4. Put one Assembly Line processing pattern in the named Dual Interface for the read-only test.
5. Download the three program/config/catalog files below to the dedicated computer. Do not install startup scripts yet.

OpenOS commands, run separately:

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Manager/almanager.lua /home/almanager.lua
    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Manager/config.example.lua /home/almanager-config.lua
    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Manager/catalog.lua /home/almanager-catalog.lua

Read-only diagnostics:

    lua /home/almanager.lua probe
    lua /home/almanager.lua interfaces
    lua /home/almanager.lua scan
    lua /home/almanager.lua status

Expected: the computer sees a component named me_interface_terminal; the interfaces command shows the Dual Interface named Assembly Line Manager; the scan command shows its processing pattern and reports that no recipe catalog entry currently matches. It should never move anything.

If multiple Interface Terminals are connected, put the correct terminalAddress in /home/almanager-config.lua. You can edit it using OpenOS edit.

## Important GTNH 2.9 discoveries

- The Data Bank only supplies researched recipes to the Assembly Line. It is not required for the computer to read processing patterns or plan item distribution.
- New researched Data Sticks no longer store the ordered item and fluid ingredient lists in the old format. OC cannot learn input positions from those sticks alone.
- The OC driver for a Dual Interface is named fluid_interface and does not directly offer getInterfacePattern. The ME Interface Terminal OC driver exposes getInterfaces and their encoded patterns, so we are testing that path instead.
- An offline GTNH 2.9 Assembly Line recipe catalog will supply the input bus and fluid hatch ordering. It is not generated yet. The provided catalog.lua intentionally has zero entries.
- Actual transfers, fluid routing, job locks and automatic AE2 crafting are future phases and are NOT activated.

## Future physical layout

Main AE2 network -> ME Dual Interface -> item buffer chest and fluid buffer tanks -> OC-controlled Transposers -> 16 Assembly Line item buses and up to 4 fluid hatches.

Assembly Line Output Bus -> main AE2 network, to finish a requested crafting job.

Optional later: Data Bank with multiple Data Access Hatches -> TecTech Data Output Connector -> data pipe -> Assembly Line Data Input Hatch.

For now use an ordinary Data Access Hatch on the Assembly Line if you do not have a Data Bank. No OC connection to the Data Bank is necessary for routing.

## Source and architecture

- OC Interface Terminal: https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala
- OC Dual Interface: https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/ae2fc/DriverBlockFluidInterface.scala
- GTNH 2.9 Assembly Line recipes: https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/gregtech/loaders/postload/recipes/AssemblyLineRecipes.java

The existing root Stocking Manager files are not modified.
