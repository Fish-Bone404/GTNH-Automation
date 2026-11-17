# Architecture and verified API surface

## Stage 1: Observe and learn safely

The manager is a dedicated program on the unused Creative OpenComputers computer near the Assembly Line. It **does not modify the separate Stocking Manager**.

The initial scope is to inspect patterns on a specified main-network ME block Interface and researched Data Sticks in a chest connected to a Transposer. It prints exact bus/hatch plans without placing any items or fluids.

### Upstream callbacks

GTNH OC includes the block ME Interface callback `getInterfacePattern(slot)`. Encoded patterns exposed through the OC ConverterPattern include `inputs`, `outputs`, and `isCraftable`.

OC's GregTech ConverterDataStick can expose `output`, `inputItems`, `inputFluids`, `eu`, and `time` on Assembly Line research Data Sticks. The converter currently supplies localized names for ingredients. **A GTNH 2.9 in-game test is needed to verify actual Lua table structure, fluid pattern representation, and whether registry identity is recoverable.**

Do not assume a chest alone preserves item bus order. The manager must cross-check the ordering against the researched Data Stick.

## Staged architecture

1. **Pattern catalog**: enumerate ME processing patterns from a specific Interface.
2. **Research library**: enumerate researched Data Sticks from a dedicated chest.
3. **Conservative matcher**: compare output and totals, decline ambiguous or unmapped recipes.
4. **Recipe plan**: store ordered positions from research data, including repeated ingredients.
5. **Job admission** (future): limit to one batch; verify staging is empty and reserve buffers.
6. **Item router** (future): control Transposers and verify transfer amounts to specific buses.
7. **Fluid router** (future): distinguish fluid identities and route exact amounts into specific hatches.
8. **Completion** (future): import output to main AE2, verify expected item and clear lock.
9. **Restart recovery** (future): inspect all in-flight state, never silently move ingredients after reboot.

## Why one-at-a-time jobs?

AE2 can send several batches of a processing pattern. A mixed chest may not reveal which request a batch belongs to, especially for recipes with identical aggregate ingredients. The implementation must gate request admission and verify the original pattern identity before it transfers anything.

## Pattern registration limitations

A pattern can be loaded at any point, but its decoded input ordering alone is not guaranteed to mirror Assembly Line input buses. A researched Data Stick is the authoritative ordered source. If multiple Data Sticks share the same total items and fluids or pattern ingredients use substitutions, the plan is flagged as ambiguous.

At present the matcher is a deliberately strict proof of concept. Do **not** add physical routing until in-game identification tests pass and all ambiguities are handled.

## Repository scope

All files are under `Assembly-Line-Manager/`. The existing root Stocking Manager files are unchanged.
