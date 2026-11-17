-- Assembly Line Manager: research library matching diagnostic v0.4
-- READ ONLY: no transfers, changes to AE2 patterns, or machine activation.
local component = require("component")
local ifaceList, transList = {}, {}
for a in component.list("fluid_interface") do ifaceList[#ifaceList+1] = a end
for a in component.list("transposer") do transList[#transList+1] = a end
table.sort(ifaceList); table.sort(transList)
local HATCH_SIDE, CHEST_SIDE = 2, 3
local function normalize(s)
  if type(s)~="string" then return "" end
  return s:lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
end
local function safeRead(addr,slot)
  local ok,v=pcall(component.invoke,addr,"getInterfacePattern",slot)
  if not ok then print("  Pattern slot "..slot.." API error: "..tostring(v)); return nil end
  return v
end
print("Assembly Line Manager: library match v0.4 | READ ONLY")
if #ifaceList~=1 or #transList~=1 then
  print("ERROR: expected one fluid_interface and one transposer.")
  print("Found "..#ifaceList.." fluid_interface and "..#transList.." transposer.")
  print("Do not use this diagnostic with multiple devices.")
  return
end
local iface=ifaceList[1]
local t=component.proxy(transList[1])
local okChest,chestSize=pcall(t.getInventorySize,CHEST_SIDE)
local okHatch,hatchSize=pcall(t.getInventorySize,HATCH_SIDE)
if not okChest or type(chestSize)~="number" or not okHatch or type(hatchSize)~="number" then
  print("ERROR: expected readable storage on side 3 and hatch on side 2.")
  print("Chest: "..tostring(chestSize).." Hatch: "..tostring(hatchSize))
  return
end
print("Chest side "..CHEST_SIDE.." slots="..chestSize.."; hatch side "..HATCH_SIDE.." slots="..hatchSize)
local library={}
local all=0
for slot=1,chestSize do
  local ok,item=pcall(t.getStackInSlot,CHEST_SIDE,slot)
  if not ok then print("WARNING: chest slot "..slot.." read failed") end
  if ok and type(item)=="table" then
    all=all+1
    local output=item.output
    print("Chest slot "..slot..": "..tostring(item.label).." | output="..tostring(output))
    if normalize(output)~="" then
      local key=normalize(output)
      library[key]=library[key] or {}
      library[key][#library[key]+1]={slot=slot,label=item.label,output=output,tag=item.hasTag}
    end
  end
end
print("Research items with output names: "..all.." occupied slots scanned")
local found=0
for slot=1,9 do
  local pattern=safeRead(iface,slot)
  if type(pattern)=="table" then
    found=found+1
    local output=type(pattern.outputs)=="table" and pattern.outputs[1] or nil
    local outputName=type(output)=="table" and (output.label or output.displayName or output.name) or nil
    print("Pattern slot "..slot..": "..tostring(outputName))
    if not outputName then
      print("  REVIEW: pattern output not readable")
    else
      local matches=library[normalize(outputName)] or {}
      if #matches==0 then
        print("  NO RESEARCH ITEM IN CHEST. Check hatch or other storage.")
      elseif #matches==1 then
        print("  CANDIDATE: chest slot "..matches[1].slot.." ("..tostring(matches[1].label)..")")
        print("  UNVERIFIED: output-name match only; no recipe or NBT validation")
      else
        print("  AMBIGUOUS: "..#matches.." research items share this output:")
        for _,m in ipairs(matches) do print("    chest slot "..m.slot) end
        print("  No automatic selection allowed")
      end
    end
  end
end
print("Scanned "..found.." encoded pattern(s). Nothing moved.")
