# GTNH 2.9 Assembly Line Rebuild

Clean rebuild. Old bus-by-bus Transposer mappings and old manager scripts are not used.

## Stage 1: single-Transposer item router v1.0

Installed scripts:
- al-item-router-v1.lua: item-only release, staged recipe matching, pattern order review, one-batch safety lock
- al-item-config.example.lua: configuration template for the new item layout
- stage-probe-v1.lua: separate read-only buffer diagnostic
- stage-config.example.lua: example config for the read-only diagnostic

### In-world layout

ME Dual Interface -> item staging chest -> adjacent OpenComputers item Transposer -> adjacent Ender IO distribution chest -> Ender IO Item Conduits -> ULV Assembly Line Input Buses.

The Transposer must touch BOTH chests on two distinct sides. It must also be wired to the Creative Computer. Its OC wiring does not move items.

Ender IO conduit output connections must be priority ordered from Bus 1 to Bus 16. Proposed filter arrangement is an Existing Item Filter in blacklist mode with no frozen snapshot at every insert connection; validate this setup in-game. Use 15 Speed Upgrades on the conduit extracting from the distribution chest. Disable Round Robin for priority routing.

WARNING: A distribution chest becoming empty does NOT prove items reached the correct buses. Test in-world and manually inspect each numbered bus before using this on valuable components. A recipe needing repeated ingredients or 64 items in one input must be tested.

Fluid transport is intentionally not implemented in this program. Build it independently using tanks and verify hatch order. Data Sticks remain manual.

### Install on OpenOS

Run in the shell, not interactive Lua:

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/al-item-router-v1.lua /home/al-item-router.lua
    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/al-item-config.example.lua /home/al-item-config.lua

Identify the item Transposer address and connected inventory side numbers:

    lua /home/al-item-router.lua probe
    edit /home/al-item-config.lua

Set sourceSide to the side touching the item staging chest, feederSide to the side touching the Ender IO distribution chest. The example includes a known Dual Interface address; if that block has been replaced, update its address. If the fluid Transposer is also connected, set the item transposer's UUID in transposerAddress.

Show installed AE2 patterns and their item position order:

    lua /home/al-item-router.lua patterns

Before approving a pattern, compare every numbered item and fluid position against NEI's Assembly Line recipe. For example, to approve pattern slot 1:

    lua /home/al-item-router.lua approve 1

Manually type APPROVE. Approval is invalidated if the pattern changes.

Stage exactly ONE recipe batch of items. Do not mix other AE2 requests in the staging chest. Then run:

    lua /home/al-item-router.lua check

This is read-only. It will refuse to match if there is an extra item, a missing item, an unsupported NBT item, an ambiguous pair of patterns, or an unapproved recipe order.

After inspecting the plan and confirming the Ender IO inputs are empty, run:

    lua /home/al-item-router.lua once

Manually type MOVE to authorize one item-only batch. The router transfers the exact per-position item amount to the feeder chest, waits for the feeder chest to empty, and then releases the next position. It leaves a persistent safety lock so it will NOT start another batch unobserved. It does not verify destination bus occupancy and does not route fluids.

For a one-batch waiting mode that automatically starts after a full approved batch appears in staging, use:

    lua /home/al-item-router.lua auto

Type START. This still stops after ONE batch and leaves a lock; it is not a continuous service.

See the lock status:

    lua /home/al-item-router.lua status

After verifying the previous craft actually finished and all relevant inventories are clear:

    lua /home/al-item-router.lua reset

Type RESET only when safe. A failed or interrupted transfer also leaves the lock in place to prevent silent retries.

### Tested and untested

Tested offline in a simulated OpenComputers environment:
- Lua syntax
- Recipe parsing
- Exact staged-item match
- Separately releasing duplicate 64-wire ingredients
- One-batch lock and status behavior

NOT verified in-game:
- Ender IO filter and conduit delivery priority
- Actual GTNH OC item stack identity fields
- Correct alignment of AE2 pattern order with Assembly Line NEI recipe order
- Fluid distribution
- Back-to-back multi-request operation

Any discrepancy should be diagnosed with probe and check before another transfer. Never auto-enable unattended multi-batch crafting from this version.
