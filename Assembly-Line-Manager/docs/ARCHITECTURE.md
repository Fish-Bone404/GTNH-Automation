# GTNH 2.9 design and safeguards

Data Access Hatch or Data Bank: enables researched recipes for GregTech; OpenComputers does not need to read it.

Main AE2: holds processing patterns and receives normal crafting requests. The target block ME Dual Interface is named Assembly Line Manager.

OpenComputers: uses an OC Adapter on the ME Interface Terminal. The terminal driver can list connected visible interfaces and their encoded patterns, including the inputs and output fields. Dual Interface direct driver does not offer getInterfacePattern.

Recipe catalog: version-matched ordered entries determine the bus and hatch position. Old Data Stick input parsing does not work on ordinary 2.9 research Data Sticks. Program denies unmatched or ambiguous recipes.

Future staging: items in a chest, fluids in 4 independently managed buffers; only one batch released to hardware at a time.

Future router: connected Transposers send exact item quantities to individual buses and fluids to individual input hatches. OC cable only carries control signals.

Future completion: Assembly Line outputs are imported back into main AE2. Persistent job state and controlled startup must prevent duplicate crafts or incorrect transfers after server restarts.

Current v0.2: only probe, interfaces, scan, plan and status; catalog.lua is intentionally empty and all physical transfers are disabled. The first in-game test must verify that ME Interface Terminal getInterfaces exposes the actual Dual Interface patterns in this 2.9 build.

Sources:
https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/integration/appeng/DriverPartInterfaceTerminal.scala
https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/gregtech/api/util/AssemblyLineUtils.java
