-- GTNH 2.9 Assembly Line Manager v0.8.1
-- Uses existing /home/al-map-data.lua created by al-map-v07.lua.
-- Data Sticks: MANUAL. Does not start/stop machines or request AE2 crafts.
-- IMPORTANT: The staging chest must be dedicated to one AE2 crafting job at a time.
-- All item-source sides must show the SAME shared staging inventory.
-- Each mapped Transposer must touch BOTH source and target.
-- Items: pattern ordered inputs -> bus1, bus2, ... (slot 1 only).
-- Fluids: pattern ordered inputs -> hatch1, hatch2, ...
-- Check the physical NEI Assembly Line ingredient order BEFORE running.
local component = require("component")
local args = {...}
local cmd = args[1] or "status"
local mapPath = "/home/al-map-data.lua"
local configPath = "/home/almanager-config.lua"
local maxPatterns = 9
local interval = 3
local function msg(s) print("[AL] "..tostring(s)) end
local function tidy(s)
  return tostring(s or ""):lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
end
local function call(addr,method,...)
  local ok,a,b=pcall(component.invoke,addr,method,...)
  if not ok then return nil,tostring(a) end
  return a,b
end
local function mustCall(addr,method,...)
  local a,e=call(addr,method,...)
  if a==nil then error(method..": "..tostring(e),0) end
  return a
end
local function load(path)
  local ok,t=pcall(dofile,path)
  if ok and type(t)=="table" then return t end
  return nil
end
local config=load(configPath) or {}
if type(config.maxPatternSlots)=="number" and config.maxPatternSlots>=1 and
  config.maxPatternSlots<=36 then maxPatterns=math.floor(config.maxPatternSlots) end
local map=load(mapPath)
if not map then msg("Missing mapped Transposers at "..mapPath);return end
local function interface()
  if type(config.interfaceAddress)=="string" and config.interfaceAddress~="" then
    return config.interfaceAddress
  end
  local all={}
  for a in component.list("fluid_interface") do all[#all+1]=a end
  if #all~=1 then error("Expected one ME Dual Interface (fluid_interface), found "..#all,0) end
  return all[1]
end
local function connected(address,kind)
  for a in component.list(kind) do if a==address then return true end end
  return false
end
local function getRoute(label,kind)
  local r=map[label]
  if type(r)~="table" or r.kind~=kind or type(r.address)~="string" or
    type(r.source)~="number" or type(r.destination)~="number" or
    r.source==r.destination then
    return nil,label.." is not fully mapped; expected "..kind.." with source/destination sides"
  end
  if not connected(r.address,"transposer") then
    return nil,label.." Transposer is disconnected"
  end
  return r
end
local function sortedInputs(t)
  local idx={}
  for k,v in pairs(t or {}) do
    if type(k)=="number" and type(v)=="table" then idx[#idx+1]=k end
  end
  table.sort(idx)
  return idx
end
local function display(x)
  return type(x)=="table" and (x.label or x.displayName or x.fluidName or x.name) or "unknown"
end
local function parsePattern(slot,p)
  if type(p)~="table" then return nil end
  if type(p.inputs)~="table" or type(p.outputs)~="table" then return nil end
  if p.isCraftable==true then return nil end
  local result={slot=slot,items={},fluids={},bad=false,output=display(p.outputs[1])}
  if type(p.outputs[1])~="table" then result.bad=true end
  for _,k in ipairs(sortedInputs(p.inputs)) do
    local x=p.inputs[k]
    local n=tonumber(x.size)
    local a=tonumber(x.amount)
    local entry={patternSlot=k,stack=x,name=display(x),qty=n or a}
    if a and a>0 then
      entry.qty=a;result.fluids[#result.fluids+1]=entry
    elseif n and n>0 and n<=64 and n==math.floor(n) then
      entry.qty=n;result.items[#result.items+1]=entry
    else result.bad=true end
  end
  if #result.items==0 or #result.items>16 or #result.fluids>4 then result.bad=true end
  return result
end
local function patterns()
  local addr=interface()
  local all={}
  for i=1,maxPatterns do
    local raw,err=call(addr,"getInterfacePattern",i)
    if err and raw==nil then
      error("Dual Interface pattern "..i..": "..tostring(err),0)
    end
    local p=parsePattern(i,raw)
    if p then all[#all+1]=p end
  end
  return all
end
local function itemIdentity(x)
  if type(x)~="table" then return nil end
  local id=tidy(x.name)
  local damage=x.damage
  if id~="" and damage~=nil then return id.."#"..tostring(damage) end
  if id~="" then return id end
  local lab=tidy(display(x))
  if lab~="" then return "label:"..lab end
end
local function itemEquals(a,b)
  if type(a)~="table" or type(b)~="table" then return false end
  -- Don't auto-select NBT-sensitive inputs without a verified equality API.
  if a.hasTag==true or b.hasTag==true then return false end
  local ai,bi=tidy(a.name),tidy(b.name)
  if ai~="" and bi~="" then
    if ai~=bi then return false end
    if a.damage~=nil or b.damage~=nil then
      if a.damage==nil or b.damage==nil or a.damage~=b.damage then return false end
    end
    return true
  end
  return tidy(display(a))==tidy(display(b)) and tidy(display(a))~=""
end
local function fluidEquals(a,b)
  if type(a)~="table" or type(b)~="table" then return false end
  for _,aName in ipairs({a.name or "",a.label or "",a.fluidName or ""}) do
    if tidy(aName)~="" then
      for _,bName in ipairs({b.name or "",b.label or "",b.fluidName or ""}) do
        if tidy(aName)==tidy(bName) then return true end
      end
    end
  end
  return false
end
local function inventory(r,which)
  local side=r[which]
  local invSize=mustCall(r.address,"getInventorySize",side)
  if type(invSize)~="number" or invSize<1 then error("No item inventory at "..which,0) end
  -- getAllStacks is the fast bulk API; preserve original slot indices.
  local iter=mustCall(r.address,"getAllStacks",side)
  local ok,all=pcall(function()return iter.getAll() end)
  if not ok or type(all)~="table" then error("getAllStacks.getAll failed",0) end
  return all,invSize
end
local function srcRows(r)
  local all,size=inventory(r,"source")
  local rows={}
  for i=1,size do
    local x=all[i]
    if type(x)=="table" and tonumber(x.size or 0)>0 then
      rows[#rows+1]={slot=i,stack=x,count=tonumber(x.size)}
    end
  end
  return rows
end
local function emptyDestination(r,kind)
  if kind=="item" then
    local all,size=inventory(r,"destination")
    for i=1,size do
      local v=all[i]
      if type(v)=="table" and tonumber(v.size or 0)>0 then
        return false,"destination slot "..i.." occupied"
      end
    end
  else
    local count=mustCall(r.address,"getTankCount",r.destination)
    if type(count)~="number" or count<1 then return false,"fluid destination has no tanks" end
    for i=1,count do
      local v=call(r.address,"getFluidInTank",r.destination,i)
      if type(v)=="table" and tonumber(v.amount or 0)>0 then
        return false,"destination fluid tank "..i.." is occupied"
      end
    end
  end
  return true
end
local function availableFluid(r,need)
  local count=mustCall(r.address,"getTankCount",r.source)
  if type(count)~="number" or count<1 then return nil end
  for i=1,count do
    local v=call(r.address,"getFluidInTank",r.source,i)
    if fluidEquals(v,need.stack) and tonumber(v.amount or 0)>=need.qty then return i end
  end
end
local function requirements(p)
  local req={}
  for _,v in ipairs(p.items) do
    local key=itemIdentity(v.stack)
    if not key then return nil end
    req[key]=(req[key] or 0)+v.qty
  end
  return req
end
local function hasItems(p,rows)
  local req=requirements(p)
  if not req then return false end
  local totals={}
  for _,row in ipairs(rows) do
    local matched=false
    for _,entry in ipairs(p.items) do
      if itemEquals(row.stack,entry.stack) then
        matched=true
        local key=itemIdentity(entry.stack)
        totals[key]=(totals[key] or 0)+row.count
        break
      end
    end
    -- Block when staging contains other materials or multiple craft types.
    if not matched then return false end
  end
  -- Only accept a complete whole number of identical recipe batches.
  -- This keeps a partially delivered AE2 job from triggering another recipe
  -- when only some of the expected resources have arrived.
  local batches=nil
  for k,n in pairs(req) do
    local found=totals[k] or 0
    if found<n or found%n~=0 then return false end
    local count=found/n
    if batches and count~=batches then return false end
    batches=count
  end
  return batches~=nil
end
local function itemRoutePreflight(p)
  for i,x in ipairs(p.items) do
    local r,e=getRoute("bus"..i,"item")
    if not r then return false,e end
    local ok,reason=emptyDestination(r,"item")
    if not ok then return false,"bus"..i..": "..reason end
    local all,sz=srcRows(r)
    local total=0
    for _,v in ipairs(all) do
      if itemEquals(v.stack,x.stack) then total=total+v.count end
    end
    if total<x.qty then return false,"bus"..i.." does not see "..x.qty.." x "..x.name.." in its source" end
    local cap=call(r.address,"getSlotMaxStackSize",r.destination,1)
    if type(cap)=="number" and cap>0 and cap<x.qty then
      return false,"bus"..i.." cannot fit "..x.qty.." into slot 1"
    end
  end
  return true
end
local function fluidRoutePreflight(p)
  for i,x in ipairs(p.fluids) do
    local r,e=getRoute("hatch"..i,"fluid")
    if not r then return false,e end
    local ok,reason=emptyDestination(r,"fluid")
    if not ok then return false,"hatch"..i..": "..reason end
    if not availableFluid(r,x) then
      return false,"hatch"..i.." source lacks "..x.qty.." L "..x.name
    end
    local cap=call(r.address,"getTankCapacity",r.destination,1)
    if type(cap)=="number" and cap<x.qty then
      return false,"hatch"..i.." too small for "..x.qty.." L"
    end
  end
  return true
end
local function evaluate(p,rows)
  if p.bad then return false,"invalid or unsupported recipe pattern" end
  if not hasItems(p,rows) then return false,"items not complete or staging has unrelated items" end
  local ok,e=itemRoutePreflight(p)
  if not ok then return false,e end
  ok,e=fluidRoutePreflight(p)
  if not ok then return false,e end
  return true
end
local function selectReady()
  local r,e=getRoute("bus1","item")
  if not r then return nil,e end
  local sourceRows=srcRows(r)
  if #sourceRows==0 then return nil,"waiting for items in staging chest" end
  local candidates,why={},{}
  local list=patterns()
  if #list==0 then return nil,"no AE2 processing patterns found" end
  for _,p in ipairs(list) do
    local good,reason=evaluate(p,sourceRows)
    if good then candidates[#candidates+1]=p
    else why[#why+1]="slot "..p.slot..": "..reason end
  end
  if #candidates==1 then return candidates[1] end
  if #candidates>1 then
    return nil,"AMBIGUOUS: multiple recipes have a complete set of ingredients. No transfers."
  end
  return nil,"not ready | "..table.concat(why,"; ")
end
local function moveItem(r,entry)
  local remaining=entry.qty
  while remaining>0 do
    local rows=srcRows(r)
    local picked=nil
    for _,v in ipairs(rows) do
      if itemEquals(v.stack,entry.stack) then
        picked=v;break
      end
    end
    if not picked then error("Missing item during transfer: "..entry.name,0) end
    local amount=math.min(remaining,picked.count)
    local moved,e=call(r.address,"transferItem",r.source,r.destination,amount,picked.slot,1)
    if tonumber(moved)~=amount then
      error("PARTIAL ITEM TRANSFER "..entry.name.." | expected "..amount..
        ", moved "..tostring(moved)..", info="..tostring(e),0)
    end
    remaining=remaining-amount
  end
  msg("bus: "..entry.qty.." x "..entry.name)
end
local function moveFluid(r,entry)
  local remaining=entry.qty
  local attempts=0
  while remaining>0 do
    attempts=attempts+1
    if attempts>200 then error("Fluid transfer attempt limit reached",0) end
    local tank=availableFluid(r,{stack=entry.stack,qty=1})
    if not tank then error("Missing fluid while transferring "..entry.name,0) end
    local result,amount=call(r.address,"transferFluid",r.source,r.destination,remaining,tank)
    local moved=nil
    if result==true and type(amount)=="number" then moved=amount
    elseif type(result)=="number" then moved=result end
    if not moved or moved<=0 or moved>remaining then
      error("PARTIAL FLUID TRANSFER "..entry.name..", got "..tostring(result)..
        ", detail="..tostring(amount),0)
    end
    remaining=remaining-moved
  end
  msg("hatch: "..entry.qty.." L "..entry.name)
end
local function dispatch(p)
  msg("Moving one batch: "..p.output.." (pattern slot "..p.slot..")")
  for i,entry in ipairs(p.items) do
    local route=assert(getRoute("bus"..i,"item"))
    moveItem(route,entry)
  end
  for i,entry in ipairs(p.fluids) do
    local route=assert(getRoute("hatch"..i,"fluid"))
    moveFluid(route,entry)
  end
  msg("Batch loaded. Data Stick must already be available to the Assembly Line.")
end
local function one(dry)
  local p,reason=selectReady()
  if not p then return false,reason end
  if dry then
    msg("READY pattern "..p.slot..": "..p.output)
    for i,x in ipairs(p.items) do msg("  bus"..i.." -> "..x.qty.." x "..x.name) end
    for i,x in ipairs(p.fluids) do msg("  hatch"..i.." -> "..x.qty.." L "..x.name) end
    msg("All required destinations are empty. No transfers in check mode.")
  else dispatch(p) end
  return true,p.output
end
local function main()
  msg("Assembly Line Manager v0.8.1 | manual Data Sticks")
  if cmd=="status" then
    msg("Saved routes: "..mapPath)
    msg("Commands: check, once, run, status")
    msg("check=read-only, once=move one batch, run=automatic continuous")
    msg("Please verify recipe order and route destinations before 'run'.")
  elseif cmd=="check" or cmd=="once" then
    local ok,err=pcall(function()
      local success,reason=one(cmd=="check")
      if not success then msg(reason) end
    end)
    if not ok then msg("STOPPED: "..tostring(err)) end
  elseif cmd=="run" then
    msg("Auto-routing started. Press Ctrl+C to stop.")
    local lastReason=nil
    while true do
      local ok,success,reason=pcall(one,false)
      if not ok then
        msg("STOPPED on transfer or API error: "..tostring(success))
        msg("Inspect staging and all buses/hatches before restarting.")
        return
      end
      if success then
        lastReason=nil
      elseif reason~=lastReason then
        msg(reason);lastReason=reason
      end
      os.sleep(interval)
    end
  else
    msg("Unknown command: "..tostring(cmd))
  end
end
main()
