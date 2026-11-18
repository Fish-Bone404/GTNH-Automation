-- GTNH 2.9 Assembly Line direct transfer tester v0.6
-- Data Sticks are always manual. This tool tests one item bus or fluid hatch
-- at a time; it does not queue crafts or automatically route full recipes.
-- A Transposer must touch BOTH the source container and the destination.
local component=require("component")
local argv={...}
local command=argv[1] or "help"

local function getAddr(kind,prefix)
  local found={}
  for a in component.list(kind) do
    if not prefix or a:sub(1,#prefix)==prefix then found[#found+1]=a end
  end
  table.sort(found)
  if #found~=1 then return nil,kind..": expected 1 matching component, found "..#found end
  return found[1]
end
local function safe(addr,method,...)
  local ok,a,b=pcall(component.invoke,addr,method,...)
  if not ok then return nil,tostring(a) end
  return a,b
end
local function num(s,min,max)
  local n=tonumber(s)
  if not n or n~=math.floor(n) or n<min or n>max then return nil end
  return n
end
local function name(x)
  if type(x)~="table" then return nil end
  return x.label or x.displayName or x.name
end
local function normalized(s)
  return tostring(s or ""):lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
end
local function itemMatches(a,b)
  if not a or not b then return false end
  local an=normalized(a.name);local bn=normalized(b.name)
  -- GTNH has registry IDs and damage for items; prefer them when present.
  if an~="" and bn~="" then
    if an~=bn then return false end
    if a.damage~=nil and b.damage~=nil and a.damage~=b.damage then return false end
    return true
  end
  return normalized(name(a))~="" and normalized(name(a))==normalized(name(b))
end
local function fluidMatches(a,b)
  if not a or not b then return false end
  local namesA={a.name,a.label,a.fluidName}
  local namesB={b.name,b.label,b.fluidName}
  for _,x in pairs(namesA) do
    for _,y in pairs(namesB) do
      if normalized(x)~="" and normalized(x)==normalized(y) then return true end
    end
  end
  return false
end
local function getPattern(slot)
  local addr,e=getAddr("fluid_interface")
  if not addr then return nil,e end
  local p,err=safe(addr,"getInterfacePattern",slot)
  if err and not p then return nil,err end
  if not p or type(p.inputs)~="table" then return nil,"No readable pattern in slot "..slot end
  return p
end
local function entries(p,kind)
  local list={}
  local keys={}
  for k in pairs(p.inputs) do
    if type(k)=="number" then keys[#keys+1]=k end
  end
  table.sort(keys)
  for _,k in ipairs(keys) do
    local v=p.inputs[k]
    if type(v)=="table" then
      if kind=="item" and tonumber(v.size) and not tonumber(v.amount) then
        list[#list+1]={slot=k,stack=v,quantity=tonumber(v.size)}
      elseif kind=="fluid" and tonumber(v.amount) and tonumber(v.amount)>0 then
        list[#list+1]={slot=k,stack=v,quantity=tonumber(v.amount)}
      end
    end
  end
  return list
end
local function patterns()
  local addr,e=getAddr("fluid_interface")
  if not addr then print("ERROR: "..e);return end
  for slot=1,9 do
    local p=safe(addr,"getInterfacePattern",slot)
    if type(p)=="table" then
      local out=type(p.outputs)=="table" and p.outputs[1] or nil
      print("Pattern "..slot..": "..tostring(name(out)))
      for i,v in ipairs(entries(p,"item")) do
        print("  Item "..i..", pattern position "..v.slot..": "..v.quantity.." x "..tostring(name(v.stack)))
      end
      for i,v in ipairs(entries(p,"fluid")) do
        print("  Fluid "..i..", pattern position "..v.slot..": "..v.quantity.." L "..tostring(name(v.stack)))
      end
    end
  end
end
local function probe()
  print("Assembly Line direct transfer tester v0.6 | READ ONLY PROBE")
  local count=0
  for a in component.list("transposer") do
    count=count+1
    print("\nTransposer "..a)
    for side=0,5 do
      local inv=safe(a,"getInventorySize",side)
      local tanks=safe(a,"getTankCount",side)
      if type(inv)=="number" or (type(tanks)=="number" and tanks>0) then
        local invName=safe(a,"getInventoryName",side)
        print("  Side "..side..": "..(type(inv)=="number" and ("inventory="..inv) or "no inventory")
          .." | tanks="..tostring(tanks).." | "..tostring(invName or ""))
        if type(tanks)=="number" then
          for k=1,math.min(tanks,4) do
            local fluid=safe(a,"getFluidInTank",side,k)
            if type(fluid)=="table" then
              print("    Tank "..k..": "..tostring(name(fluid)).." ("..tostring(fluid.amount or 0).." L)")
            end
          end
        end
      end
    end
  end
  print("\nTransposers detected: "..count)
  print("No materials moved.")
end
local function getRequest(kind)
  local slot=num(argv[2],1,9)
  local index=num(argv[3],1,16)
  local addr,e=getAddr("transposer",argv[4])
  local from=num(argv[5],0,5)
  local to=num(argv[6],0,5)
  if not slot or not index or not addr or from==nil or to==nil or from==to then
    print("ERROR: expected <pattern-slot> <ingredient-index> <transposer-address-prefix> <source-side> <destination-side>")
    if e then print(e) end
    return
  end
  local p,err=getPattern(slot)
  if not p then print("ERROR: "..err);return end
  local options=entries(p,kind)
  local request=options[index]
  if not request then print("ERROR: recipe has no "..kind.." ingredient number "..index);return end
  return addr,from,to,request
end
local function checkItem(doMove)
  local addr,from,to,r=getRequest("item")
  if not addr then return end
  local n=r.quantity
  if n<1 or n>64 or n~=math.floor(n) then print("BLOCKED: item batch does not fit one bus slot");return end
  local srcSize=safe(addr,"getInventorySize",from)
  local dstSize=safe(addr,"getInventorySize",to)
  if type(srcSize)~="number" or type(dstSize)~="number" then
    print("BLOCKED: Transposer must touch both source inventory and input bus");return
  end
  if srcSize==dstSize and from~=to then
    -- Equal sizes are valid; no assumption about which inventory is the bus.
  end
  for i=1,dstSize do
    local existing=safe(addr,"getStackInSlot",to,i)
    if existing then print("BLOCKED: destination inventory already contains an item in slot "..i);return end
  end
  local sourceSlot=nil
  for i=1,srcSize do
    local v=safe(addr,"getStackInSlot",from,i)
    if type(v)=="table" and itemMatches(v,r.stack) and tonumber(v.size or 0)>=n then
      sourceSlot=i;break
    end
  end
  if not sourceSlot then print("BLOCKED: source has no matching stack with "..n.." items");return end
  local cap=safe(addr,"getSlotMaxStackSize",to,1)
  if type(cap)=="number" and cap<n then print("BLOCKED: destination slot capacity "..cap.." < "..n);return end
  print("READY: "..n.." x "..tostring(name(r.stack)).." from inventory slot "..sourceSlot..
    " on side "..from.." -> destination side "..to.." slot 1")
  print("Check NEI recipe order: item index "..argv[3].." belongs at this bus.")
  if not doMove then print("CHECK ONLY: nothing moved");return end
  io.write("Type MOVE to transfer this single item ingredient: ")
  if io.read()~="MOVE" then print("Canceled");return end
  local result,err=safe(addr,"transferItem",from,to,n,sourceSlot,1)
  print("Transferred: "..tostring(result).." of "..n..(err and (" | "..tostring(err)) or ""))
  if result~=n then print("STOP: partial/failed transfer. Inspect both inventories before continuing.") end
end
local function checkFluid(doMove)
  local addr,from,to,r=getRequest("fluid")
  if not addr then return end
  local n=r.quantity
  if not n or n<=0 then print("BLOCKED: invalid fluid quantity");return end
  local srcTanks=safe(addr,"getTankCount",from)
  local dstTanks=safe(addr,"getTankCount",to)
  if type(srcTanks)~="number" or srcTanks<1 or type(dstTanks)~="number" or dstTanks<1 then
    print("BLOCKED: Transposer must touch both Super Tank and input hatch");return
  end
  local sourceTank=nil
  for i=1,srcTanks do
    local v=safe(addr,"getFluidInTank",from,i)
    if type(v)=="table" and fluidMatches(v,r.stack) and tonumber(v.amount or 0)>=n then
      sourceTank=i;break
    end
  end
  if not sourceTank then print("BLOCKED: source does not contain required fluid "..tostring(name(r.stack)).." ("..n.." L)");return end
  for i=1,dstTanks do
    local v=safe(addr,"getFluidInTank",to,i)
    if type(v)=="table" and tonumber(v.amount or 0)>0 then
      print("BLOCKED: destination has fluid in tank "..i);return
    end
  end
  local capacity=safe(addr,"getTankCapacity",to,1)
  if type(capacity)=="number" and capacity<n then print("BLOCKED: destination capacity insufficient");return end
  print("READY: "..n.." L "..tostring(name(r.stack)).." from tank "..sourceTank..
    " on side "..from.." -> destination side "..to)
  print("Check NEI recipe order: fluid index "..argv[3].." belongs at this hatch.")
  if not doMove then print("CHECK ONLY: nothing moved");return end
  io.write("Type MOVE to transfer this single fluid ingredient: ")
  if io.read()~="MOVE" then print("Canceled");return end
  local result,more=safe(addr,"transferFluid",from,to,n,sourceTank)
  local moved
  if type(result)=="number" then moved=result
  elseif result==true and type(more)=="number" then moved=more end
  print("Transferred: "..tostring(moved).." of "..n.." | API result: "..tostring(result))
  if moved~=n then print("STOP: partial/failed transfer. Inspect both tanks before continuing.") end
end
if command=="probe" then probe()
elseif command=="patterns" then patterns()
elseif command=="item-check" then checkItem(false)
elseif command=="item-move" then checkItem(true)
elseif command=="fluid-check" then checkFluid(false)
elseif command=="fluid-move" then checkFluid(true)
else
  print("GTNH Assembly Line direct transfer tester v0.6")
  print("Manual Data Sticks. No background service. No automatic crafting yet.")
  print("  probe")
  print("  patterns")
  print("  item-check <pattern-slot> <item-index> <transposer-address> <source-side> <destination-side>")
  print("  item-move  <pattern-slot> <item-index> <transposer-address> <source-side> <destination-side>")
  print("  fluid-check <pattern-slot> <fluid-index> <transposer-address> <source-side> <destination-side>")
  print("  fluid-move  <pattern-slot> <fluid-index> <transposer-address> <source-side> <destination-side>")
end
