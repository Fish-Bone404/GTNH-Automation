-- GTNH 2.9 Assembly Line Rebuild: staging probe v1
-- READ ONLY. No transfers, machine controls, or Data Stick management.
local c=require("component")
local a={...}
local cmd=a[1] or "scan"
local configPath="/home/al-stage-config.lua"

local function call(addr,method,...)
  local ok,x,y=pcall(c.invoke,addr,method,...)
  if not ok then return nil,tostring(x) end
  return x,y
end
local function kindList(kind)
  local t={}
  for addr in c.list(kind) do t[#t+1]=addr end
  table.sort(t);return t
end
local function label(x)
  return type(x)=="table" and (x.label or x.fluidName or x.displayName or x.name) or "unknown"
end
local function text(x) return tostring(x or ""):lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ") end
local function itemKey(x)
  if type(x)~="table" or x.hasTag==true then return nil end
  if type(x.name)=="string" then
    return text(x.name)..":"..tostring(x.damage or "unknown")
  end
  return "label:"..text(label(x))
end
local function fluidKey(x)
  if type(x)~="table" then return nil end
  return text(x.name or x.fluidName or x.label)
end
local function slots(addr,side,size)
  local stacks,err=call(addr,"getAllStacks",side)
  if stacks then
    local ok,t=pcall(function()return stacks.getAll() end)
    if ok and type(t)=="table" then return t end
  end
  local t={}
  for i=1,size do
    local x=call(addr,"getStackInSlot",side,i)
    t[i]=x
  end
  return t
end
local function scan()
  print("AL Staging v1 | component and buffer probe | READ ONLY")
  local ifaces=kindList("fluid_interface")
  for _,addr in ipairs(ifaces) do print("ME Dual Interface: "..addr) end
  if #ifaces~=1 then print("NOTE: expected exactly one Dual Interface for recipe scanning") end
  local trans=kindList("transposer")
  print("Transposers detected: "..#trans)
  for _,addr in ipairs(trans) do
    print("\nTransposer "..addr)
    for side=0,5 do
      local n=call(addr,"getInventorySize",side)
      local nt=call(addr,"getTankCount",side)
      if type(n)=="number" or (type(nt)=="number" and nt>0) then
        local invName=call(addr,"getInventoryName",side)
        print("  Side "..side.." | inventory="..tostring(n)..
          " | tanks="..tostring(nt).." | "..tostring(invName))
        if type(n)=="number" then
          local all=slots(addr,side,n)
          for i=1,n do
            local x=all[i]
            if type(x)=="table" and tonumber(x.size or 0)>0 then
              print("    Item slot "..i..": "..tostring(x.size).." x "..tostring(label(x)))
            end
          end
        end
        if type(nt)=="number" then
          for tank=1,nt do
            local x=call(addr,"getFluidInTank",side,tank)
            if type(x)=="table" and tonumber(x.amount or 0)>0 then
              print("    Fluid tank "..tank..": "..tostring(x.amount).." L "..tostring(label(x)))
            end
          end
        end
      end
    end
  end
  print("\nNothing moved. Record the exact Transposer addresses and sides that contain the staging chest and tanks.")
end
local function patterns()
  local ifaces=kindList("fluid_interface")
  if #ifaces~=1 then print("ERROR: expected exactly one ME Dual Interface");return {} end
  local all={}
  for slot=1,9 do
    local p,err=call(ifaces[1],"getInterfacePattern",slot)
    if err then print("ERROR reading pattern "..slot..": "..err) end
    if type(p)=="table" and type(p.inputs)=="table" then
      local out=type(p.outputs)=="table" and p.outputs[1] or nil
      local rec={slot=slot,output=label(out),items={},fluids={},unknown=0}
      for k=1,18 do
        local x=p.inputs[k]
        if type(x)=="table" then
          if tonumber(x.amount) and tonumber(x.amount)>0 then
            rec.fluids[#rec.fluids+1]={position=k,key=fluidKey(x),qty=tonumber(x.amount),name=label(x)}
          elseif tonumber(x.size) and tonumber(x.size)>0 then
            rec.items[#rec.items+1]={position=k,key=itemKey(x),qty=tonumber(x.size),name=label(x)}
          else
            rec.unknown=rec.unknown+1
          end
        end
      end
      print("Pattern "..slot..": "..rec.output.." | "..#rec.items.." items | "..#rec.fluids.." fluids")
      for _,x in ipairs(rec.items) do print("  Item position "..x.position..": "..x.qty.." x "..x.name) end
      for _,x in ipairs(rec.fluids) do print("  Fluid position "..x.position..": "..x.qty.." L "..x.name) end
      all[#all+1]=rec
    end
  end
  return all
end
local function sourceRows(entry,wantFluid)
  if type(entry)~="table" or not entry.address or type(entry.side)~="number" then
    return nil,"Missing address/side in /home/al-stage-config.lua"
  end
  local addr,side=entry.address,entry.side
  if wantFluid then
    local n=call(addr,"getTankCount",side)
    if type(n)~="number" then return nil,"No fluid handler for "..addr.." side "..side end
    local rows={}
    for i=1,n do
      local x=call(addr,"getFluidInTank",side,i)
      if type(x)=="table" and tonumber(x.amount or 0)>0 then
        rows[#rows+1]={key=fluidKey(x),amount=tonumber(x.amount),name=label(x)}
      end
    end
    return rows
  end
  local n=call(addr,"getInventorySize",side)
  if type(n)~="number" then return nil,"No inventory for "..addr.." side "..side end
  local all=slots(addr,side,n);local rows={}
  for i=1,n do
    local x=all[i]
    if type(x)=="table" and tonumber(x.size or 0)>0 then
      rows[#rows+1]={key=itemKey(x),amount=tonumber(x.size),name=label(x)}
    end
  end
  return rows
end
local function compare()
  local ok,cfg=pcall(dofile,configPath)
  if not ok or type(cfg)~="table" or type(cfg.items)~="table" or type(cfg.fluids)~="table" then
    print("CONFIG REQUIRED: "..configPath)
    print("Example: return {items={address='UUID',side=2}, fluids={{address='UUID',side=3}}}")
    print("Run 'scan' first to identify the actual buffers.")
    return
  end
  local items,err=sourceRows(cfg.items,false)
  if not items then print("ERROR: "..err);return end
  local fluids={}
  for _,source in ipairs(cfg.fluids) do
    local x,e=sourceRows(source,true)
    if not x then print("ERROR: "..e);return end
    for _,row in ipairs(x) do fluids[#fluids+1]=row end
  end
  local function totals(rows)
    local t={}
    for _,row in ipairs(rows) do
      if row.key then t[row.key]=(t[row.key] or 0)+row.amount end
    end
    return t
  end
  local it,ft=totals(items),totals(fluids)
  print("Read-only staging comparison: "..#items.." item stacks; "..#fluids.." fluid contents")
  local match=0
  for _,r in ipairs(patterns()) do
    local required={}
    local safe=r.unknown==0 and #r.items>0
    for _,x in ipairs(r.items) do
      if not x.key or x.qty<=0 then safe=false;break end
      required[x.key]=(required[x.key] or 0)+x.qty
    end
    local count=nil
    for k,n in pairs(required) do
      local qty=it[k] or 0
      if qty<n or qty%n~=0 then safe=false;break end
      local batches=qty/n
      if count and count~=batches then safe=false;break end
      count=batches
    end
    -- Other items in the staging chest mean a different or mixed request.
    for k in pairs(it) do if not required[k] then safe=false end end
    local needed={}
    for _,x in ipairs(r.fluids) do
      if not x.key then safe=false else needed[x.key]=(needed[x.key] or 0)+x.qty end
    end
    for k,n in pairs(needed) do if (ft[k] or 0)<n then safe=false end end
    if safe and count then
      match=match+1
      print("CANDIDATE pattern "..r.slot..": "..r.output.." | item batches="..count)
    end
  end
  if match==0 then print("No complete unique recipe is staged yet.") end
  if match>1 then print("AMBIGUOUS: multiple recipes match. No action allowed.") end
  if match==1 then print("Candidate only. No automated routing until physical distribution is tested.") end
  print("Data Sticks remain manual. Nothing moved.")
end
if cmd=="scan" then scan()
elseif cmd=="patterns" then patterns()
elseif cmd=="compare" then compare()
else print("Commands: scan, patterns, compare") end