-- GTNH 2.9 ME Dual Interface read-only invocation diagnostic
-- No crafting, no configuration changes and no inventory transfers.
local component = require("component")
local addresses = {}
for address in component.list("fluid_interface") do addresses[#addresses + 1] = address end
table.sort(addresses)
print("Dual Interface probe v2 | READ ONLY")
print("fluid_interface components: " .. #addresses)
if #addresses == 0 then return end

local function summarize(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for k in pairs(value) do keys[#keys+1] = k end
  table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
  local entries = {}
  for i=1,math.min(#keys,16) do
    local k=keys[i]
    local v=value[k]
    entries[#entries+1]=tostring(k) .. "=" .. (type(v)=="table" and "{table}" or tostring(v))
  end
  return "{" .. table.concat(entries,", ") .. "}"
end
for _,addr in ipairs(addresses) do
  print("\nAddress: " .. addr)
  local methods=component.methods(addr) or {}
  for _,name in ipairs({"getInterfacePattern","getInterfaceConfiguration","getFluidInterfaceConfiguration"}) do
    local listed = methods[name] ~= nil
    local proxyOk,proxy=pcall(component.proxy,addr)
    local proxyType = proxyOk and proxy and type(proxy[name]) or "unavailable"
    print(name .. ": listed=" .. tostring(listed) .. ", proxy=" .. proxyType)
  end
  print("Invoking getInterfacePattern via component.invoke, slots 0..8:")
  local errors=0
  for slot=0,8 do
    local ok,result,more=pcall(component.invoke,addr,"getInterfacePattern",slot)
    if ok then
      print("  slot " .. slot .. ": " .. summarize(result) .. (more~=nil and (" | extra="..summarize(more)) or ""))
    else
      errors=errors+1
      print("  slot " .. slot .. " ERROR: " .. tostring(result))
      if errors>=3 then
        print("  Stopping after 3 errors.")
        break
      end
    end
  end
end
