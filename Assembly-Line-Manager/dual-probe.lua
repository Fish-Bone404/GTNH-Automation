-- GTNH 2.9 Assembly Line Manager: ME Dual Interface diagnostic
-- READ ONLY. Does not change patterns, network contents, or redstone.
local component = require("component")
local addresses = {}
for address in component.list("fluid_interface") do addresses[#addresses + 1] = address end
table.sort(addresses)
print("ME Dual Interface probe | READ ONLY")
print("fluid_interface components: " .. #addresses)
if #addresses == 0 then
  print("No fluid_interface found. Check OC adapter/cable connection.")
  return
end
local function describe(value)
  if type(value) == "table" then
    local parts = {}
    for k, v in pairs(value) do
      if type(v) == "table" then
        parts[#parts + 1] = tostring(k) .. "={table}"
      else
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
      end
      if #parts >= 12 then break end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(value)
end
for _, addr in ipairs(addresses) do
  print("\nAddress: " .. addr)
  local methods = component.methods(addr) or {}
  local patternMethods = {}
  for name in pairs(methods) do
    if name:lower():find("pattern") or name:lower():find("interface") then
      patternMethods[#patternMethods + 1] = name
    end
  end
  table.sort(patternMethods)
  print("Relevant API methods:")
  for _, name in ipairs(patternMethods) do print("  " .. name) end
  local proxy = component.proxy(addr)
  if type(proxy.getInterfacePattern) == "function" then
    print("Reading pattern slots 0-35 safely:")
    local successful = 0
    local returned = 0
    for slot = 0, 35 do
      local ok, result = pcall(proxy.getInterfacePattern, slot)
      if ok then
        successful = successful + 1
        if result ~= nil then
          returned = returned + 1
          print("  slot " .. slot .. ": " .. describe(result))
        end
      elseif slot == 0 or slot == 1 then
        print("  slot " .. slot .. " error: " .. tostring(result))
      end
    end
    print("Successful calls: " .. successful .. "; non-nil slots: " .. returned)
  else
    print("getInterfacePattern is not available on this component.")
  end
end
