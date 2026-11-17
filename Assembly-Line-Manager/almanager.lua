-- Assembly Line Manager, alpha 0.1
-- GTNH 2.9 / OpenComputers: probe, conservative recipe learning and dry-run plans only.
-- No exports, imports, fluid transfers or redstone changes occur in this version.

local component = require("component")
local serialization = require("serialization")
local shell = require("shell")

local configPath = "/home/almanager-config.lua"
local cfg = {
  interfaceAddress = "", stickTransposerAddress = "", stickChestSide = 2,
  patternSlots = 9, maxItemBuses = 16, maxFluidHatches = 4,
  statePath = "/home/almanager-recipes.db",
  diagnosticPath = "/home/almanager-probe.log", dryRun = true
}
local okConfig, userConfig = pcall(dofile, configPath)
if okConfig and type(userConfig) == "table" then
  for k, v in pairs(userConfig) do cfg[k] = v end
end

local function norm(s)
  s = tostring(s or ""):lower()
  s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  return s
end

local function count(v)
  if type(v) == "number" then return v end
  return tonumber(v) or 0
end

local function nameOf(v)
  if type(v) == "string" then return v end
  if type(v) ~= "table" then return nil end
  return v.label or v.displayName or v.display_name or v.localizedName or v.name
end

local function quantity(v, fluid)
  if type(v) ~= "table" then return 0 end
  if fluid then return count(v.amount or v.size or v.count) end
  return count(v.size or v.count or v.amount)
end

local function componentOf(addr, typ)
  if type(addr) ~= "string" or addr == "" then return nil, "address not configured" end
  local ok, p = pcall(component.proxy, addr)
  if not ok or not p then return nil, "component not reachable: " .. addr end
  if typ and p.type ~= typ then
    -- Some wrapped components omit their type; method checks follow.
    if p.type then return nil, "wrong component type: " .. tostring(p.type) end
  end
  return p
end

local function grab(interface, i)
  local ok, item = pcall(interface.getInterfacePattern, i)
  if not ok then return nil, tostring(item) end
  return item
end

local function asPairs(input, preferredFluid)
  local out = {}
  if type(input) ~= "table" then return out, "not a table" end
  for _, v in ipairs(input) do
    if type(v) == "table" then
      local label, n
      -- Data Stick converter uses Scala pairs. Their OC representation
      -- varies with serialization; accept only recognizable structures.
      if type(v[1]) == "string" and (type(v[2]) == "number" or tonumber(v[2])) then
        label, n = v[1], count(v[2])
      else
        label = nameOf(v)
        n = quantity(v, preferredFluid)
      end
      if not label or n <= 0 then return nil, "unrecognized ingredient entry" end
      out[#out + 1] = {name = tostring(label), amount = n}
    else
      return nil, "ingredient entry is not a table"
    end
  end
  return out
end

local function sortedTotals(items, fluids)
  local sums = {}
  local function add(kind, v)
    local key = kind .. ":" .. norm(v.name)
    sums[key] = (sums[key] or 0) + count(v.amount)
  end
  for _, it in ipairs(items) do add("i", it) end
  for _, fl in ipairs(fluids) do add("f", fl) end
  local keys = {}
  for k, v in pairs(sums) do keys[#keys + 1] = k .. "=" .. tostring(v) end
  table.sort(keys)
  return table.concat(keys, "|")
end

local function decodePattern(stack)
  if type(stack) ~= "table" or type(stack.inputs) ~= "table"
      or type(stack.outputs) ~= "table" then
    return nil, "pattern decoder did not expose inputs and outputs"
  end
  if stack.isCraftable == true then return nil, "crafting pattern, not processing pattern" end
  local items, fluids = {}, {}
  for _, v in ipairs(stack.inputs) do
    if type(v) ~= "table" then return nil, "input format unknown" end
    local label = nameOf(v)
    if not label then return nil, "input has no usable name" end
    local isFluid = v.fluid == true or v.type == "fluid" or v.isFluid == true
    local n = quantity(v, isFluid)
    if n < 1 then return nil, "input quantity unknown" end
    local entry = {name = label, amount = n}
    if isFluid then fluids[#fluids + 1] = entry
    else items[#items + 1] = entry end
  end
  local first = stack.outputs[1]
  local output = nameOf(first)
  if not output then return nil, "pattern output unknown" end
  return {output = output, items = items, fluids = fluids,
          signature = sortedTotals(items, fluids)}
end

local function decodeStick(stack, slot)
  if type(stack) ~= "table" or type(stack.output) ~= "string"
      or type(stack.inputItems) ~= "table" then return nil end
  local items, e1 = asPairs(stack.inputItems, false)
  local fluids, e2 = asPairs(stack.inputFluids or {}, true)
  if not items then return nil, e1 end
  if not fluids then return nil, e2 end
  return {output = stack.output, items = items, fluids = fluids,
          signature = sortedTotals(items, fluids), sourceSlot = slot}
end

local function probe()
  print("Assembly Line Manager v0.1: read-only device probe")
  for _, ty in ipairs({"me_interface", "transposer", "inventory_controller",
                        "me_controller", "adapter"}) do
    print("\n" .. ty .. ":")
    local found = 0
    for addr in component.list(ty) do
      found = found + 1
      local p = component.proxy(addr)
      local methods = {}
      for k, v in pairs(p) do
        if type(v) == "function" and
           (k:find("Pattern") or k:find("Fluid") or k:find("Inventory") or
            k:find("Stack") or k:find("transfer")) then
          methods[#methods + 1] = k
        end
      end
      table.sort(methods)
      print(" " .. addr .. " methods: " .. table.concat(methods, ", "))
    end
    if found == 0 then print(" none") end
  end
  print("\nNo inventories or machine settings were changed.")
end

local function readPatterns()
  local dev, e = componentOf(cfg.interfaceAddress)
  if not dev then return nil, e end
  if type(dev.getInterfacePattern) ~= "function" then
    return nil, "configured interface has no getInterfacePattern method"
  end
  local results, skipped = {}, {}
  for slot = 1, cfg.patternSlots do
    local stack, err = grab(dev, slot)
    if err then
      skipped[#skipped + 1] = "Interface slot " .. slot .. ": " .. err
    elseif stack ~= nil then
      local pattern, why = decodePattern(stack)
      if pattern then pattern.sourceSlot = slot; results[#results + 1] = pattern
      else skipped[#skipped + 1] = "Interface slot " .. slot .. ": " .. why end
    end
  end
  return {items = results, issues = skipped}
end

local function readSticks()
  local dev, e = componentOf(cfg.stickTransposerAddress)
  if not dev then return nil, e end
  if type(dev.getInventorySize) ~= "function" or
      type(dev.getStackInSlot) ~= "function" then
    return nil, "configured component does not expose inventory reading methods"
  end
  local ok, size = pcall(dev.getInventorySize, cfg.stickChestSide)
  if not ok or not size then return nil, "research chest not accessible from configured side" end
  local results, skipped = {}, {}
  for slot = 1, size do
    local success, stack = pcall(dev.getStackInSlot, cfg.stickChestSide, slot)
    if success and stack then
      local stick, why = decodeStick(stack, slot)
      if stick then results[#results + 1] = stick
      elseif why then skipped[#skipped + 1] = "Chest slot " .. slot .. ": " .. why end
    end
  end
  return {items = results, issues = skipped, chestSlots = size}
end

local function learn(patterns, sticks)
  local plans, issues = {}, {}
  for _, p in ipairs(patterns) do
    local matches = {}
    for _, s in ipairs(sticks) do
      if norm(s.output) == norm(p.output) and s.signature == p.signature then
        matches[#matches + 1] = s
      end
    end
    if #matches == 1 then
      local s = matches[1]
      if #s.items > cfg.maxItemBuses or #s.fluids > cfg.maxFluidHatches then
        issues[#issues + 1] = p.output .. ": more inputs than configured buses/hatches"
      else
        plans[#plans + 1] = {
          output = p.output, interfaceSlot = p.sourceSlot, stickSlot = s.sourceSlot,
          fingerprint = p.signature, itemBuses = s.items, fluidHatches = s.fluids
        }
      end
    elseif #matches > 1 then
      issues[#issues + 1] = p.output .. ": ambiguous; " .. #matches .. " Data Sticks match"
    else
      issues[#issues + 1] = p.output .. ": no exact researched Data Stick match"
    end
  end
  return plans, issues
end

local function loadCache()
  local file = io.open(cfg.statePath, "r")
  if not file then return {} end
  local s = file:read("*a")
  file:close()
  local ok, data = pcall(serialization.unserialize, s)
  return ok and type(data) == "table" and data or {}
end

local function saveCache(records)
  local f, err = io.open(cfg.statePath .. ".tmp", "w")
  if not f then return nil, err end
  f:write(serialization.serialize(records))
  f:close()
  -- OpenOS rename is available via filesystem, not os.rename in every build.
  local fs = require("filesystem")
  if fs.exists(cfg.statePath) then fs.remove(cfg.statePath) end
  if not fs.rename(cfg.statePath .. ".tmp", cfg.statePath) then
    return nil, "cannot rename temporary recipe cache"
  end
  return true
end

local function scan()
  print("Scanning AE2 patterns and researched Assembly Line Data Sticks...")
  local pats, pe = readPatterns()
  local sticks, se = readSticks()
  if not pats then print("PATTERN ERROR: " .. pe) end
  if not sticks then print("DATA STICK ERROR: " .. se) end
  if not pats or not sticks then
    print("Learning skipped. Run almanager probe and configure device addresses.")
    return
  end
  local plans, issues = learn(pats.items, sticks.items)
  print(("Patterns: %d  Data Sticks: %d  Unambiguous plans: %d"):format(
    #pats.items, #sticks.items, #plans))
  for _, v in ipairs(pats.issues) do print("PATTERN: " .. v) end
  for _, v in ipairs(sticks.issues) do print("STICK: " .. v) end
  for _, v in ipairs(issues) do print("REVIEW: " .. v) end
  -- Save successful matches only. No physical routing.
  local ok, e = saveCache(plans)
  if not ok then print("CACHE ERROR: " .. tostring(e)) end
  print("Read-only scan complete. No ingredients were moved.")
end

local function recipes(verbose)
  local plans = loadCache()
  print("Saved Assembly Line plans: " .. tostring(#plans))
  for _, r in ipairs(plans) do
    print(("%s  interface=%s  stick=%s"):format(
      tostring(r.output), tostring(r.interfaceSlot), tostring(r.stickSlot)))
    if verbose then
      for i, item in ipairs(r.itemBuses or {}) do
        print(("  Item Bus %d: %s x%s"):format(i, item.name, item.amount))
      end
      for i, fluid in ipairs(r.fluidHatches or {}) do
        print(("  Fluid Hatch %d: %s %s L"):format(i, fluid.name, fluid.amount))
      end
    end
  end
  if verbose then print("This is a plan only. Routing is not implemented.") end
end

local function status()
  print("Assembly Line Manager v0.1 / GTNH 2.9 research prototype")
  print("Mode: READ ONLY; transfer actions disabled")
  print("Interface address: " .. (cfg.interfaceAddress ~= "" and cfg.interfaceAddress or "(not configured)"))
  print("Stick transposer: " .. (cfg.stickTransposerAddress ~= "" and cfg.stickTransposerAddress or "(not configured)"))
  print("Cached plans: " .. tostring(#loadCache()))
end

local function help()
  print("Assembly Line Manager - read-only development version")
  print("  almanager probe     List components and suitable methods")
  print("  almanager status    Show setup status")
  print("  almanager scan      Learn conservative plans from patterns + Data Sticks")
  print("  almanager recipes   List cached plans")
  print("  almanager plan      Show exact bus and hatch assignments")
  print("No craft, route, start, or redstone command is enabled in this version.")
end

local args = {...}
local action = args[1] or "status"
if action == "probe" then probe()
elseif action == "scan" then scan()
elseif action == "recipes" then recipes(false)
elseif action == "plan" then recipes(true)
elseif action == "status" then status()
else help() end
