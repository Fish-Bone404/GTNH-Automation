# Assembly Line Rebuild: clean staging test (GTNH 2.9)

This is a NEW design. Previous scripts, old Transposer mappings, Data Stick swappers, and routing code are not used.

## Goal

AE2 processing request -> ME Dual Interface -> separate item and fluid staging -> OpenComputers reads staged inputs and matches a recipe -> eventual controlled delivery to ordered Assembly Line buses and hatches -> finished output imported to AE2.

The code here only verifies staging and matching. It performs no transfers and does not yet solve physical distribution to all buses and hatches.

## First in-game setup

1. Keep the existing ME Dual Interface and encoded test pattern. Attach a dedicated staging chest to its configured item-push face.
2. Attach two temporary empty fluid tanks to the interface's configured fluid delivery faces for the first 2-fluid recipe test. In GTNH 2.9, fluids are direct AE2 crafting ingredients. Verify how the Dual Interface actually fills these tanks before expanding. Do not assume the tanks receive the fluids in a fixed order.
3. Connect the Creative Computer to the Dual Interface as before. Place one or more OC Transposers so the computer can inspect the staging chest and tanks. They only need to see the source buffers for now.
4. Disable automatic extraction from staging while testing.
5. Run the scan and patterns commands with empty buffers, then request ONE Electric Motor (LuV) from AE2 and scan again. Do not request other Assembly Line recipes simultaneously.
6. When actual crafting is eventually enabled, the completed output must be imported into the main AE2 network.

## Installation

In the OpenOS terminal:

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/stage-probe-v1.lua /home/al-stage-v1.lua
    lua /home/al-stage-v1.lua patterns
    lua /home/al-stage-v1.lua scan

The scan prints component addresses, available sides, item stacks and fluid contents. It is read-only.

After identifying the buffers:

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/stage-config.example.lua /home/al-stage-config.lua
    edit /home/al-stage-config.lua
    lua /home/al-stage-v1.lua compare

Comparison yields candidate matches only, not an AE2 crafting request event. Use dedicated staging buffers with one recipe at a time.

## Physical routing later

Do not build a final transport system until the first delivery test succeeds. OC cables carry computer signals, not items or fluids. A Transposer can only transfer materials between adjacent inventories/tanks. We will verify one item and one fluid destination path before scaling up.

Data Sticks remain manual until the Data Bank is built. The Assembly Line selects a recipe by matching the ordered item and fluid inputs against the Data Sticks it can read.
