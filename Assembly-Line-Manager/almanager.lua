-- Assembly Line Manager 0.2 for GTNH 2.9
-- READ ONLY. Never moves fluids/items or changes patterns/redstone.
local component = require("component")
local cfg = {interfaceName="Assembly Line Manager", terminalAddress="",
  catalogPath="/home/almanager-catalog.lua"}
local ok, custom = pcall(dofile, "/home/almanager-config.lua")
if ok and type(custom)=="table" then
  for k,v in pairs(custom) do cfg[k]=v end
end
local function normalize(s)
  return tostring(s or ""):lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
end
local function addresses(kind)
  local found={}
  for address in component.list(kind) do found[#found+1]=address end
  table.sort(found)
  return found
end
local function terminal()
  local addr=cfg.terminalAddress
  if addr=="" then
    local found=addresses("me_interface_terminal")
    if #found==0 then return nil,"ME Interface Terminal is not connected to OC" end
    if #found>1 then return nil,"Set terminalAddress in config, multiple terminals found" end
    addr=found[1]
  end
  local ok,p=pcall(component.proxy,addr)
  if not ok or not p then return nil,"Could not connect to terminal "..tostring(addr) end
  if type(p.getInterfaces)~="function" then return nil,"getInterfaces API missing" end
  return p
end
local function interfaces()
  local p,e=terminal()
  if not p then return nil,e end
  local ok,arr=pcall(p.getInterfaces)
  if not ok or not arr then return nil,"getInterfaces failed: "..tostring(arr) end
  local okCount,n=pcall(function() return arr.count() end)
  if not okCount or type(n)~="number" then return nil,"Invalid terminal results" end
  local result={}
  for i=1,n do
    local success,x=pcall(function() return arr[i] end)
    if success and type(x)=="table" then result[#result+1]=x end
  end
  return result
end
local function printInterfaces()
  local list,e=interfaces()
  if not list then print("ERROR: "..e);return end
  print("Interfaces visible: "..#list)
  for _,x in ipairs(list) do
    local num=0
    for _,v in pairs(x.patterns or {}) do
      if type(v)=="table" then num=num+1 end
    end
    print("  "..tostring(x.name).." | patterns="..num)
  end
end
local function name(v)
  if type(v)=="string" then return v end
  if type(v)~="table" then return nil end
  return v.label or v.displayName or v.localizedName or v.name
end
local function num(v)
  v=tonumber(v)
  if not v or v<=0 or v~=math.floor(v) then return nil end
  return v
end
local function parsePattern(stack)
  if type(stack)~="table" or type(stack.inputs)~="table"
      or type(stack.outputs)~="table" then
    return nil,"Pattern inputs or outputs not exposed by API"
  end
  if stack.isCraftable==true then return nil,"Crafting pattern, not processing" end
  local result={output=name(stack.outputs[1]),items={},fluids={}}
  if not result.output then return nil,"Unknown output name" end
  for _,v in ipairs(stack.inputs) do
    local kind=type(v)=="table" and
      (v.isFluid==true or v.type=="fluid" or v.fluidName~=nil or v.fluid==true)
    local entry={name=name(v),
      amount=type(v)=="table" and num(v.size or v.amount or v.count) or nil}
    if not entry.name or not entry.amount then
      return nil,"Unknown input identity or count"
    end
    local target=kind and result.fluids or result.items
    target[#target+1]=entry
  end
  return result
end
local function signature(items,fluids)
  local data={}
  local function add(kind,x)
    local k=kind..":"..normalize(x.name)
    data[k]=(data[k] or 0)+x.amount
  end
  for _,x in ipairs(items) do add("i",x) end
  for _,x in ipairs(fluids) do add("f",x) end
  local keys={}
  for k in pairs(data) do keys[#keys+1]=k end
  table.sort(keys)
  local result={}
  for _,k in ipairs(keys) do result[#result+1]=k.."="..data[k] end
  return table.concat(result,"|")
end
local function catalog()
  local ok,cat=pcall(dofile,cfg.catalogPath)
  if not ok or type(cat)~="table" or cat.format~=1
      or type(cat.recipes)~="table" then
    return nil,"No valid GTNH 2.9 catalog at "..cfg.catalogPath
  end
  return cat
end
local function validEntries(t)
  if type(t)~="table" then return false end
  for _,x in ipairs(t) do
    if type(x)~="table" or not name(x) or not num(x.amount) then return false end
  end
  return true
end
local function matching(p,cat)
  local found={}
  for _,r in ipairs(cat.recipes) do
    if type(r)=="table" and type(r.output)=="string"
      and validEntries(r.itemBuses) and validEntries(r.fluidHatches)
      and #r.itemBuses<=16 and #r.fluidHatches<=4
      and normalize(r.output)==normalize(p.output)
      and signature(r.itemBuses,r.fluidHatches)==signature(p.items,p.fluids) then
      found[#found+1]=r
    end
  end
  if #found==1 then return found[1] end
  if #found>1 then return nil,"Multiple matching catalog recipes" end
  return nil,"No exact catalog match"
end
local function scan(verbose)
  local list,e=interfaces()
  if not list then print("ERROR: "..e);return end
  local target={}
  for _,x in ipairs(list) do
    if normalize(x.name)==normalize(cfg.interfaceName) then target[#target+1]=x end
  end
  if #target~=1 then
    print("ERROR: expected one Interface named "..cfg.interfaceName..", found "..#target)
    return
  end
  local cat,reason=catalog()
  if not cat then print("Catalog: "..reason) end
  local n,matched=0,0
  for slot,stack in pairs(target[1].patterns or {}) do
    if type(stack)=="table" then
      n=n+1
      local p,errorMessage=parsePattern(stack)
      if not p then
        print("Slot "..tostring(slot)..": NEEDS REVIEW: "..errorMessage)
      else
        print("Slot "..tostring(slot)..": "..p.output..
          " | "..#p.items.." item inputs | "..#p.fluids.." fluid inputs")
        local r,why=cat and matching(p,cat) or nil,"No catalog"
        if cat then r,why=matching(p,cat) end
        if r then
          matched=matched+1
          print("  VERIFIED CATALOG MATCH")
          if verbose then
            for i,x in ipairs(r.itemBuses) do
              print("    Bus "..i..": "..x.amount.." x "..x.name)
            end
            for i,x in ipairs(r.fluidHatches) do
              print("    Hatch "..i..": "..x.amount.." L "..x.name)
            end
          end
        else print("  REVIEW: "..tostring(why)) end
      end
    end
  end
  print("Read-only: "..matched.."/"..n.." patterns matched. Nothing moved.")
end
local function probe()
  print("Assembly Line Manager v0.2: component probe, READ ONLY")
  for _,kind in ipairs({"me_interface_terminal","fluid_interface",
    "me_interface","transposer","adapter"}) do
    print(kind..":")
    local list=addresses(kind)
    if #list==0 then print("  none") end
    for _,a in ipairs(list) do print("  "..a) end
  end
end
local cmd=({...})[1] or "status"
if cmd=="probe" then probe()
elseif cmd=="interfaces" then printInterfaces()
elseif cmd=="scan" then scan(false)
elseif cmd=="plan" then scan(true)
elseif cmd=="catalog" then
  local cat,e=catalog()
  print(cat and ("Catalog recipes: "..#cat.recipes) or ("ERROR: "..e))
elseif cmd=="status" then
  print("Assembly Line Manager v0.2, READ ONLY")
  print("Target ME interface: "..cfg.interfaceName)
  print("No routing or automatic crafting enabled")
else
  print("Commands: probe, interfaces, scan, plan, catalog, status")
end
