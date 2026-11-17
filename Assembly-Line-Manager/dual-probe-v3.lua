-- GTNH 2.9 Assembly Line Manager: dual interface pattern shape probe v3
-- READ ONLY. No crafting, no changes to inventory, fluid or pattern configuration.
local component = require("component")
local function safe(v)
  if type(v)=="string" then
    local s=v:gsub("[^%g%s]","?")
    return (#s>90 and s:sub(1,90).."...") or s
  end
  if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
  return type(v)
end
local function describe(v,depth)
  if type(v)~="table" then return safe(v) end
  if depth>=2 then return "{table}" end
  local keys={}
  for k in pairs(v) do
    if k~="tag" and k~="nbt" and k~="rawTag" and k~="encodedPattern" then keys[#keys+1]=k end
  end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  local t={}
  for i=1,math.min(12,#keys) do
    local k=keys[i]
    local x=v[k]
    if type(x)=="table" and depth==0 then
      t[#t+1]=tostring(k).."="..describe(x,depth+1)
    else
      t[#t+1]=tostring(k).."="..safe(x)
    end
  end
  return "{"..table.concat(t,", ").."}"
end
local addresses={}
for a in component.list("fluid_interface") do addresses[#addresses+1]=a end
table.sort(addresses)
print("Dual Interface probe v3 | READ ONLY")
print("Detected Dual Interfaces: "..#addresses)
for _,addr in ipairs(addresses) do
  print("Address: "..addr)
  for slot=1,9 do
    local ok,p=pcall(component.invoke,addr,"getInterfacePattern",slot)
    if not ok then
      print("Slot "..slot.." ERROR: "..safe(p))
    elseif p~=nil then
      print("Slot "..slot..": "..describe(p,0))
      for _,field in ipairs({"inputs","outputs"}) do
        local list=type(p)=="table" and p[field] or nil
        if type(list)=="table" then
          local keys={}
          for k in pairs(list) do keys[#keys+1]=k end
          table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
          print("  "..field.." entries: "..#keys)
          for i=1,math.min(16,#keys) do
            local k=keys[i]
            print("    "..tostring(k)..": "..describe(list[k],0))
          end
        else
          print("  "..field..": "..safe(list))
        end
      end
    end
  end
  for _,method in ipairs({"getInterfaceConfiguration","getFluidInterfaceConfiguration"}) do
    -- Only probe configuration without arguments. Errors are printed, not retried with guesses.
    local ok,result=pcall(component.invoke,addr,method)
    if ok then
      print(method..": "..describe(result,0))
    else
      print(method.." requires arguments or is unavailable: "..safe(result))
    end
  end
end
