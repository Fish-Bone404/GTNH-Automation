-- GTNH 2.9 Assembly Line: Single-Transposer Item Router v2.0
-- ONE item Transposer touches AE2 staging chest and Ender IO feeder chest.
-- Does NOT route fluids, move Data Sticks, or verify Assembly Line bus occupancy.
-- One batch per operator reset: deliberately NOT unattended continuous crafting.
-- Commands: probe | patterns | approve SLOT | check | once | run | status | reset

local component = require("component")
local event = require("event")
local computer = require("computer")
local args = {...}
local cmd = args[1] or "status"
local CFG = "/home/al-item-config.lua"
local APPROVAL = "/home/al-item-approved.lua"
local LOCK = "/home/al-item-run-lock.lua"

local cfg = {
  interfaceAddress = "", -- blank: find the one connected ME Dual Interface
  transposerAddress = "", -- blank: find the one connected Transposer
  machineAddress = "", -- GT Assembly Line controller through OC Adapter
  sourceSide = -1,       -- side of AE2 staging chest, determined by probe
  feederSide = -1,       -- side of Ender IO feeder chest, determined by probe
  patternSlots = 9,
  stagingStableSeconds = 0.6,
  feederEmptySeconds = 0.2,
  feederDrainTimeout = 15,
  autoPollSeconds = 0.4,
  machineStartTimeout = 120,
  machineFinishTimeout = 3600,
  idleStableSeconds = 1.0,
  machinePollSeconds = 0.1
}
local okCfg, extra = pcall(dofile, CFG)
if okCfg and type(extra) == "table" then
  for k,v in pairs(extra) do cfg[k] = v end
end

local function say(s) print("[AL-ITEM] " .. tostring(s)) end
local function fail(s) error(tostring(s), 0) end
local function invoke(address, method, ...)
  local ok, x, y = pcall(component.invoke, address, method, ...)
  if not ok then return nil, tostring(x) end
  return x, y
end
local function addresses(kind)
  local all = {}
  for address in component.list(kind) do all[#all+1] = address end
  table.sort(all)
  return all
end
local function choose(kind, saved)
  local a = addresses(kind)
  if type(saved) == "string" and saved ~= "" then
    for _, x in ipairs(a) do if x == saved then return saved end end
    fail("Configured " .. kind .. " not connected: " .. saved)
  end
  if #a ~= 1 then fail("Expected exactly one " .. kind .. ", found " .. #a .. ". Set its address in " .. CFG) end
  return a[1]
end
local function sides()
  local from = tonumber(cfg.sourceSide)
  local to = tonumber(cfg.feederSide)
  if not from or not to or from % 1 ~= 0 or to % 1 ~= 0 or
    from < 0 or from > 5 or to < 0 or to > 5 or from == to then
    fail("Set different sourceSide and feederSide values from 0 to 5 in " .. CFG)
  end
  local a = choose("transposer", cfg.transposerAddress)
  local n = invoke(a, "getInventorySize", from)
  local m = invoke(a, "getInventorySize", to)
  if type(n) ~= "number" or n < 1 then fail("No staging inventory on side " .. from) end
  if type(m) ~= "number" or m < 1 then fail("No feeder inventory on side " .. to) end
  return a, from, to, n, m
end
local function name(x)
  if type(x) ~= "table" then return "unknown" end
  return tostring(x.label or x.displayName or x.name or "unknown")
end
local function identity(x)
  if type(x) ~= "table" then return nil end
  if type(x.name) ~= "string" or x.name == "" or x.damage == nil then return nil end
  if x.hasTag == true or x.nbt ~= nil or x.tag ~= nil then return nil end
  return x.name .. "@" .. tostring(x.damage)
end
local function keys(t)
  local a={}
  if type(t) ~= "table" then return a end
  for k,v in pairs(t) do
    if type(k) == "number" and k > 0 and k % 1 == 0 and type(v) == "table" then
      a[#a+1]=k
    end
  end
  table.sort(a)
  return a
end
local function parsePattern(slot, raw)
  if raw == nil then return nil end
  local p = {slot=slot, items={}, fluids={}, output="unknown", invalid=nil}
  if type(raw) ~= "table" or type(raw.inputs) ~= "table" or type(raw.outputs) ~= "table" then
    p.invalid="Unexpected pattern structure";return p
  end
  if raw.isCraftable == true then p.invalid="Crafting pattern, not processing" end
  local outKeys=keys(raw.outputs)
  if #outKeys ~= 1 then p.invalid="Expected exactly one output item" end
  if #outKeys >= 1 then p.output=name(raw.outputs[outKeys[1]]) end
  for _, index in ipairs(keys(raw.inputs)) do
    local x=raw.inputs[index]
    if x.amount ~= nil then
      local qty=tonumber(x.amount)
      if not qty or qty <= 0 or qty % 1 ~= 0 then
        p.invalid="Bad fluid amount at AE2 input "..index
      else
        p.fluids[#p.fluids+1]={patternPosition=index, qty=qty, label=name(x), fluidId=x.name}
      end
    elseif x.size ~= nil then
      local qty=tonumber(x.size)
      local key=identity(x)
      if not qty or qty <= 0 or qty % 1 ~= 0 or qty > 64 or not key then
        p.invalid="Unsupported item at AE2 input "..index..". Must be a stack of at most 64 with readable ID and metadata, without NBT."
      else
        p.items[#p.items+1]={patternPosition=index, qty=qty, label=name(x), key=key}
      end
    else
      p.invalid="Unknown input type at AE2 input "..index
    end
  end
  if #p.items < 1 or #p.items > 16 or #p.fluids > 4 then
    p.invalid="Pattern needs unsupported number of buses or fluid hatches"
  end
  return p
end
local function patterns()
  local addr=choose("fluid_interface",cfg.interfaceAddress)
  local n=tonumber(cfg.patternSlots) or 9
  if n < 1 or n > 36 or n % 1 ~= 0 then fail("patternSlots must be an integer from 1 to 36") end
  local all={}
  for slot=1,n do
    local raw,err=invoke(addr,"getInterfacePattern",slot)
    if err and raw == nil then fail("Cannot read AE2 pattern slot "..slot..": "..err) end
    local p=parsePattern(slot,raw)
    if p then all[#all+1]=p end
  end
  return all
end
local function fingerprint(p)
  local s={"slot="..p.slot, "out="..p.output}
  for _,x in ipairs(p.items) do s[#s+1]="item:"..x.patternPosition..":"..x.key..":"..x.qty end
  for _,x in ipairs(p.fluids) do
    s[#s+1]="fluid:"..x.patternPosition..":"..tostring(x.fluidId)..":"..x.qty
  end
  local v=table.concat(s,"|")
  local h=0
  for i=1,#v do h=(h*131+v:byte(i))%2147483647 end
  return tostring(h)
end
local function readFile(path)
  local h=io.open(path,"r")
  if not h then return nil end
  h:close()
  local ok,x=pcall(dofile,path)
  if not ok or type(x)~="table" then return {corrupt=true} end
  return x
end
local approvals=readFile(APPROVAL) or {}
local function approved(p)
  return approvals[p.slot]==fingerprint(p)
end
local function saveTable(path,t)
  local f,err=io.open(path,"w")
  if not f then fail("Could not write "..path..": "..tostring(err)) end
  f:write("-- Generated by al-item-router-v1.lua\nreturn {\n")
  local sorted={}
  for k in pairs(t) do sorted[#sorted+1]=k end
  table.sort(sorted,function(a,b)return tostring(a)<tostring(b) end)
  for _,k in ipairs(sorted) do
    local v=t[k]
    if type(k)=="number" and type(v)=="string" then
      f:write(string.format(" [%d]=%q,\n",k,v))
    end
  end
  f:write("}\n")
  f:close()
end
local function lockState(phase,slot,step,output)
  -- Write journal BEFORE touching the next stack. Any crash requires human verification.
  local f,err=io.open(LOCK,"w")
  if not f then fail("Cannot update safety lock: "..tostring(err)) end
  f:write("return {\n")
  f:write(" phase="..string.format("%q",phase)..",\n")
  f:write(" slot="..tostring(slot)..",\n")
  f:write(" step="..tostring(step)..",\n")
  f:write(" output="..string.format("%q",output).."\n")
  f:write("}\n");f:close()
end
local function printPattern(p)
  say("Pattern "..p.slot..": "..p.output.." | "..(approved(p) and "APPROVED" or "NOT APPROVED"))
  if p.invalid then say("  BLOCKED: "..p.invalid) end
  for i,x in ipairs(p.items) do say("  Bus "..i.." <- "..x.qty.." x "..x.label.." [AE2 input "..x.patternPosition.."]") end
  for i,x in ipairs(p.fluids) do say("  Hatch "..i.." <- "..x.qty.." L "..x.label.." [AE2 input "..x.patternPosition.."]") end
end
local function getInv(a,side,n)
  local rows={}
  for i=1,n do
    local x,err=invoke(a,"getStackInSlot",side,i)
    if x==nil and err then fail("Inventory scan failed on side "..side.." slot "..i..": "..tostring(err)) end
    if type(x)=="table" and tonumber(x.size or 0)>0 then
      rows[#rows+1]={slot=i, stack=x, count=tonumber(x.size), key=identity(x)}
    end
  end
  return rows
end
local function feederEmpty(a,to,n)
  return #getInv(a,to,n)==0
end
local function staged(a,from,n)
  return getInv(a,from,n)
end
local function signature(rows)
  local x={}
  for _,r in ipairs(rows) do x[#x+1]=r.slot..":"..tostring(r.key)..":"..r.count end
  return table.concat(x,"|")
end
local function needed(p,start)
  local totals={}
  for i=start,#p.items do
    local x=p.items[i]
    totals[x.key]=(totals[x.key] or 0)+x.qty
  end
  return totals
end
local function exactMatch(p,rows,start)
  if p.invalid then return false end
  local want=needed(p,start or 1)
  local have={}
  for _,r in ipairs(rows) do
    if not r.key or not want[r.key] then return false end
    have[r.key]=(have[r.key] or 0)+r.count
  end
  for key,quantity in pairs(want) do
    if have[key] ~= quantity then return false end
  end
  return true
end
local function candidates(rows)
  local out={}
  for _,p in ipairs(patterns()) do
    if exactMatch(p,rows,1) then out[#out+1]=p end
  end
  return out
end
local function checkConfig()
  local a,from,to,n,m=sides()
  return a,from,to,n,m
end
local function ready(quiet)
  local a,from,to,n,m=checkConfig()
  local rows=staged(a,from,n)
  if #rows==0 then return nil,"Staging chest is empty" end
  if not feederEmpty(a,to,m) then return nil,"Distribution chest is not empty" end
  local matches=candidates(rows)
  if #matches==0 then return nil,"No complete exact recipe matches the staging chest; no transfers permitted" end
  if #matches>1 then return nil,"Several patterns match these items; cannot distinguish them without a fluid or request signal" end
  local p=matches[1]
  if not approved(p) then return nil,"Pattern "..p.slot.." matches, but its NEI bus order has not been approved" end
  if not quiet then printPattern(p) end
  return p,nil,{address=a,source=from,feeder=to,sourceSize=n,feederSize=m,rows=rows}
end
local function awaitStable(p,hardware)
  local first=signature(staged(hardware.address,hardware.source,hardware.sourceSize))
  local at=computer.uptime()
  local deadline=at+math.max(15,tonumber(cfg.stagingStableSeconds)*6)
  while computer.uptime() - at < tonumber(cfg.stagingStableSeconds) do
    if computer.uptime()>deadline then fail("Staging did not stabilize") end
    event.pull(0.1)
    local rows=staged(hardware.address,hardware.source,hardware.sourceSize)
    if not exactMatch(p,rows,1) then fail("Staging ingredients changed during the preflight") end
    local nextSignature=signature(rows)
    if nextSignature~=first then first=nextSignature;at=computer.uptime() end
    if not feederEmpty(hardware.address,hardware.feeder,hardware.feederSize) then
      fail("Distribution chest received unexpected items while waiting")
    end
  end
end
local function awaitDrain(hardware,step)
  local emptyFrom=nil
  local deadline=computer.uptime()+(tonumber(cfg.feederDrainTimeout) or 25)
  local seconds=tonumber(cfg.feederEmptySeconds) or 1
  while computer.uptime()<deadline do
    local empty=feederEmpty(hardware.address,hardware.feeder,hardware.feederSize)
    if empty then
      if not emptyFrom then emptyFrom=computer.uptime() end
      if computer.uptime()-emptyFrom>=seconds then return end
    else
      emptyFrom=nil
    end
    event.pull(0.1)
  end
  fail("Step "..step.." timed out: items remain in distribution chest. STOP and inspect conduits, priorities and filters")
end
local function singleStack(rows,x)
  for _,r in ipairs(rows) do
    if r.key==x.key and r.count>=x.qty then return r end
  end
  return nil
end
local function deliver(p,h)
  local lock=readFile(LOCK)
  if lock then fail("Safety lock exists. Inspect the line and use reset only after buses and feeder are clear") end
  local p2,reason=ready(true)
  if not p2 or p2.slot~=p.slot or fingerprint(p2)~=fingerprint(p) then
    fail("Pattern changed before delivery: "..tostring(reason))
  end
  awaitStable(p,h)
  lockState("started",p.slot,0,p.output)
  say("Locked to pattern "..p.slot..": "..p.output)
  for i,x in ipairs(p.items) do
    -- Fail if any unanticipated source contents arrived during distribution.
    local rows=staged(h.address,h.source,h.sourceSize)
    if not exactMatch(p,rows,i) then
      fail("Source no longer matches expected remaining items before Bus "..i..". STOP")
    end
    if not feederEmpty(h.address,h.feeder,h.feederSize) then
      fail("Feeder not empty before Bus "..i)
    end
    local row=singleStack(rows,x)
    if not row then
      fail("Bus "..i.." needs "..x.qty.." x "..x.label.." in a SINGLE source stack; consolidate partial stacks first")
    end
    lockState("moving",p.slot,i,p.output)
    local moved,err=invoke(h.address,"transferItem",h.source,h.feeder,x.qty,row.slot)
    if tonumber(moved)~=x.qty then
      fail("Transfer to feeder failed or partial at Bus "..i..": moved="..tostring(moved).." expected="..x.qty.." "..tostring(err))
    end
    say("Released ingredient "..i.." of "..#p.items..": "..x.qty.." x "..x.label)
    awaitDrain(h,i)
    lockState("drained",p.slot,i,p.output)
  end
  lockState("completed",p.slot,#p.items,p.output)
  say("All item positions were released in order. NOT proof of bus placement.")
  say("Safety lock remains until the Assembly Line finishes and you manually reset.")
  say("Fluid distribution and machine-start control are NOT included.")
end
local function probe()
  say("Hardware scan, READ ONLY")
  for _,kind in ipairs({"fluid_interface","transposer"}) do
    local list=addresses(kind)
    say(kind..": "..#list)
    for _,addr in ipairs(list) do say("  "..addr) end
  end
  for _,a in ipairs(addresses("transposer")) do
    say("Transposer "..a)
    for side=0,5 do
      local n=invoke(a,"getInventorySize",side)
      if type(n)=="number" and n>0 then
        local label=invoke(a,"getInventoryName",side)
        say("  side "..side.." | "..n.." slots | "..tostring(label))
        for _,row in ipairs(getInv(a,side,n)) do
          say("    slot "..row.slot.." = "..row.count.." x "..name(row.stack))
        end
      end
    end
  end
  say("Connected gt_machine components:")
  for _,m in ipairs(addresses("gt_machine")) do
    local x=invoke(m,"getWorkProgress")
    local y=invoke(m,"getWorkMaxProgress")
    say("  "..m.." work="..tostring(x).." max="..tostring(y))
  end
  say("Use these side numbers in "..CFG..". Probe moves NOTHING.")
end
local function doApprove()
  local slot=tonumber(args[2])
  if not slot or slot%1~=0 then say("Usage: approve <AE2 pattern slot>");return end
  local found=nil
  for _,p in ipairs(patterns()) do if p.slot==slot then found=p end end
  if not found then fail("No pattern found in slot "..slot) end
  printPattern(found)
  if found.invalid then fail("Cannot approve invalid pattern: "..found.invalid) end
  say("Compare all numbered item buses and fluid hatches above against the GTNH NEI Assembly Line recipe.")
  say("This DOES NOT verify routing hardware. It approves ONLY the saved recipe order.")
  io.write("Type APPROVE to accept this exact recipe order: ")
  if io.read()~="APPROVE" then say("Canceled");return end
  approvals[slot]=fingerprint(found)
  saveTable(APPROVAL,approvals)
  say("Approved pattern "..slot..". Changing its ingredients will invalidate approval.")
end
local function check()
  local lock=readFile(LOCK)
  if lock then
    say("SAFETY LOCK: "..tostring(lock.phase).." | pattern "..tostring(lock.slot).." | step "..tostring(lock.step))
  end
  local a,from,to,n,m=checkConfig()
  say("Source: "..a.." side "..from.." | feeder: side "..to)
  for _,row in ipairs(staged(a,from,n)) do
    say("Staged: "..row.count.." x "..name(row.stack).." [slot "..row.slot.."]")
  end
  say("Feeder: "..(feederEmpty(a,to,m) and "empty" or "NOT EMPTY"))
  local p,why=ready(false)
  if p then say("MATCHED: "..p.output.." | one batch | "..(lock and "BLOCKED BY SAFETY LOCK" or "READY FOR ONE-BATCH DISPATCH"))
  else say("NOT READY: "..why) end
  say("No items moved.")
end
local function once()
  if readFile(LOCK) then fail("Safety lock exists. Run status or reset after inspecting the line") end
  local p,why,h=ready(false)
  if not p then fail(why) end
  say("This is an ITEM-ONLY test. Existing bus contents cannot be verified by this one Transposer.")
  io.write("Type MOVE to release ONE recipe batch: ")
  if io.read()~="MOVE" then say("Canceled");return end
  deliver(p,h)
end
local function machineReading()
  local address=choose("gt_machine",cfg.machineAddress)
  local progress,e1=invoke(address,"getWorkProgress")
  local maximum,e2=invoke(address,"getWorkMaxProgress")
  if type(progress)~="number" or type(maximum)~="number" then
    fail("Cannot read Assembly Line progress through OC Adapter: "..tostring(e1 or e2))
  end
  if progress<0 or maximum<0 then fail("Machine reports invalid progress values") end
  return progress,maximum,address
end
local function machineIdle()
  local progress,maximum=machineReading()
  return progress<=0 and maximum<=0
end
local function stableIdle()
  local t=computer.uptime()
  local seconds=tonumber(cfg.idleStableSeconds) or 1
  while computer.uptime()-t<seconds do
    if not machineIdle() then return false end
    event.pull(0.1)
  end
  return true
end
local function waitForCraft(slot)
  local seen=false
  local startDeadline=computer.uptime()+(tonumber(cfg.machineStartTimeout) or 120)
  local endDeadline=nil
  local idleAt=nil
  while true do
    local progress,maximum=machineReading()
    local busy=progress>0 or maximum>0
    if busy then
      if not seen then
        seen=true
        endDeadline=computer.uptime()+(tonumber(cfg.machineFinishTimeout) or 3600)
        say("Assembly Line started crafting pattern "..slot)
      end
      idleAt=nil
    elseif seen then
      if not idleAt then idleAt=computer.uptime() end
      if computer.uptime()-idleAt >= tonumber(cfg.idleStableSeconds) then
        say("Assembly Line returned to idle after pattern "..slot)
        return
      end
    end
    if not seen and computer.uptime()>startDeadline then
      fail("Assembly Line did not start. Check fluids, power, Data Stick and item bus order. Safety lock retained.")
    end
    if seen and computer.uptime()>endDeadline then
      fail("Assembly Line did not complete before timeout. Safety lock retained.")
    end
    event.pull(tonumber(cfg.machinePollSeconds) or 0.1)
  end
end
-- No operator confirmation in run mode.
-- Wait for one exact staged recipe, release its items, verify a machine cycle, repeat.
local function run()
  local _,_,addr=machineReading()
  say("Continuous item routing started. Machine Adapter "..addr)
  say("Fluids are external and must already route into the correct hatches.")
  say("One complete batch at a time; mixed or multiplied batches will NOT match.")
  local previous=""
  while true do
    if readFile(LOCK) then
      fail("Safety lock remains from an earlier craft. Inspect the machine and use reset before restarting.")
    end
    if machineIdle() then
      local p,reason,h=ready(true)
      if p then
        say("AE2 staged "..p.output..", pattern "..p.slot)
        if stableIdle() then
          deliver(p,h)
          waitForCraft(p.slot)
          if not feederEmpty(h.address,h.feeder,h.feederSize) then
            fail("Distribution chest still contains items after crafting.")
          end
          if not stableIdle() then fail("Machine became active unexpectedly after craft.") end
          local state=readFile(LOCK)
          if not state or state.phase~="completed" or state.slot~=p.slot then
            fail("Safety journal changed during crafting; halting.")
          end
          local ok,err=os.remove(LOCK)
          if not ok then fail("Could not clear completed journal: "..tostring(err)) end
          say("Completed machine cycle. Waiting for next AE2 request.")
          previous=""
        end
      elseif previous~=reason then
        say("Waiting: "..reason)
        previous=reason
      end
    elseif previous~="busy" then
      say("Assembly Line busy; waiting for it to become idle")
      previous="busy"
    end
    event.pull(tonumber(cfg.autoPollSeconds) or 0.4)
  end
end
local function reset()
  local state=readFile(LOCK)
  if not state then say("No safety lock exists");return end
  say("LOCK: "..tostring(state.phase).." pattern="..tostring(state.slot).." step="..tostring(state.step))
  say("ONLY reset after verifying the Assembly Line buses and feeder chest are empty and the prior craft has finished.")
  io.write("Type RESET to release safety lock: ")
  if io.read()~="RESET" then say("Canceled");return end
  local a,from,to,n,m=checkConfig()
  if not feederEmpty(a,to,m) then fail("Feeder chest still has items. Refusing reset") end
  local ok,err=os.remove(LOCK)
  if not ok then fail("Could not remove lock: "..tostring(err)) end
  say("Lock cleared. You may dispatch the next batch.")
end
local function main()
  if cmd=="probe" then probe()
  elseif cmd=="patterns" then for _,p in ipairs(patterns()) do printPattern(p) end
  elseif cmd=="approve" then doApprove()
  elseif cmd=="check" then check()
  elseif cmd=="once" then once()
  elseif cmd=="run" or cmd=="auto" then run()
  elseif cmd=="reset" then reset()
  elseif cmd=="status" then
    say("Single-Transposer item router v2.0. Continuous mode requires GT machine Adapter; fluids external.")
    local state=readFile(LOCK)
    say(state and ("SAFETY LOCK: "..tostring(state.phase).." pattern "..tostring(state.slot).." step "..tostring(state.step)) or "No safety lock")
    say("Commands: probe, patterns, approve SLOT, check, once, run, status, reset")
    say("Configuration: "..CFG)
  else say("Unknown command. Try status") end
end
local ok,err=pcall(main)
if not ok then
  say("STOPPED: "..tostring(err))
  say("Do not rerun until you inspect the staging chest, feeder chest and input buses.")
end