# Assembly Line Manager

An early-stage OpenComputers and AE2 automation project for the GT New Horizons 2.9 Assembly Line.

**Goal:** Request crafts from the existing main AE2 Crafting Terminal while a dedicated Creative OpenComputers computer learns Assembly Line recipes and eventually routes exact quantities to the correct buses and hatches. Repeated ingredients should work without renaming.

**Important GTNH 2.9 finding:** New Assembly Line Data Sticks store the recipe output but not ordered ingredient lists. The existing read-only learner cannot derive input positions from these sticks alone. A version-matched recipe catalog or another reliable source is needed before automatic learning can work. See [Data Access Verification](docs/DATA_ACCESS_VERIFICATION.md).\n\n**Current state: research prototype, read-only. It does not move items or fluids and does not process crafting jobs yet.** Do not rely on this build for unattended crafting. The separate Stocking Manager in the parent repository is unaffected.

## Why learning needs more than a chest

An AE2 processing pattern exposes required input quantities but a staging chest loses the original recipe and bus order. The manager therefore compares:
1. Encoded processing patterns read through an attached ME Interface.
2. Researched Assembly Line Data Sticks read through an OpenComputers Transposer.

The 2.9 researched Data Stick does **not** supply ordered Assembly Line item and fluid inputs; it identifies an output for the GT recipe lookup. The program cannot reliably learn bus order without a recipe catalog or another trusted source. Automatic matching is currently disabled for these incomplete sticks. Ambiguous or unreadable data is rejected and displayed instead of being guessed.

**Important:** OpenComputers' GTNH Data Stick converter currently exposes localized display names rather than canonical registry IDs. This prototype checks them conservatively, and the exact 2.9 output formats still need an in-game probe. Full hands-free learning is a design goal, not yet proven on a running server.

## Initial installation

Use your **dedicated Creative Computer**, not the computer running Stocking Manager. Download files to the in-game OpenOS machine using the following commands:

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Manager/almanager.lua /home/almanager.lua
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/Assembly-Line-Manager/config.example.lua /home/almanager-config.lua
```

The `wget` commands install only the safe, read-only prototype. No startup service is installed.

## First commands

```sh
almanager probe
almanager status
almanager scan
almanager recipes
almanager plan
almanager help
```

If OpenOS cannot find `almanager`, run `cd /home` first and then `almanager.lua probe`.

1. Run `probe` to enumerate ME Interfaces, Transposers, and their relevant methods.
2. Edit `/home/almanager-config.lua` to supply the correct ME Interface address and the Data Stick Transposer address and side.
3. Run `scan` to observe the interface and Data Stick metadata. Current 2.9 Data Sticks cannot provide ordered input lists, so expect a useful warning instead of a saved routing plan.
4. Run `recipes` and `plan` to inspect what it learned.

The Data Stick chest must be visible to a Transposer. The configured ME Interface must be a **block Interface** with the patterns installed and accessible through the OC adapter. These requirements will be validated before physical routing is developed.

## Architecture

- **AE2 main network:** retains crafting CPUs, terminal, recipe patterns, ingredient sources, and output import.
- **Manager / Creative Computer:** reads patterns, learns recipes, tracks jobs and eventually schedules routing.
- **Staging chest and fluid buffers:** isolate one recipe batch so another craft cannot intermingle.
- **OpenComputers Transposers:** proposed exact item and fluid transfers.
- **Assembly Line inputs:** up to 16 item positions and 4 fluid positions.
- **Research library:** chest containing researched Data Sticks, with research kept available to the Assembly Line.

See [Architecture](docs/ARCHITECTURE.md) and [Wiring](docs/WIRING.md).

## Known constraints

- Reading encoded AE2 patterns and Data Stick metadata in the *specific GTNH 2.9 release* needs confirmation through `probe` and `scan`.
- Some patterns encode substitutes or fluid ingredients differently; if normalized inputs do not match exactly, learning stops for that recipe.
- If multiple Data Sticks match the same pattern, the manager flags an ambiguity rather than selecting a random recipe.
- The main AE2 network must still use a processing pattern. Returning the correct output to AE2 is what finishes the crafting request.
- Pattern-only registration cannot safely distinguish two different orders that use exactly the same aggregate ingredients unless the Data Stick or an additional job identifier resolves the ambiguity.
- Recipe matching is separate from crafting queueing, fluid routing, redstone locking, power, and failure recovery. Those are future phases.

## Upstream GTNH references

- [OC Interface pattern API](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverBlockInterface.scala)
- [OC AE2 pattern converter](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/ConverterPattern.scala)
- [OC Assembly Line Data Stick converter](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/gregtech/ConverterDataStick.scala)

## Development stages

1. Probe real 2.9 component methods and metadata.
2. Decode and learn patterns and researched Data Sticks without modifying inventories.
3. Validate exact item and fluid positions with mock data and in-game dry runs.
4. Add job locking, staging verification, transposer routing, and recovery.
5. Add output monitoring and AE2 crafting completion.
6. Add safe auto-start after several successful supervised crafts.
