-- Copy to /home/al-item-config.lua on your Creative Computer.
-- OpenComputers sides: 0 down, 1 up, 2 north, 3 south, 4 west, 5 east.
-- Probe first, then replace the -1 side numbers.
return {
  interfaceAddress = "38c686d2-2763-4b24-b341-3ad0ee199012",
  transposerAddress = "", -- Set the full UUID if more than one Transposer is connected
  sourceSide = -1,         -- staging chest on item Transposer
  feederSide = -1,         -- Ender IO distribution chest on item Transposer
  patternSlots = 9,
  stagingStableSeconds = 5,
  feederEmptySeconds = 1,
  feederDrainTimeout = 25,
  autoPollSeconds = 2
}