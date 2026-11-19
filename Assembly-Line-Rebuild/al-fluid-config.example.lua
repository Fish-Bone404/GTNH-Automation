-- GTNH 2.9 Assembly Line Fluid Router v1
-- Replace with exact fluid Transposer UUID shown by "probe".
-- Use physically separate single-fluid source tanks; output tanks must be EMPTY.
-- All side numbers are relative to the FLUID Transposer:
-- 0=down, 1=up, 2=north, 3=south, 4=west, 5=east
return {
  interfaceAddress = "0dd3d3f8-b915-42a9-be95-61dd1e95adf9",
  transposerAddress = "",   -- REQUIRED when item and fluid Transposers share the OC network
  sourceSides = {},         -- e.g. {1, 2} for AE2 Indalloy and Lubricant staging tanks
  outputSides = {},         -- e.g. {3, 4}; FIRST -> Hatch 1, SECOND -> Hatch 2
  patternSlots = 9,
  transferTimeout = 20,
  retryDelay = 0.25
}