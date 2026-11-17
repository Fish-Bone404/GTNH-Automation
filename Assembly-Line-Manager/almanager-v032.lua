-- Assembly Line Manager v0.3 for GTNH 2.9
-- Direct ME Dual Interface mode. READ ONLY.
-- Does not move materials, change patterns, activate machines, or touch data sticks.
local component=require("component")
local cfg={
  interfaceAddress="", -- Set this if more than one Dual Interface is connected.
  catalogPath="/home/almanager-catalog.lua",
  maxPatternSlots=9
}
local ok,custom=pcall(dofile,"/home/almanager-config.lua")
if ok and type(custom)=="table" then
  for k,v in pairs(custom) do cfg[k]=v end
end
local function addresses(kind)
  local a={}
  for address in component.list(kind) do a[#a+1]=address end
  table.sort(a)
  return a
end
local function interface()
  local addr=cfg.interfaceAddress
  if type(addr)~="string" or addr=="" then
    local found=addresses("fluid_interface")
    if #found==0 then return nil,"No ME Dual Interface detected (fluid_interface)" end
    if #found>1 then return nil,"Multiple Dual Interfaces detected. Set interfaceAddress in configuration." end
    addr=found[1]
  end
  -- component.methods may omit entries despite successful component.invoke.
  -- The read-only scan below directly invokes getInterfacePattern.
  return addr
end
local function sortedKeys(t)
  local keys={}
  if type(t)~="table" then return keys end
  for k in pairs(t) do keys[#keys+1]=k end
  table.sort(keys,function(a,b)
    if type(a)=="number" and type(b)=="number" then return a<b end
    return tostring(a)<tostring(b)
  end)
  return keys
end
local function itemName(x)
  if type(x)~="table" then return nil end
  return x.label or x.displayName or x.localizedName or x.name
end
local function inputType(x)
  -- In GTNH 2.9 OC getInterfacePattern, fluid entries expose 'amount'
  -- and items expose 'size'. Never silently assume an ambiguous entry is an item.
  local amount=tonumber(x.amount)
  local size=tonumber(x.size)
  if amount and amount>0 and x.id and x.name then return "fluid",amount end
  if amount and amount>0 and not x.damage then return "fluid",amount end
  if size and size>0 and not amount then return "item",size end
  return nil,nil
end
local function pattern(addr,slot)
  local success,raw=pcall(component.invoke,addr,"getInterfacePattern",slot)
  if not success then return nil,"API error: "..tostring(raw) end
  if raw==nil then return nil,nil end
  if type(raw)~="table" then return nil,"Unexpected pattern data" end
  if type(raw.inputs)~="table" or type(raw.outputs)~="table" then
    return nil,"Pattern does not expose inputs and outputs"
  end
  local outputs={}
  for _,k in ipairs(sortedKeys(raw.outputs)) do
    local x=raw.outputs[k]
    if type(x)=="table" then
      outputs[#outputs+1]={name=itemName(x),quantity=tonumber(x.size or x.amount),slot=k}
    end
  end
  local result={slot=slot,outputs=outputs,items={},fluids={},unknown={},craftable=raw.isCraftable}
  for _,k in ipairs(sortedKeys(raw.inputs)) do
    local x=raw.inputs[k]
    if type(x)=="table" then
      local kind,quantity=inputType(x)
      local row={slot=k,name=itemName(x),quantity=quantity,id=x.name,damage=x.damage}
      if kind=="item" then result.items[#result.items+1]=row
      elseif kind=="fluid" then result.fluids[#result.fluids+1]=row
      else result.unknown[#result.unknown+1]=row end
    end
  end
  return result
end
local function scan(verbose)
  local addr,err=interface()
  if not addr then print("ERROR: "..err);return end
  local slots=tonumber(cfg.maxPatternSlots) or 36
  if slots<1 or slots>128 then slots=9 end
  print("Assembly Line Manager v0.3.2 | READ ONLY")
  print("Dual Interface: "..addr)
  local found=0
  for slot=1,slots do
    local p,why=pattern(addr,slot)
    if why then
      print("Pattern slot "..slot.." ERROR: "..why)
    elseif p then
      found=found+1
      local output=p.outputs[1]
      print("Pattern slot "..slot..": "..(output and output.name or "unknown output")..
        " | "..#p.items.." item inputs | "..#p.fluids.." fluid inputs"..
        (#p.unknown>0 and (" | "..#p.unknown.." unknown inputs") or ""))
      if p.craftable==true then print("  WARNING: crafting pattern rather than processing") end
      if verbose then
        for _,x in ipairs(p.items) do
          print("  Item input slot "..tostring(x.slot)..": "..tostring(x.quantity).." x "..tostring(x.name))
        end
        for _,x in ipairs(p.fluids) do
          print("  Fluid input slot "..tostring(x.slot)..": "..tostring(x.quantity).." L "..tostring(x.name))
        end
        for _,x in ipairs(p.unknown) do
          print("  UNKNOWN input slot "..tostring(x.slot)..": "..tostring(x.name))
        end
        for _,x in ipairs(p.outputs) do
          print("  Output: "..tostring(x.quantity).." x "..tostring(x.name))
        end
      end
    end
  end
  print("Detected "..found.." processing-pattern slot(s). Nothing moved.")
  print("Data Stick selection and crafting are not enabled.")
end
local cmd=({...})[1] or "status"
if cmd=="probe" then
  print("Assembly Line Manager v0.3 | READ ONLY")
  for _,kind in ipairs({"fluid_interface","me_interface_terminal","adapter","transposer"}) do
    print(kind..":")
    local found=addresses(kind)
    if #found==0 then print("  none") end
    for _,a in ipairs(found) do print("  "..a) end
  end
elseif cmd=="scan" then scan(false)
elseif cmd=="plan" then scan(true)
elseif cmd=="catalog" then
  local ok,cat=pcall(dofile,cfg.catalogPath)
  if ok and type(cat)=="table" and type(cat.recipes)=="table" then
    print("Catalog entries: "..#cat.recipes)
  else
    print("Recipe catalog not available at "..cfg.catalogPath)
  end
elseif cmd=="status" then
  print("Assembly Line Manager v0.3.2, direct Dual Interface mode, READ ONLY")
  local addr,err=interface()
  print(addr and ("Connected: "..addr) or ("ERROR: "..err))
  print("Commands: probe, scan, plan, catalog, status")
else
  print("Commands: probe, scan, plan, catalog, status")
end
