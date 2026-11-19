-- GTNH 2.9 Assembly Line Router v2, continuous mode
-- Updated to match the currently verified item Transposer layout.
-- YOU MUST attach an OpenComputers Adapter to the Assembly Line controller
-- and fill machineAddress if multiple gt_machine components are on the OC network.
return {
  interfaceAddress = "0dd3d3f8-b915-42a9-be95-61dd1e95adf9",
  transposerAddress = "6f22fcbe-28f4-4f78-b3fa-ef92c81348ce",
  machineAddress = "",

  sourceSide = 1,
  feederSide = 2,
  patternSlots = 9,

  stagingStableSeconds = 0.6,
  feederEmptySeconds = 0.2,
  feederDrainTimeout = 15,
  autoPollSeconds = 0.4,
  machinePollSeconds = 0.1,
  machineStartTimeout = 120,
  machineFinishTimeout = 3600,
  idleStableSeconds = 1.0
}