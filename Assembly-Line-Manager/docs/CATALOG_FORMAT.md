# Recipe catalog format

An entry represents the actual ordered GregTech recipe from a verified GTNH 2.9 source. A pattern is matched only if the output AND aggregated item/fluid quantities match exactly. Distinct repeated item stacks remain separate entries in itemBuses.

Format illustration ONLY, not a real recipe:

    return {
      format = 1,
      sourceVersion = "GTNH 2.9",
      recipes = {
        {
          output = "EXACT OUTPUT LABEL",
          itemBuses = {
            {name = "EXACT ITEM LABEL", amount = 36},
            {name = "EXACT ITEM LABEL", amount = 36}
          },
          fluidHatches = {
            {name = "EXACT FLUID LABEL", amount = 144}
          }
        }
      }
    }

Source importers must handle alternate ore dictionary materials, alternate circuits, dynamic recipes, and localized names, and must not produce partial ambiguous matches. The file catalog.lua is initially empty to prevent unsafe claims of coverage.

Relevant source:
https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.154/src/main/java/gregtech/loaders/postload/recipes/AssemblyLineRecipes.java
https://github.com/GTNewHorizons/NewHorizonsCoreMod/blob/2.9.0/src/main/java/com/dreammaster/gthandler/recipes/AssemblingLineRecipes.java
