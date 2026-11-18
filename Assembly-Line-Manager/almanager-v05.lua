-- Assembly Line Manager v0.5 for GT New Horizons 2.9
-- Pattern/route planner; manual Data Sticks; READ ONLY for all world components.
-- Does NOT move items or fluids, request crafts, toggle machines or edit AE2 patterns.
local component=require("component")
local routesPath="/home/almanager-routes.lua"
local maxPatternSlots=9
local maxBuses=16
local maxHatches=4
local cfgOk,cfg=pcall(dofile,"/home/almanager-config.lua")
if cfgOk and type(cfg)=="table" then
  if type(cfg.interfaceAddress)=="string" and cfg.interfaceAddress~="" then
    -- Config override is read when resolving the interface below.
  end
  if type(cfg.maxPatternSlots)=="number" and cfg.maxPatternSlots>=1 and cfg.maxPatternSlots<=36 then
    maxPatternSlots=math.floor(cfg.maxPatternSlots)
  end
end

local function addresses(kind)
  local a={}
  for addr in component.list(kind) do a[#a+1]=addr end
  table.sort(a)
  return a
end
local function selectedInterface()
  local addr=cfgOk and type(cfg)=="table" and cfg.interfaceAddress or nil
  if type(addr)=="string" and addr~="" then return addr end
  local all=addresses("fluid_interface")
  if #all~=1 then
    return nil,"Expected one fluid_interface, found "..#all..". Configure interfaceAddress if multiple."
  end
  return all[1]
end
local function keys(t)
  local a={}
  if type(t)=="table" then for k in pairs(t) do a[#a+1]=k end end
  table.sort(a,function(x,y)
    if type(x)=="number" and type(y)=="number" then return x<y end
    return tostring(x)<tostring(y)
  end)
  return a
end
local function label(v)
  if type(v)~="table" then return nil end
  return v.label or v.displayName or v.name
end
local function classify(v)
  if type(v)~="table" then return nil,nil end
  if tonumber(v.amount) and tonumber(v.amount)>0 then return "fluid",tonumber(v.amount) end
  if tonumber(v.size) and tonumber(v.size)>0 then return "item",tonumber(v.size) end
  return nil,nil
end
local function readPattern(addr,slot)
  local ok,p=pcall(component.invoke,addr,"getInterfacePattern",slot)
  if not ok then return nil,"getInterfacePattern failed: "..tostring(p) end
  if p==nil then return nil end
  if type(p)~="table" or type(p.inputs)~="table" or type(p.outputs)~="table" then
    return nil,"Invalid pattern structure"
  end
  local result={slot=slot,items={},fluids={},unknown={},outputs={},craftable=p.isCraftable==true}
  for _,i in ipairs(keys(p.inputs)) do
    local v=p.inputs[i]
    local kind,qty=classify(v)
    if type(v)=="table" then
      local e={slot=i,name=label(v),qty=qty,registry=v.name,damage=v.damage,id=v.id,tagged=v.hasTag==true}
      if kind=="item" then result.items[#result.items+1]=e
      elseif kind=="fluid" then result.fluids[#result.fluids+1]=e
      else result.unknown[#result.unknown+1]=e end
    end
  end
  for _,i in ipairs(keys(p.outputs)) do
    local v=p.outputs[i]
    if type(v)=="table" then
      result.outputs[#result.outputs+1]={slot=i,name=label(v),qty=tonumber(v.size or v.amount),
        registry=v.name,damage=v.damage}
    end
  end
  return result
end
local function fingerprint(p)
  -- A change detector, not proof of a valid GTNH recipe or ingredient bus order.
  -- Includes pattern input position and item registry/damage, not only labels.
  local parts={"p",tostring(p.slot),"craft",tostring(p.craftable)}
  local function add(kind,a)
    for _,x in ipairs(a) do
      parts[#parts+1]=table.concat({kind,tostring(x.slot),tostring(x.registry),
        tostring(x.damage),tostring(x.qty),tostring(x.name)},"|")
    end
  end
  add("i",p.items); add("f",p.fluids); add("u",p.unknown); add("o",p.outputs)
  local s=table.concat(parts,";")
  local h=0
  for i=1,#s do h=(h*131+s:byte(i))%2147483647 end
  return string.format("%08x",h)
end
local function loadRoutes()
  local ok,r=pcall(dofile,routesPath)
  if ok and type(r)=="table" and type(r.patterns)=="table" then return r.patterns end
  return {}
end
local function routeCheck(p,rule)
  local issues={}
  local function fail(s) issues[#issues+1]=s end
  if not rule then
    fail("No route mapping saved. Use init-routes to create a draft.")
    return issues
  end
  if p.craftable then fail("AE2 crafting pattern, not a processing pattern") end
  if #p.outputs~=1 then fail("Expected exactly one output") end
  if #p.unknown>0 then fail("Pattern has unrecognized inputs") end
  if #p.items>maxBuses then fail("More than 16 item inputs") end
  if #p.fluids>maxHatches then fail("More than 4 fluid inputs") end
  local output=p.outputs[1]
  if not output or output.name~=rule.output then fail("Pattern output changed") end
  if fingerprint(p)~=rule.fingerprint then fail("Pattern fingerprint changed; remap after checking NEI") end
  local function checkMap(kind,arr,map,maxNum)
    local seen={}
    map=type(map)=="table" and map or {}
    for _,x in ipairs(arr) do
      local n=map[x.slot]
      if type(n)~="number" or n~=math.floor(n) or n<1 or n>maxNum then
        fail(kind.." input slot "..x.slot.." has no valid destination")
      elseif seen[n] then
        fail(kind.." destination "..n.." assigned more than once")
      else seen[n]=true end
    end
    for k in pairs(map) do
      local found=false
      for _,x in ipairs(arr) do if x.slot==k then found=true end end
      if not found then fail(kind.." mapping contains stale slot "..tostring(k)) end
    end
  end
  checkMap("Item",p.items,rule.itemBus,maxBuses)
  checkMap("Fluid",p.fluids,rule.fluidHatch,maxHatches)
  if rule.approved~=true then fail("Manual NEI/order verification is not marked approved") end
  return issues
end
local function showPlan(p,rule)
  print("\nPattern "..p.slot..": "..(p.outputs[1] and tostring(p.outputs[1].name) or "UNKNOWN"))
  print("Fingerprint: "..fingerprint(p).." | items "..#p.items.." | fluids "..#p.fluids)
  for _,x in ipairs(p.items) do
    local bus=type(rule)=="table" and type(rule.itemBus)=="table" and rule.itemBus[x.slot] or nil
    print(string.format("  Item pattern input %s -> Bus %s : %s x %s",tostring(x.slot),
      bus and bus>0 and tostring(bus) or "UNASSIGNED",tostring(x.qty),tostring(x.name)))
  end
  for _,x in ipairs(p.fluids) do
    local hatch=type(rule)=="table" and type(rule.fluidHatch)=="table" and rule.fluidHatch[x.slot] or nil
    print(string.format("  Fluid pattern input %s -> Hatch %s : %s L %s",tostring(x.slot),
      hatch and hatch>0 and tostring(hatch) or "UNASSIGNED",tostring(x.qty),tostring(x.name)))
  end
  for _,x in ipairs(p.unknown) do print("  UNKNOWN input "..tostring(x.slot).." : "..tostring(x.name)) end
  local issues=routeCheck(p,rule)
  if #issues==0 then print("  Route definitions validated, but transfers remain DISABLED.") else
    print("  Route NOT READY:")
    for _,s in ipairs(issues) do print("    "..s) end
  end
end
local function allPatterns(addr)
  local found={}
  for i=1,maxPatternSlots do
    local p,e=readPattern(addr,i)
    if e then print("Pattern "..i.." ERROR: "..e)
    elseif p then found[#found+1]=p end
  end
  return found
end
local function initRoutes(addr)
  local handle=io.open(routesPath,"r")
  if handle then
    handle:close()
    print("REFUSED: "..routesPath.." exists. No configuration overwritten.")
    return
  end
  local patterns=allPatterns(addr)
  local lines={
    "-- Generated by Assembly Line Manager v0.5. Edit destination numbers after checking GTNH NEI.",
    "-- Bus 1 = first Assembly Line input bus, Hatch 1 = first recipe fluid input hatch.",
    "-- The generated 0 values are NOT actual destinations. Duplicate ingredients need separate buses.",
    "-- Do not mark approved=true until the actual NEI recipe and physical layout are checked.",
    "return { patterns = {"
  }
  for _,p in ipairs(patterns) do
    local out=p.outputs[1] and p.outputs[1].name or ""
    lines[#lines+1]=string.format("  [%d] = {",p.slot)
    lines[#lines+1]="    output = "..string.format("%q",out)..","
    lines[#lines+1]="    fingerprint = "..string.format("%q",fingerprint(p))..","
    lines[#lines+1]="    approved = false,"
    lines[#lines+1]="    itemBus = {"
    for _,x in ipairs(p.items) do
      lines[#lines+1]=string.format("      [%s] = 0, -- %s x %s",tostring(x.slot),tostring(x.qty),tostring(x.name))
    end
    lines[#lines+1]="    },"
    lines[#lines+1]="    fluidHatch = {"
    for _,x in ipairs(p.fluids) do
      lines[#lines+1]=string.format("      [%s] = 0, -- %s L %s",tostring(x.slot),tostring(x.qty),tostring(x.name))
    end
    lines[#lines+1]="    },"
    lines[#lines+1]="  },"
  end
  lines[#lines+1]="} }"
  local w,err=io.open(routesPath,"w")
  if not w then print("ERROR saving route draft: "..tostring(err));return end
  w:write(table.concat(lines,"\n").."\n")
  w:close()
  print("Saved UNAPPROVED route draft: "..routesPath)
  print("Only a local configuration file was created. No machine changed.")
end
local function ioProbe()
  print("GTNH 2.9 I/O capability survey | READ ONLY")
  local types={"fluid_interface","me_inputbus","me_inputhatch","transposer","gt_machine","redstone"}
  for _,kind in ipairs(types) do
    local a=addresses(kind)
    print(kind..": "..#a)
    for _,addr in ipairs(a) do
      local name=""
      if kind=="gt_machine" then
        local ok,v=pcall(component.invoke,addr,"getName")
        name=ok and (" | name="..tostring(v)) or " | name unavailable"
      end
      print("  "..addr..name)
      local methods=component.methods(addr) or {}
      local found={}
      for key in pairs(methods) do
        if kind=="fluid_interface" or kind=="me_inputbus" or kind=="me_inputhatch" then
          if key:find("^get") or key:find("^is") or key:find("^has") or key:find("^set") then
            found[#found+1]=key
          end
        end
      end
      table.sort(found)
      if #found>0 then print("  API methods: "..table.concat(found,", ")) end
    end
  end
  print("No inventory transfers, writes, or redstone actions were made.")
end

local cmd=({...})[1] or "status"
if cmd=="io" or cmd=="probe" then ioProbe(); return end
print("Assembly Line Manager v0.5 | MANUAL DATA STICKS | NO TRANSFERS")
local addr,reason=selectedInterface()
if not addr then print("ERROR: "..reason);return end
print("ME Dual Interface: "..addr)
if cmd=="init-routes" then initRoutes(addr);return end
if cmd=="status" then
  print("Commands: patterns, plan [slot], routes, init-routes, io, status")
  print("Request detection: not connected; item and fluid routing: DISABLED")
  return
end
local patterns=allPatterns(addr)
local saved=loadRoutes()
if cmd=="patterns" then
  for _,p in ipairs(patterns) do
    print("Slot "..p.slot..": "..(p.outputs[1] and tostring(p.outputs[1].name) or "UNKNOWN")..
      " | "..#p.items.." item inputs | "..#p.fluids.." fluid inputs")
  end
  print("Patterns are templates, NOT active crafting requests.")
elseif cmd=="plan" or cmd=="routes" then
  local chosen=tonumber(({...})[2])
  if cmd=="plan" and chosen and chosen~=math.floor(chosen) then print("Invalid slot"); return end
  local count=0
  for _,p in ipairs(patterns) do
    if cmd=="routes" or not chosen or p.slot==chosen then
      showPlan(p,saved[p.slot]); count=count+1
    end
  end
  if count==0 then print("No patterns found for this slot.") end
  print("No transfers performed. Data Sticks remain entirely manual.")
else
  print("Unknown command. Use: patterns, plan [slot], routes, init-routes, io, status")
end
