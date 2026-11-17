# Physical wiring proposal

## Phase A: pattern and research reader (do this first)

1. Place an **ME block Interface** on the main network and put Assembly Line processing patterns into it. Avoid using this Interface for active crafting until learning/probing is validated.
2. Position an **OpenComputers Adapter** so the Creative Computer can see that Interface as an `me_interface` component. Connect the Adapter to the Creative Computer by OC cable.
3. Place researched Assembly Line Data Sticks in a dedicated chest.
4. Place an **OpenComputers Transposer** against the research chest and connect it to the Creative Computer by OC cable.
5. Run `almanager probe`, record the component addresses and transposer side, and configure `/home/almanager-config.lua`.
6. Run `almanager scan`, then `almanager plan` and check the output. If it does not learn, collect the actual API data and adjust decoding.

## Phase B: physical item routing (NOT implemented yet)

- AE2 main network exports exactly one processing batch into a staging chest.
- An OC-controlled network of Transposers and small routing buffers reaches the 16 ULV Assembly Line Input Buses.
- A Transposer must be adjacent to inventories it accesses; OC cable connects control signals and does not move items.
- For a scalable build, use dedicated routing inventories or partitioned buffer chests so each bus can be reached without allowing ingredients to mix.
- Verify that each destination is empty or has an exact allowed residue before transfer.

## Phase C: physical fluid routing (NOT implemented yet)

- Feed fluid staging tanks from the main AE2 network's fluid handling.
- An OC Transposer can call `transferFluid(fromSide, toSide, quantity)` when adjacent source and destination tanks accept transfer.
- Use separate, controllable destination paths for the Assembly Line fluid Input Hatches. Do not assume one GT pipe can distinguish the four hatch positions.
- Verify fluid identity and quantity before and after moving it. Stop on partial transfer or incompatible hatches.
- Keep a fluid buffer for each concurrently needed fluid, or reconfigure an interface to supply them in sequence after clearing/confirming the previous fluid.

## Phase D: job control and outputs (NOT implemented yet)

- Main-network Pattern Provider or Interface receives processing patterns.
- Blocking and a machine-level lock must prevent mixed requests.
- Output Bus must feed the **main network** so AE2 crafting CPUs see job completion.
- No auto-start until manual tests succeed for repeated full stacks, repeated partial stacks, alternative coolant cells, and mixed fluids.

## Intended basic layout

```text
AE2 Main: Crafting Terminal + CPUs + patterns
                           |
                 ME Interface/Provider
                           |
           item chest + fluid staging tanks
                           |
                     OC Transposers
                           |
         16 Input Buses + up to 4 Fluid Hatches
                           |
                     Assembly Line
                           |
                    ME Import Bus
                           |
                        AE2 Main

Creative Computer -- OC cable -- Adapter -- ME Interface reader
                 `-- OC cable -- Transposers and other readers
```
