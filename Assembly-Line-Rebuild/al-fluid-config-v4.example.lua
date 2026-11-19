-- GTNH 2.9 Assembly Line Manager v4
-- Source tanks receive full AE2 fluid requests. Output tanks feed numbered hatches.
-- Run: lua /home/al-assembly-manager.lua fluid-probe
-- Sides: 0=bottom, 1=top, 2=north, 3=south, 4=west, 5=east
return {
  transferTimeout=20,
  stations={
    {
      address="REPLACE_WITH_FLUID_TRANSPOSER_UUID",
      sources={1,2}, -- example source tanks receiving AE2 fluids, any order
      outputs={
        {hatch=1,side=3}, -- example tank feeding Hatch 1
        {hatch=2,side=4}  -- example tank feeding Hatch 2
      }
    }
  }
}
-- For more fluid inputs, add another station/Transposer with sources and
-- explicitly numbered outputs for hatches 3 and 4.
-- Source and output for one fluid MUST touch the SAME Transposer.
