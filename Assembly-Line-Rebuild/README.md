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


## Stage 2: continuous item routing with machine completion interlock

File: al-item-router-v2.lua
Configuration example: al-item-config-v2.example.lua

V2 removes the MOVE/START confirmation in \`run\` mode. It makes the item staging wait 0.6 seconds instead of 5 seconds and waits for the feeder to stay empty 0.2 seconds instead of 1 second. The actual hardware may still have transfer latency; the router checks what is there rather than assuming instant deliveries.

**New required hardware**: one OpenComputers Adapter directly touching the **Assembly Line controller**, with OC cable back to the Creative Computer. This exposes the GregTech machine component \`gt_machine\`. The v2 software reads \`getWorkProgress()\` and \`getWorkMaxProgress()\` to verify the machine actually started and returned to idle before accepting the next recipe. Confirm that the detected gt_machine address belongs to the Assembly Line rather than another machine.

This feature is safer than a fixed arbitrary wait, but only proves the machine ran, not that the finished item reached AE2. A power failure or a forced machine stop could also return the machine to idle. Verify the output import path and do not use with overlapping/multiplied requests until those cases are added to the manager.

Use the updated configuration example or add these fields to your existing \`/home/al-item-config.lua\`:

    machineAddress = "", -- the real controller component address if multiple gt_machine components exist
    stagingStableSeconds = 0.6,
    feederEmptySeconds = 0.2,
    feederDrainTimeout = 15,
    autoPollSeconds = 0.4,
    machinePollSeconds = 0.1,
    machineStartTimeout = 120,
    machineFinishTimeout = 3600,
    idleStableSeconds = 1.0

Install:

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/al-item-router-v2.lua /home/al-item-router-v2.lua
    lua /home/al-item-router-v2.lua probe
    lua /home/al-item-router-v2.lua patterns
    lua /home/al-item-router-v2.lua status

After verifying the controller's gt_machine methods and the conduit routing:

    lua /home/al-item-router-v2.lua run

Leave \`run\` active. It is a foreground OpenOS program and will continue handling each one-batch crafting request automatically without pressing MOVE or RESET. You will need to start it again if the computer restarts, unless you separately configure a startup service.

The old \`once\` command is still available for a manual test. \`reset\` is reserved for recovery after a crash or unexpected failure. Do not reset an interrupted transfer without checking the actual inventories.

### V2 limitations

* Only one complete recipe's items may be in staging at a time. If AE2 sends 2× the ingredients or mixes simultaneous requests, the script refuses to route them.
* The computer cannot tell whether the finished item entered AE2 with only the current hardware. Future versions should optionally use a second verification sensor or AE2 status.
* If a recipe finishes before the controller's progress is observed, the script retains its safety lock and stops; it does not blindly send another batch.
* A current pattern with 16 item inputs and four fluids is supported; patternSlots refers to installed patterns, not ingredients.
* Fluid handling is still external. Direct tank-to-hatch routing must preserve each recipe's actual hatch order.

## Stage 3: bulk same-recipe item staging

File: `al-item-router-v3.lua`

This version can recognize 2, 10, or more **complete identical recipe sets** already delivered into the staging chest and release them **one set per observed Assembly Line machine cycle**. For example, when 10 pump ingredient sets are staged together, it releases ingredients for pump 1, waits for the machine to run and return to idle, then checks for 9 remaining sets before continuing. The recipe's repeated inputs are still transferred as separate ordered positions.

Install without overwriting v2:

    wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Rebuild/al-item-router-v3.lua /home/al-item-router-v3.lua
    lua /home/al-item-router-v3.lua check

Only enable unattended `run` after testing in-world and confirming correct fluid routing.

Important limitations: the manager cannot detect an AE2 job completion event or verify the output was imported into AE2. It observes that the actual Assembly Line started and returned to idle. It does not infer or support mixed recipes sharing the chest, and it cannot prove all the requested materials have finished arriving without extra signaling. It only recognizes exact whole-number multiples of ONE installed, approved processing pattern. If the incoming ingredients are partial, extra, or mixed, it waits or stops without routing. If AE2 adds ingredients during an active dispatch, the script stops with a safety journal.

**Fluid warning:** Ender IO fluid outputs must be filtered per destination to prevent splitting fluid between wrong hatches. For current pump/motor patterns, route Molten Indalloy 140 only to Hatch 1 and Lubricant only to Hatch 2. Higher-tier generic Ender IO wiki information may not match GTNH 2.9, particularly fluid insertion priority. Use white-listed fluid filters, not priority assumptions.

The v3 code is committed but has not been tested in Minecraft yet. Do not replace a working v2 setup until the fluid routing test succeeds.
