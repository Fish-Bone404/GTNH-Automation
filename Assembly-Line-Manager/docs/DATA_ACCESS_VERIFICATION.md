# Data Access verification for GTNH 2.9

Checked against GT5-Unofficial version `5.09.54.154` and the GTNH OpenComputers source.

## What the computer can and cannot inspect

| Block | Direct inventory inspection through an adjacent OC Transposer | Recipe information |
| --- | --- | --- |
| Standard Data Access Hatch | Supported by underlying Minecraft IInventory; 4 slots | Physical Data Sticks can be enumerated |
| Advanced Data Access Hatch | Supported by underlying Minecraft IInventory; 16 slots | Physical Data Sticks can be enumerated |
| Data Bank controller | Not a combined physical Data Stick inventory | No verified OC callback to enumerate the bank's recipes |
| Data Bank's Data Access Hatches | Same as ordinary Data Access Hatches | Read each physical hatch separately |
| Assembly Line Slave Connector / Data Input Hatch | No; getSizeInventory returns 0 and getStackInSlot returns null | Receives an internal ALRecipeDataPacket, which the normal inventory API does not expose |

**Caveat:** An OpenComputers Transposer's inventory inspection is subject to `allowItemStackInspection`, ownership/permission checks, and the actual in-game connectivity. Verify on your specific server before relying on it. The source-level compatibility is strong, but there is no live server test recorded here.

## Critical finding about recipe learning

GTNH 2.9's `AssemblyLineUtils.setAssemblyLineRecipeOnDataStick` writes the output, author, tooltip pages, and lastUpdate. It clears earlier tags. It **does not write each ordered item and fluid ingredient** to the stick.

OpenComputers `ConverterDataStick` still has logic to read old-style numbered `0`, `1`, etc. item tags and `f0`, `f1`, etc. fluid tags. Because the new GTNH 2.9 research Data Stick no longer writes those tags, `inputItems` and `inputFluids` will be empty on ordinary new sticks.

GTNH's Assembly Line and Data Bank use a server-side recipe lookup keyed from Data Stick output, so the machine still works even though OC does not get the recipe ingredient list.

**Implication:** Pattern-only automatic recipe learning cannot safely use the current Data Stick parser to discover bus positions. Implement a GTNH 2.9 recipe catalog or an equivalent accessible recipe lookup instead. The Lua prototype now rejects sticks with no ordered inputs rather than inventing assignments.

## Safe read-only test with an adjacent Transposer

Place an OC Transposer directly next to the **ordinary Data Access Hatch** holding your researched Data Sticks, and connect it to the Creative Computer with OC cable. In OpenOS, run the commands below, changing `sides.north` to the face of the hatch relative to the Transposer.

```lua
local component = require("component")
local sides = require("sides")
local t = component.transposer
local side = sides.north
print("Inventory slots:", t.getInventorySize(side))
local stick = t.getStackInSlot(side, 1)
if stick then
  print("Name:", stick.label)
  print("Recipe output:", stick.output or "(not exposed)")
  print("Ordered item entries:", stick.inputItems and #stick.inputItems or "(not exposed)")
else
  print("Slot 1 is empty or inaccessible")
end
```

Using `getAllStacks(side)` is preferable for multiple sticks because it is batched. This test does not modify any block or item.

For a Data Bank, repeat the test with Transposers next to its ordinary Data Access Hatches. Do **not** attempt to read the bank's slave connector this way, because it has no inventory slots.

## Source references

- [GTNH Data Access Hatch](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/gregtech/api/metatileentity/implementations/MTEHatchDataAccess.java)
- [GTNH Data Bank](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/tectech/thing/metaTileEntity/multi/MTEDataBank.java)
- [Data Input Hatch with no inventory](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/tectech/thing/metaTileEntity/hatch/MTEHatchDataItemsInput.java)
- [GTNH Data Stick recipe writer](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/gregtech/api/util/AssemblyLineUtils.java)
- [GTNH OC Data Stick converter](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/gregtech/ConverterDataStick.scala)
- [GTNH OC Transposer inventory reader](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/server/component/traits/WorldInventoryAnalytics.scala)
