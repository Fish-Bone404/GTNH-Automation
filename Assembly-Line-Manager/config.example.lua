-- Copy to /home/almanager-config.lua and fill in device addresses after running:
--   almanager probe
--
-- OpenComputers sides: bottom=0 top=1 back=2 front=3 right=4 left=5
-- Use the "sides" library for named directions when editing settings.
return {
  interfaceAddress = "",       -- OC component address for a block ME Interface with processing patterns.
  stickTransposerAddress = "", -- OC component address for the Transposer adjacent to the research Data Stick chest.
  stickChestSide = 2,          -- Side of the research chest as seen by the Transposer.
  patternSlots = 9,            -- Accessible Interface pattern slots; increase only after proving API support.
  maxItemBuses = 16,
  maxFluidHatches = 4,
  statePath = "/home/almanager-recipes.db",
  diagnosticPath = "/home/almanager-probe.log",
  dryRun = true,               -- Physical movement is intentionally not implemented.
}
