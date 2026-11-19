-- GTNH 2.9 Assembly Line: two-fluid, single-Transposer router v1
-- One fluid Transposer touches one source tank per fluid and one output tank per hatch.
-- This is a ONE-BATCH operator-gated fluid transfer, NOT unattended continuous crafting.
-- Uses completed item router lock to determine the exact AE2 processing pattern.
-- Commands: probe | patterns | check | once | status | reset
local component=require("component")
local computer=require("computer")
local event=require("event")
local args={...}
local cmd=args[1] or "status"
local CONFIG="/home/al-fluid-config.lua"
local ITEM_LOCK="/home/al-item-run-lock.lua"
local FLUID_LOCK="/home/al-fluid-run-lock.lua"
local APPROVAL="/home/al-item-approved.lua"

local cfg={
  interfaceAddress="",
  transposerAddress="",
  sourceSides={},  -- tank holding AE2's Molten Indalloy and tank holding Lubricant, in any order
  outputSides={},  -- output tank feeding hatch 1, then hatch 2
  patternSlots=9,
  transferTimeout=20,
  retryDelay=0.25
}
local okConf, custom=pcall(dofile,CONFIG)
if okConf and type(custom)=="table" then
  for k,v in pairs(custom) do cfg[k]=v end
end
local function say(v) print("[AL-FLUID] "..tostring(v)) end
local function fail(v) error(tostring(v),0) end
local function call(addr,method,...)
  local ok,a,b=pcall(component.invoke,addr,method,...)
  if not ok then return nil,tostring(a) end
  return a,b
end
local function list(kind)
  local a={}
  for address in component.list(kind) do a[#a+1]=address end
  table.sort(a)
  return a
end
local function choose(kind,which)
  local a=list(kind)
  if which and which~="" then
    for _,v in ipairs(a) do if v==which then return v end end
    fail("Configured "..kind.." not present on computer: "..tostring(which))
  end
  if #a~=1 then fail("Found "..#a.." "..kind.." components; configure the full UUID") end
  return a[1]
end
local function readFile(path)
  local f=io.open(path,"r")
  if not f then return nil end
  f:close()
  local ok,value=pcall(dofile,path)
  if not ok or type(value)~="table" then return {corrupt=true} end
  return value
end
local function lock(phase,slot,hatch,output)
  local f,err=io.open(FLUID_LOCK,"w")
  if not f then fail("Cannot write fluid safety journal: "..tostring(err)) end
  f:write("return {\n")
  f:write(" phase="..string.format("%q",phase)..",\n")
  f:write(" slot="..tostring(slot)..",\n")
  f:write(" hatch="..tostring(hatch)..",\n")
  f:write(" output="..string.format("%q",output)..",\n")
  f:write("}\n")
  f:close()
end
local function positiveSide(side)
  return type(side)=="number" and side%1==0 and side>=0 and side<=5
end
local function sides()
  if type(cfg.sourceSides)~="table" or type(cfg.outputSides)~="table" then
    fail("Set sourceSides and outputSides in "..CONFIG)
  end
  local n=#cfg.sourceSides
  if n<1 or n>4 or #cfg.outputSides<1 or #cfg.outputSides>4 then
    fail("Set 1 to 4 sourceSides and 1 to 4 outputSides")
  end
  local used={}
  for _,side in ipairs(cfg.sourceSides) do
    if not positiveSide(side) or used[side] then fail("Source sides must be distinct integers from 0 to 5") end
    used[side]=true
  end
  for _,side in ipairs(cfg.outputSides) do
    if not positiveSide(side) or used[side] then fail("Every output must use a distinct side, different from sources") end
    used[side]=true
  end
  return choose("transposer",cfg.transposerAddress)
end
local function normalize(s)
  if s==nil then return "" end
  return tostring(s):lower():gsub("^%s+",""):gsub("%s+$",""):gsub("[%s_%-%p]","")
end
local function fluidInfo(x)
  if type(x)~="table" then return nil end
  local amount=tonumber(x.amount)
  if not amount or amount<=0 then return nil end
  local id=tostring(x.name or x.id or "")
  local label=tostring(x.label or x.displayName or "")
  return {id=id,label=label,amount=amount}
end
local function tank(addr,side)
  local n,err=call(addr,"getTankCount",side)
  if type(n)~="number" or n~=1 then fail("Side "..side.." must expose exactly ONE tank (found "..tostring(n)..") "..tostring(err or "")) end
  local raw,why=call(addr,"getFluidInTank",side,1)
  if why and raw==nil then fail("Could not read tank on side "..side..": "..tostring(why)) end
  local capacity=call(addr,"getTankCapacity",side,1)
  if type(capacity)~="number" or capacity<=0 then
    fail("Could not read a valid tank capacity on side "..side)
  end
  return {side=side,fluid=fluidInfo(raw),capacity=capacity}
end
local function fluidEq(a,b)
  if not a or not b then return false end
  if a.id~="" and b.id~="" and normalize(a.id)==normalize(b.id) then return true end
  if a.label~="" and b.label~="" and normalize(a.label)==normalize(b.label) then return true end
  return false
end
local function sortedInputKeys(t)
  local a={}
  if type(t)=="table" then
    for k,v in pairs(t) do if type(k)=="number" and k>0 and k%1==0 and type(v)=="table" then a[#a+1]=k end end
  end
  table.sort(a)
  return a
end
local function itemKey(x)
  if type(x)~="table" or x.hasTag==true or x.nbt~=nil or x.tag~=nil or type(x.name)~="string" or x.damage==nil then
    return nil
  end
  return x.name.."@"..tostring(x.damage)
end
-- Match the exact fingerprint used by al-item-router-v1.lua so a changed pattern cannot be silently used.
local function pattern(slot,raw)
  if type(raw)~="table" or type(raw.inputs)~="table" or type(raw.outputs)~="table" then
    fail("Invalid pattern in slot "..slot)
  end
  local p={slot=slot,items={},fluids={},output="unknown"}
  local outputKeys=sortedInputKeys(raw.outputs)
  if #outputKeys~=1 then fail("Pattern "..slot.." must have exactly one output") end
  local o=raw.outputs[outputKeys[1]]
  p.output=tostring(o.label or o.displayName or o.name or "unknown")
  if raw.isCraftable==true then fail("Pattern "..slot.." is a crafting pattern, not processing") end
  for _,index in ipairs(sortedInputKeys(raw.inputs)) do
    local x=raw.inputs[index]
    if x.amount~=nil then
      local q=tonumber(x.amount)
      if not q or q<=0 or q%1~=0 then fail("Bad fluid quantity in pattern "..slot) end
      local label=tostring(x.label or x.displayName or x.name or "")
      p.fluids[#p.fluids+1]={patternPosition=index,qty=q,id=tostring(x.name or ""),label=label}
    elseif x.size~=nil then
      local q=tonumber(x.size)
      local key=itemKey(x)
      if not q or q<1 or q>64 or q%1~=0 or not key then fail("Unsupported item in pattern "..slot) end
      p.items[#p.items+1]={patternPosition=index,qty=q,key=key}
    else
      fail("Unknown input type in pattern "..slot)
    end
  end
  return p
end
local function fingerprint(p)
  local parts={"slot="..p.slot,"out="..p.output}
  for _,x in ipairs(p.items) do parts[#parts+1]="item:"..x.patternPosition..":"..x.key..":"..x.qty end
  for _,x in ipairs(p.fluids) do parts[#parts+1]="fluid:"..x.patternPosition..":"..x.id..":"..x.qty end
  local s=table.concat(parts,"|")
  local h=0
  for i=1,#s do h=(h*131+s:byte(i))%2147483647 end
  return tostring(h)
end
local function recipe(slot)
  local addr=choose("fluid_interface",cfg.interfaceAddress)
  local raw,err=call(addr,"getInterfacePattern",slot)
  if err or type(raw)~="table" then fail("Cannot read pattern "..slot..": "..tostring(err)) end
  local p=pattern(slot,raw)
  if #p.fluids<1 then fail("Pattern "..slot.." has no fluids") end
  if #p.fluids>#cfg.outputSides then fail("Only "..#cfg.outputSides.." output hatch tanks configured; recipe requires "..#p.fluids) end
  local approvals=readFile(APPROVAL) or {}
  if approvals.corrupt or approvals[slot]~=fingerprint(p) then
    fail("Pattern "..slot.." is not approved by item router or has changed. Reapprove the pattern first.")
  end
  return p
end
local function itemReady()
  local il=readFile(ITEM_LOCK)
  if not il or il.corrupt then fail("No readable item-router lock. Run the item router first.") end
  if il.phase~="completed" then fail("Item router lock is '"..tostring(il.phase).."', not completed. No fluid can move yet.") end
  local slot=tonumber(il.slot)
  if not slot or slot<1 or slot%1~=0 then fail("Item router lock has invalid pattern slot") end
  return slot
end
local function layout(p,quiet)
  local a=sides()
  local sources={}
  for _,side in ipairs(cfg.sourceSides) do sources[#sources+1]=tank(a,side) end
  local outputs={}
  for _,side in ipairs(cfg.outputSides) do outputs[#outputs+1]=tank(a,side) end
  for _,out in ipairs(outputs) do
    if out.fluid then fail("Output tank on side "..out.side.." contains "..out.fluid.amount.." L "..out.fluid.label..". It must be EMPTY before starting.") end
  end
  local usedSources={}
  local routes={}
  for i,x in ipairs(p.fluids) do
    local required={id=x.id,label=x.label}
    local chosen=nil
    for _,src in ipairs(sources) do
      if src.fluid and fluidEq(src.fluid,required) then
        if chosen and chosen.side~=src.side then fail("Multiple source tanks match fluid "..x.label..". Use one tank per fluid type.") end
        chosen=src
      end
    end
    if not chosen then fail("No visible source tank contains "..x.label.." for hatch "..i) end
    usedSources[chosen.side]=(usedSources[chosen.side] or 0)+x.qty
    if chosen.fluid.amount<usedSources[chosen.side] then
      fail("Insufficient "..x.label.." in source tank on side "..chosen.side)
    end
    local out=outputs[i]
    if out.capacity<x.qty then fail("Output tank on side "..out.side.." is too small for "..x.qty.." L") end
    routes[#routes+1]={hatch=i,label=x.label,quantity=x.qty,source=chosen.side,output=out.side}
  end
  if not quiet then
    for _,r in ipairs(routes) do
      say("Hatch "..r.hatch..": "..r.quantity.." L "..r.label.." | source tank side "..r.source.." -> output tank side "..r.output)
    end
    say("All output tanks are empty. Routing destinations are NOT independently verifiable through the tanks.")
  end
  return a,routes
end
local function probe()
  say("READ ONLY fluid Transposer scan")
  local listTrans=list("transposer")
  say("Connected transposers: "..#listTrans)
  for _,a in ipairs(listTrans) do
    say("Transposer "..a)
    for side=0,5 do
      local n=call(a,"getTankCount",side)
      if type(n)=="number" and n>0 then
        say("  side "..side..": "..n.." tank(s)")
        for i=1,n do
          local raw=call(a,"getFluidInTank",side,i)
          local f=fluidInfo(raw)
          local capacity=call(a,"getTankCapacity",side,i)
          if f then
            say("    tank "..i..": "..f.amount.." L "..f.label.." | id="..f.id.." | capacity="..tostring(capacity))
          else
            say("    tank "..i..": EMPTY | capacity="..tostring(capacity))
          end
        end
      end
    end
  end
  say("Probe moved nothing. Enter tank sides in "..CONFIG)
end
local function patterns()
  local addr=choose("fluid_interface",cfg.interfaceAddress)
  local approved=readFile(APPROVAL) or {}
  for i=1,tonumber(cfg.patternSlots) or 9 do
    local raw=call(addr,"getInterfacePattern",i)
    if type(raw)=="table" then
      local ok,p=pcall(pattern,i,raw)
      if not ok then say("Pattern "..i.." error: "..tostring(p))
      else
        say("Pattern "..i..": "..p.output.." | "..(approved[i]==fingerprint(p) and "APPROVED" or "NOT APPROVED"))
        for j,x in ipairs(p.fluids) do say("  Hatch "..j.." <- "..x.qty.." L "..x.label) end
      end
    end
  end
end
local function check()
  local slot=itemReady()
  local p=recipe(slot)
  say("Selected from item-router lock: pattern "..slot.." "..p.output)
  local a,r=layout(p,false)
  if readFile(FLUID_LOCK) then
    fail("Fluid safety lock already exists. Use status. No new transfer allowed.")
  end
  say("READY for one fluid batch once you verify each output tank feeds the stated hatch.")
  say("READ ONLY. Nothing moved.")
  return p,a,r
end
local function transferOne(a,r,p)
  lock("moving",p.slot,r.hatch,p.output)
  local total=0
  local deadline=computer.uptime()+(tonumber(cfg.transferTimeout) or 20)
  while total<r.quantity and computer.uptime()<deadline do
    local moved,amount=call(a,"transferFluid",r.source,r.output,r.quantity-total)
    -- OpenComputers: true, number (millibuckets) on success.
    if moved==true and type(amount)=="number" and amount>0 then
      total=total+amount
      if total>r.quantity then fail("Fluid transfer exceeded requested quantity! Stop and inspect manually") end
    elseif moved==false or moved==nil then
      if total==0 then fail("Fluid transfer rejected at hatch "..r.hatch..": "..tostring(amount)) end
      fail("Partial fluid transfer stopped at hatch "..r.hatch.." after "..total.." L: "..tostring(amount))
    else
      fail("Unexpected transferFluid return values: "..tostring(moved).." / "..tostring(amount))
    end
    if total<r.quantity then event.pull(tonumber(cfg.retryDelay) or 0.25) end
  end
  if total~=r.quantity then fail("Transfer timed out after "..total.." L, wanted "..r.quantity) end
  lock("moved",p.slot,r.hatch,p.output)
  say("Transferred exactly "..total.." L for Hatch "..r.hatch..": "..r.label)
end
local function once()
  local p,a,r=check()
  say("FLUIDS WILL MOVE. Make sure Hatches 1 and 2 and their pipes are empty, and item buses contain the right inputs.")
  io.write("Type FLUID to transfer one recipe's fluids: ")
  if io.read()~="FLUID" then say("Canceled");return end
  -- Recheck immediately before locking.
  local p2=recipe(itemReady())
  if p2.slot~=p.slot then fail("Selected recipe changed") end
  a,r=layout(p2,true)
  if readFile(FLUID_LOCK) then fail("Fluid safety lock exists") end
  lock("started",p.slot,0,p.output)
  for _,step in ipairs(r) do
    -- Reverify the selected pattern and that target tank is initially empty.
    local fresh=tank(a,step.output)
    if fresh.fluid then fail("Output tank on side "..step.output.." is no longer empty before hatch "..step.hatch) end
    local source=tank(a,step.source)
    if not source.fluid or source.fluid.amount<step.quantity then fail("Fluid source missing for hatch "..step.hatch) end
    local target={id=step.hatch and p2.fluids[step.hatch].id,label=step.label}
    if not fluidEq(source.fluid,target) then fail("Fluid source changed before hatch "..step.hatch) end
    transferOne(a,step,p)
  end
  lock("completed",p.slot,#r,p.output)
  say("Fluid quantities have been transferred. Verify actual hatch tanks before trusting unattended automation.")
  say("Fluid safety lock remains until you manually reset after this craft.")
end
local function reset()
  local prior=readFile(FLUID_LOCK)
  if not prior then say("No fluid safety lock");return end
  say("Fluid safety lock: "..tostring(prior.phase).." | pattern "..tostring(prior.slot).." | last hatch "..tostring(prior.hatch))
  say("ONLY reset after the previous craft completes and you verify all output tanks/hatches are clear.")
  io.write("Type RESET to release the fluid safety lock: ")
  if io.read()~="RESET" then say("Canceled");return end
  local ok,err=os.remove(FLUID_LOCK)
  if not ok then fail("Cannot remove safety lock: "..tostring(err)) end
  say("Fluid safety lock cleared.")
end
local function status()
  say("Single Transposer tank-to-tank fluid router v1. Items not touched.")
  local il=readFile(ITEM_LOCK)
  local fl=readFile(FLUID_LOCK)
  say("Item lock: "..(il and tostring(il.phase).." pattern "..tostring(il.slot) or "none"))
  say("Fluid lock: "..(fl and tostring(fl.phase).." pattern "..tostring(fl.slot).." hatch "..tostring(fl.hatch) or "none"))
  say("Commands: probe, patterns, check, once, status, reset")
end
local function main()
  if cmd=="probe" then probe()
  elseif cmd=="patterns" then patterns()
  elseif cmd=="check" then check()
  elseif cmd=="once" then once()
  elseif cmd=="status" then status()
  elseif cmd=="reset" then reset()
  else say("Commands: probe, patterns, check, once, status, reset") end
end
local ok,err=pcall(main)
if not ok then
  say("STOPPED: "..tostring(err))
  say("If fluid transfer began, DO NOT RESET without checking source/output tanks and the Assembly Line hatches.")
end