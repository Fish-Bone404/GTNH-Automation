# First physical connections

                       MAIN AE2 NETWORK
                       |             |
             ME Dual Interface   ME Interface Terminal
           name: Assembly Line       |
                Manager          OC Adapter
                                     |
                                  OC Cable
                                     |
                            Creative Computer

Use this layout for the first read-only test. The computer does not need to touch the Dual Interface directly if the Interface Terminal lists its patterns.

Later, after catalog generation, physical routing and locking:

ME Dual Interface -> staging chest and 4 fluid tanks -> Transposers and routing buffers -> Assembly Line item buses and input hatches
Assembly Line Output Bus -> ME Import Bus -> main AE2 network

For researched recipes: place sticks in the Assembly Line Data Access Hatch at LuV. Later, Data Bank -> TecTech data pipe -> Assembly Line Data Input Hatch; no OC recipe reader needed at the bank.

WARNING: A Transposer must be physically adjacent to the inventories or tanks that it transfers between. OC cables transmit instructions, not items or fluids. The exact routing topology and fluid export behavior need in-game tests before enabling any craft.
