-- GTNH OpenComputers AE2 Stocking Controller
-- Version 1.0: Stocking Manager with persistent background service controls.
-- Machine assignments live in /home/stock-config.dat, not in this program.

local component = require("component")
local computer = require("computer")
local serialization = require("serialization")
local filesystem = require("filesystem")
local sides = require("sides")

local CONFIG = "/home/stock-config.dat"
local STATUS_FILE = "/home/stock-service.log"
local TICK_SECONDS = 15
local SIDES = {
  {name="bottom", value=sides.bottom},
  {name="top", value=sides.top},
  {name="north", value=sides.north},
  {name="south", value=sides.south},
  {name="west", value=sides.west},
  {name="east", value=sides.east}
}
local SIDE_BY_NAME = {}
for _, s in ipairs(SIDES) do SIDE_BY_NAME[s.name] = s.value end

local function loadConfig()
  if not filesystem.exists(CONFIG) then
    return {version=1, meAddress=nil, blocks={}, rules={}}
  end
  local f, err = io.open(CONFIG, "r")
  assert(f, err)
  local content = f:read("*a")
  f:close()
  local data = serialization.unserialize(content)
  assert(type(data) == "table" and type(data.blocks) == "table"
    and type(data.rules) == "table", "Config invalid: " .. CONFIG)
  return data
end

local cfg = loadConfig()

local function saveConfig()
  local temp = CONFIG .. ".tmp"
  local f, err = io.open(temp, "w")
  assert(f, err)
  f:write(serialization.serialize(cfg))
  f:close()
  local backup = CONFIG .. ".bak"
  if filesystem.exists(backup) then filesystem.remove(backup) end
  if filesystem.exists(CONFIG) then
    assert(filesystem.rename(CONFIG, backup), "Could not back up configuration")
  end
  local ok, message = filesystem.rename(temp, CONFIG)
  if not ok then
    if filesystem.exists(backup) then filesystem.rename(backup, CONFIG) end
    error("Could not save configuration: " .. tostring(message))
  end
end

local function ask(prompt)
  io.write(prompt .. " ")
  return io.read() or ""
end

local function chooseIndex(maximum, prompt)
  local value = tonumber(ask(prompt))
  if not value or value ~= math.floor(value) or value < 1 or value > maximum then
    print("Invalid selection.")
    return nil
  end
  return value
end

local function activeRedstone()
  local result = {}
  for address, kind in component.list("redstone") do
    if kind == "redstone" then result[#result+1] = address end
  end
  table.sort(result)
  return result
end

local function activeME()
  local result = {}
  for address, kind in component.list() do
    if kind == "me_controller" or kind == "me_interface" then
      result[#result+1] = {address=address, kind=kind}
    end
  end
  table.sort(result, function(a,b) return a.address < b.address end)
  return result
end

local function getME()
  assert(cfg.meAddress, "First select the main AE2 network in Stocking Manager.")
  local kind = component.type(cfg.meAddress)
  assert(kind == "me_controller" or kind == "me_interface",
    "Registered AE2 component disconnected. Check rack/cables.")
  return component.proxy(cfg.meAddress)
end

local function listRedstone()
  local found = activeRedstone()
  print("Connected redstone components: " .. #found)
  for i, address in ipairs(found) do
    local block = cfg.blocks[address]
    local slot = component.slot(address)
    local location = (slot and slot >= 0) and ("installed slot " .. slot) or "external/unknown"
    print(string.format("%d) %s | %s | %s", i, address,
      block and block.name or "UNREGISTERED", location))
  end
  print("Internal Redstone Cards also appear here. Verify the physical block")
  print("with an OpenComputers Analyzer before registering it.")
  return found
end

local function registerBlock()
  local found = listRedstone()
  if #found == 0 then return end
  local index = chooseIndex(#found, "Number of the I/O component to name:")
  if not index then return end
  local address = found[index]
  local name = ask("Friendly name (example: Chemical Plant):")
  if name == "" then print("Cancelled."); return end
  cfg.blocks[address] = {name=name}
  saveConfig()
  print("Registered " .. name .. " as " .. address)
end

local function chooseME()
  local found = activeME()
  if #found == 0 then print("No AE2 Controller/Interface detected."); return end
  for i, item in ipairs(found) do
    local p = component.proxy(item.address)
    local ok, result = pcall(p.getItemsInNetwork)
    local count = ok and type(result) == "table" and #result or "unavailable"
    print(string.format("%d) %s | %s | %s item types", i,
      item.kind, item.address, tostring(count)))
  end
  print("Choose the network that contains your main AE2 inventory.")
  local index = chooseIndex(#found, "AE2 component number:")
  if not index then return end
  cfg.meAddress = found[index].address
  saveConfig()
  print("Saved main AE2 component: " .. cfg.meAddress)
end

-- Called only during item registration/testing, NOT in the 15-second run loop.
-- Display labels are not reliable identifiers for getItemInNetwork.
local function identifyItem(me, label)
  local entries = me.getItemsInNetwork({label=label})
  assert(type(entries) == "table", "Could not resolve item label in AE2")
  local matches = {}
  for _, entry in ipairs(entries) do
    if entry.label == label then matches[#matches+1] = entry end
  end
  assert(#matches > 0, "No stored sample of " .. label .. " found. Add one to AE2.")
  assert(#matches == 1,
    "More than one item variant has the label " .. label ..
    ". Fast lookup needs an exact variant; registration cancelled.")
  local entry = matches[1]
  assert(not entry.hasTag,
    "Item " .. label .. " has NBT data. Fast stocking registration for tagged items is not supported yet.")
  assert(type(entry.name) == "string" and entry.name ~= ""
    and type(entry.damage) == "number",
    "AE2 did not return the registry name and damage for " .. label)
  local key = {name=entry.name, damage=entry.damage}
  local oldAmount = tonumber(entry.size or entry.amount)
  assert(oldAmount, "Invalid item quantity from old lookup for " .. label)
  local result = me.getItemInNetwork(key)
  assert(type(result) == "table",
    "Fast lookup did not find " .. label .. ". Check your GTNH OpenComputers version.")
  assert(result.name == key.name and tonumber(result.damage) == key.damage
      and result.label == label,
    "Fast lookup returned a different item. Keeping the old rule unchanged.")
  local newAmount = tonumber(result.size or result.amount)
  assert(newAmount, "Fast lookup returned an invalid quantity for " .. label)
  assert(newAmount == oldAmount,
    "Old and new quantities differ for " .. label .. " (" ..
    tostring(oldAmount) .. " vs " .. tostring(newAmount) ..
    "). Stop item transfers and test again.")
  return key, newAmount
end

-- Resolve a fluid label to its internal registry name once, outside the run loop.
-- OpenComputers getFluidInNetwork accepts the registry name as a string.
local function identifyFluid(me, label)
  local entries = me.getFluidsInNetwork()
  assert(type(entries) == "table", "Could not read fluids from AE2")
  local matches = {}
  for _, entry in ipairs(entries) do
    if entry.label == label or entry.name == label then
      matches[#matches+1] = entry
    end
  end
  assert(#matches > 0, "No stored sample of " .. label .. ". Add some fluid to AE2.")
  assert(#matches == 1,
    "More than one fluid entry matches " .. label ..
    ". Fast lookup needs a unique fluid; registration cancelled.")
  local entry = matches[1]
  assert(not entry.hasTag,
    "Fluid " .. label .. " has NBT data. Fast stocking registration for tagged fluids is not supported yet.")
  assert(type(entry.name) == "string" and entry.name ~= "",
    "AE2 did not return an internal fluid name for " .. label)
  local key = entry.name
  local oldAmount = tonumber(entry.amount or entry.size)
  assert(oldAmount, "Invalid fluid amount from old lookup for " .. label)
  local result = me.getFluidInNetwork(key)
  assert(type(result) == "table",
    "Fast fluid lookup did not find " .. label .. ". Check your GTNH OpenComputers version.")
  assert(result.name == key and result.label == entry.label,
    "Fast fluid lookup returned a different fluid. No changes saved.")
  local newAmount = tonumber(result.amount or result.size)
  assert(newAmount, "Fast fluid lookup returned an invalid amount for " .. label)
  assert(newAmount == oldAmount,
    "Fluid quantity changed between lookups for " .. label .. " (" ..
    tostring(oldAmount) .. " vs " .. tostring(newAmount) ..
    "). Pause fluid transfers briefly and retry.")
  return key, newAmount
end

-- Monitoring uses the fast, exact-item query. Fluids also use a targeted lookup.
local function readAmount(me, kind, name, itemKey, fluidKey)
  if kind == "item" then
    assert(itemKey, "Item " .. name .. " needs its fast lookup ID. Run 'stock optimize'.")
    local entry = me.getItemInNetwork(itemKey)
    if entry == nil then return 0, 0 end
    assert(type(entry) == "table"
      and entry.name == itemKey.name
      and tonumber(entry.damage) == itemKey.damage
      and entry.label == name, "Fast lookup returned unexpected item for " .. name)
    local quantity = tonumber(entry.size or entry.amount)
    assert(quantity, "Fast lookup returned invalid quantity for " .. name)
    return quantity, 1
  elseif kind == "fluid" then
    assert(type(fluidKey) == "string" and fluidKey ~= "",
      "Fluid " .. name .. " needs its fast lookup ID. Run 'stock optimize'.")
    local entry = me.getFluidInNetwork(fluidKey)
    if entry == nil then return 0, 0 end
    assert(type(entry) == "table" and entry.name == fluidKey
      and (entry.label == name or entry.name == name),
      "Fast lookup returned unexpected fluid for " .. name)
    local quantity = tonumber(entry.amount or entry.size)
    assert(quantity, "Fast lookup returned invalid quantity for " .. name)
    return quantity, 1
  end
  error("Invalid kind " .. tostring(kind))
end

-- Test a known item label without saving anything or changing redstone outputs.
local function testItem(name)
  if name == "" then
    print("Usage: stock testitem Sulfur Dust")
    return
  end
  local ok, key, amount = pcall(identifyItem, getME(), name)
  if not ok then print("TEST FAILED: " .. tostring(key)); return end
  print("PASS: " .. name .. " = " .. tostring(amount))
  print("Registry name: " .. key.name .. " | damage: " .. tostring(key.damage))
  print("Old label lookup and fast getItemInNetwork returned the same quantity.")
end

-- Test a stored fluid without changing saved rules or Redstone I/O outputs.
local function testFluid(name)
  if name == "" then
    print("Usage: stock testfluid Benzene")
    return
  end
  local ok, key, amount = pcall(identifyFluid, getME(), name)
  if not ok then print("TEST FAILED: " .. tostring(key)); return end
  print("PASS: " .. name .. " = " .. tostring(amount))
  print("Internal fluid name: " .. key)
  print("Old and targeted fluid lookups returned the same amount.")
end

-- Resolve legacy rules once, then use only targeted lookups while running.
-- Changes are written only if every pending rule validates successfully.
local function optimizeRules()
  local pending = {}
  local me = getME()
  for i, rule in ipairs(cfg.rules) do
    if rule.kind == "item" and not rule.itemKey then
      print("Identifying item " .. rule.name .. " (rule " .. i .. ")...")
      local ok, key, quantity = pcall(identifyItem, me, rule.name)
      if not ok then
        print("FAILED: " .. tostring(key))
        print("No rules changed. Fix this and run stock optimize again.")
        return
      end
      print("  Verified " .. quantity .. " items.")
      pending[#pending+1] = {index=i, field="itemKey", key=key}
    elseif rule.kind == "fluid" and not rule.fluidKey then
      print("Identifying fluid " .. rule.name .. " (rule " .. i .. ")...")
      local ok, key, quantity = pcall(identifyFluid, me, rule.name)
      if not ok then
        print("FAILED: " .. tostring(key))
        print("No rules changed. Fix this and run stock optimize again.")
        return
      end
      print("  Verified " .. quantity .. " L.")
      pending[#pending+1] = {index=i, field="fluidKey", key=key}
    end
  end
  if #pending == 0 then
    print("All item and fluid rules already use fast lookups.")
    return
  end
  for _, change in ipairs(pending) do
    cfg.rules[change.index][change.field] = change.key
  end
  saveConfig()
  print("Saved fast lookup IDs for " .. #pending .. " rules.")
end

local function registeredOnline()
  local found = activeRedstone()
  local result = {}
  for _, address in ipairs(found) do
    if cfg.blocks[address] then result[#result+1] = address end
  end
  return result
end

local function showOutputSides(address)
  local used = {}
  for _, rule in ipairs(cfg.rules) do
    if rule.address == address then used[rule.side] = rule end
  end

  print("\n=== " .. cfg.blocks[address].name .. " Outputs ===")
  local available = {}
  for i, side in ipairs(SIDES) do
    local rule = used[side.name]
    if rule then
      print(string.format("%d) %-6s IN USE: %s (%s)",
        i, side.name, rule.name, rule.kind))
    else
      print(string.format("%d) %-6s AVAILABLE", i, side.name))
      available[side.name] = true
    end
  end
  return available
end

local function addRule()
  local found = registeredOnline()
  if #found == 0 then print("Register a Redstone I/O block first."); return end
  for i, address in ipairs(found) do
    print(i .. ") " .. cfg.blocks[address].name .. " | " .. address)
  end
  local index = chooseIndex(#found, "Block number:")
  if not index then return end
  local address = found[index]
  local available = showOutputSides(address)
  if not next(available) then
    print("Every side is already assigned. Choose another block.")
    return
  end
  local face = ask("Choose available output (number or side):"):lower()
  local selection = tonumber(face)
  if selection and SIDES[selection] then face = SIDES[selection].name end
  if not SIDE_BY_NAME[face] then print("Unknown side."); return end
  if not available[face] then
    print("That output is already in use. Choose an AVAILABLE side.")
    return
  end
  local kind = ask("Type 'item' or 'fluid':"):lower()
  if kind ~= "item" and kind ~= "fluid" then print("Invalid type."); return end
  local name = ask("Exact AE2 item/fluid label:")
  if name == "" then print("Cancelled."); return end
  local low = tonumber(ask("Start production BELOW quantity:"))
  local high = tonumber(ask("Stop production AT quantity:"))
  if not low or not high or low < 0 or low ~= math.floor(low)
      or high ~= math.floor(high) or high <= low then
    print("Limits invalid. Use whole numbers, with high greater than low.")
    return
  end
  local me = getME()
  local itemKey
  local fluidKey
  local quantity, matches
  if kind == "item" then
    local ok, key, amount = pcall(identifyItem, me, name)
    if not ok then print("Item registration error: " .. tostring(key)); return end
    itemKey = key
    quantity, matches = amount, 1
  elseif kind == "fluid" then
    local ok, key, amount = pcall(identifyFluid, me, name)
    if not ok then print("Fluid registration error: " .. tostring(key)); return end
    fluidKey = key
    quantity, matches = amount, 1
  end
  if matches == 0 then
    print("No matching material currently found in AE2. Check the label.")
    print("For safety, add one sample to AE2 before registering this rule.")
    return
  end
  print(string.format("Found %s: %d stored.", name, quantity))
  if ask("Save this rule? Type YES:") ~= "YES" then
    print("Cancelled."); return
  end
  cfg.rules[#cfg.rules+1] = {
    address=address, side=face, kind=kind, name=name,
    low=low, high=high, itemKey=itemKey, fluidKey=fluidKey
  }
  saveConfig()
  print("Rule saved. Start or restart automatic stocking in Stocking Manager to apply it.")
end

local function redstoneOnline(address)
  local ok, kind = pcall(component.type, address)
  return ok and kind == "redstone"
end

local function showRules()
  print("AE2 source: " .. tostring(cfg.meAddress or "NOT SELECTED"))
  if #cfg.rules == 0 then print("No stocking rules configured.") end
  for i, rule in ipairs(cfg.rules) do
    local block = cfg.blocks[rule.address]
    print(string.format("%d) %s [%s] / %s | %s: %s | ON below %d, OFF at %d | %s",
      i, block and block.name or "UNREGISTERED", rule.address:sub(1, 8),
      rule.side, rule.kind, rule.name, rule.low, rule.high,
      redstoneOnline(rule.address) and "ONLINE" or "MISSING"))
  end
end

local function removeRule()
  showRules()
  if #cfg.rules == 0 then return end
  local index = chooseIndex(#cfg.rules, "Rule number to remove:")
  if not index then return end
  local rule = cfg.rules[index]
  if not redstoneOnline(rule.address) then
    print("Old I/O block is missing. Removing its saved rule.")
  else
    local shared = false
    for i, other in ipairs(cfg.rules) do
      if i ~= index and other.address == rule.address
          and other.side == rule.side then
        shared = true
        break
      end
    end
    if not shared then
      local ok, err = pcall(function()
        component.proxy(rule.address).setOutput(SIDE_BY_NAME[rule.side], 0)
      end)
      if not ok then
        print("WARNING: Could not turn output OFF: " .. tostring(err))
        if ask("Remove rule anyway? Type YES:") ~= "YES" then
          print("Cancelled.")
          return
        end
      end
    end
  end
  table.remove(cfg.rules, index)
  saveConfig()
  print("Rule removed.")
end

local function editRule()
  showRules()
  if #cfg.rules == 0 then return end
  local index = chooseIndex(#cfg.rules, "Rule number to edit:")
  if not index then return end
  local rule = cfg.rules[index]
  print("Editing " .. rule.name .. " (" .. rule.kind .. ")")
  print("Current start below: " .. rule.low)
  print("Current stop at: " .. rule.high)
  local rawLow = ask("New start below (Enter keeps current):")
  local rawHigh = ask("New stop at (Enter keeps current):")
  local low = rawLow == "" and rule.low or tonumber(rawLow)
  local high = rawHigh == "" and rule.high or tonumber(rawHigh)
  if not low or not high or low < 0 or low ~= math.floor(low)
      or high ~= math.floor(high) or high <= low then
    print("Invalid limits. Use whole numbers, high greater than low.")
    return
  end
  print(string.format("New limits for %s: ON below %d, OFF at %d",
    rule.name, low, high))
  if ask("Save changes? Type YES:") ~= "YES" then
    print("Cancelled."); return
  end
  rule.low = low
  rule.high = high
  saveConfig()
  print("Limits updated. Restart automatic stocking in Stocking Manager to apply them.")
end

local function testOutput()
  local found = registeredOnline()
  if #found == 0 then print("Register a Redstone I/O block first."); return end
  for i, address in ipairs(found) do
    print(i .. ") " .. cfg.blocks[address].name .. " | " .. address)
  end
  local index = chooseIndex(#found, "Block number:")
  if not index then return end
  local face = ask("Side to pulse for 1 second:"):lower()
  if not SIDE_BY_NAME[face] then print("Unknown side."); return end
  print("WARNING: This will turn ON anything wired to that output.")
  print("Prefer a test lamp or an otherwise disconnected transmitter.")
  if ask("Type TEST to proceed:") ~= "TEST" then
    print("Cancelled."); return
  end
  local rs = component.proxy(found[index])
  local side = SIDE_BY_NAME[face]
  local ok, err = pcall(function()
    rs.setOutput(side, 15)
    os.sleep(1)
  end)
  local offOK, offErr = pcall(rs.setOutput, side, 0)
  if not offOK then print("WARNING: Could not turn output off: " .. tostring(offErr)) end
  if not ok then print("Test failed: " .. tostring(err))
  else print("Test complete. Output commanded OFF.") end
end

-- The manager uses the same OpenOS rc service that starts on boot.
-- Start both enables autostart and launches it now. Stop does both in reverse.
local SERVICE_FILE = "/etc/rc.d/stocking.lua"
local ERROR_FILE = "/home/stock-errors.log"

local function rcCommand(action)
  if not filesystem.exists(SERVICE_FILE) then
    print("Stocking service not installed: " .. SERVICE_FILE)
    print("Install stocking.lua before using automatic stocking.")
    return false
  end
  local command = "rc stocking " .. action
  local ok, result = pcall(os.execute, command)
  if not ok or result == false or result == nil
      or (type(result) == "number" and result ~= 0) then
    print("Command failed: " .. command)
    if not ok then print(tostring(result)) end
    print("Check /home/stock-errors.log and the OpenOS terminal output.")
    return false
  end
  return true
end

local function startAutomaticStocking()
  if #cfg.rules == 0 then
    print("Add a stocking rule first.")
    return
  end
  print("Enabling automatic startup on future OpenOS boots...")
  if not rcCommand("enable") then return end
  print("Starting the background stocking service...")
  if rcCommand("start") then
    print("Automatic stocking enabled for future boots and started now.")
    print("The live stock list appears after the first completed scan.")
  else
    print("Startup is enabled, but the service did not start successfully.")
  end
end

local function stopAutomaticStocking()
  print("Stopping the background stocking service...")
  local stopped = rcCommand("stop")
  print("Disabling startup on future OpenOS boots...")
  local disabled = rcCommand("disable")
  if stopped and disabled then
    print("Automatic stocking stopped and disabled for future boots.")
  else
    print("Unable to confirm both actions. Check service status.")
  end
end

local function showFile(path, description)
  local file = io.open(path, "r")
  if not file then
    print(description .. " is not available yet: " .. path)
    return
  end
  local contents = file:read("*a") or ""
  file:close()
  if contents == "" then print("No entries in " .. description .. ".")
  else print(contents) end
end

local function redstoneManager()
  while true do
    print("\n=== Redstone I/O Devices ===")
    print("1) Discover connected devices")
    print("2) Register or rename a Redstone I/O")
    print("3) Back")
    local choice = ask("Choose:")
    if choice == "3" then return
    elseif choice == "1" then listRedstone()
    elseif choice == "2" then registerBlock()
    else print("Unknown option.") end
  end
end

local function rulesManager()
  while true do
    print("\n=== Stocking Rules ===")
    print("1) View saved rules")
    print("2) Edit stocking amounts")
    print("3) Remove a rule")
    print("4) Optimize existing lookup keys")
    print("5) Back")
    local choice = ask("Choose:")
    if choice == "5" then return
    elseif choice == "1" then showRules()
    elseif choice == "2" then editRule()
    elseif choice == "3" then removeRule()
    elseif choice == "4" then optimizeRules()
    else print("Unknown option.") end
  end
end

local function automaticManager()
  while true do
    print("\n=== Automatic Stocking ===")
    print("1) START now and on future server restarts")
    print("2) STOP now and disable future automatic startup")
    print("3) Check service status")
    print("4) Back")
    local choice = ask("Choose:")
    if choice == "4" then return
    elseif choice == "1" then startAutomaticStocking()
    elseif choice == "2" then stopAutomaticStocking()
    elseif choice == "3" then rcCommand("status")
    else print("Unknown option.") end
  end
end

local function statusManager()
  while true do
    print("\n=== Stocking Status ===")
    print("1) View latest quantities and ON/OFF states")
    print("2) View errors and diagnostics")
    print("3) Back")
    local choice = ask("Choose:")
    if choice == "3" then return
    elseif choice == "1" then showFile(STATUS_FILE, "Live stocking status")
    elseif choice == "2" then showFile(ERROR_FILE, "Stocking diagnostics")
    else print("Unknown option.") end
  end
end

local function manager()
  while true do
    print("\n=== GTNH Stocking Manager ===")
    print("1) Redstone I/O devices")
    print("2) Select main AE2 network")
    print("3) Add item/fluid stocking rule")
    print("4) Manage stocking rules")
    print("5) Test redstone output (1 second)")
    print("6) Automatic stocking: START / STOP / STATUS")
    print("7) View current stock and diagnostics")
    print("8) Exit")
    print("Stop automatic stocking before editing rules; start it again after.")
    local choice = ask("Choose:")
    local actions = {
      ["1"]=redstoneManager, ["2"]=chooseME, ["3"]=addRule,
      ["4"]=rulesManager, ["5"]=testOutput,
      ["6"]=automaticManager, ["7"]=statusManager
    }
    if choice == "8" then return end
    if actions[choice] then
      local ok, err = pcall(actions[choice])
      if not ok then print("Error: " .. tostring(err)) end
    else print("Unknown option.") end
  end
end

local function offAll()
  for _, rule in ipairs(cfg.rules) do
    local available, kind = pcall(component.type, rule.address)
    if available and kind == "redstone" then
      local ok, rs = pcall(component.proxy, rule.address)
      if ok then pcall(rs.setOutput, SIDE_BY_NAME[rule.side], 0) end
    end
  end
end

-- Rewrite one current-state snapshot after every completed scan.
-- This file is a dashboard, not a history of events.
local function writeStatusSnapshot(rows)
  local lines = {}
  for i, rule in ipairs(cfg.rules) do
    local current = rows[i]
    if current then
      local block = cfg.blocks[rule.address]
      lines[#lines+1] = string.format("%s / %s: %d %s | %s",
        block and block.name or "UNREGISTERED", rule.name,
        current.quantity, rule.kind == "fluid" and "L" or "items",
        current.enabled and "ON" or "OFF")
    end
  end
  -- Opening in write mode replaces the previous snapshot, so no duplicates
  -- or outdated quantities remain after a completed scan.
  local file, err = io.open(STATUS_FILE, "w")
  if not file then return false, err end
  local ok, writeErr = pcall(function()
    file:write(table.concat(lines, "\n"), "\n")
  end)
  file:close()
  if not ok then return false, writeErr end
  return true
end

local function run(quiet, serviceMode)
  assert(#cfg.rules > 0, "No rules configured. Run 'stock setup' first.")
  getME()
  for _, rule in ipairs(cfg.rules) do
    if rule.kind == "item" then
      assert(rule.itemKey,
        "Item rule " .. rule.name .. " needs fast lookup registration. Run 'stock optimize'.")
    elseif rule.kind == "fluid" then
      assert(type(rule.fluidKey) == "string" and rule.fluidKey ~= "",
        "Fluid rule " .. rule.name .. " needs fast lookup registration. Run 'stock optimize'.")
    end
    assert(cfg.blocks[rule.address], "Unknown block in rule: " .. rule.name)
    assert(component.type(rule.address) == "redstone",
      "Disconnected redstone block: " .. cfg.blocks[rule.address].name)
  end

  -- Command OFF first. The first check of every rule always writes its output.
  offAll()
  local state = {}
  local seen = {}
  local latest = {}
  local checkSpacing = TICK_SECONDS / #cfg.rules
  if not serviceMode then
    print(string.format(
      "Stocking active: %d rules spread across %d seconds (%.3f seconds apart).",
      #cfg.rules, TICK_SECONDS, checkSpacing))
    print("Ctrl+C stops. Redstone is written on initial checks and state changes.")
  end

  local function loop()
    -- Monotonic clock avoids schedule drift from variable query duration.
    local nextCheck = computer.uptime()
    while true do
      local cycleStart = computer.uptime()
      local me = getME()
      for index, rule in ipairs(cfg.rules) do
        -- Start a new lookup at its scheduled slot, not in one large burst.
        local remaining = nextCheck - computer.uptime()
        if remaining > 0 then os.sleep(remaining) end

        if component.type(rule.address) ~= "redstone" then
          error("Lost Redstone I/O block: " .. cfg.blocks[rule.address].name)
        end

        local quantity = readAmount(me, rule.kind, rule.name, rule.itemKey, rule.fluidKey)
        local key = rule.address .. ":" .. rule.side
        local previous = state[key]
        local enabled = previous or false
        if quantity < rule.low then enabled = true
        elseif quantity >= rule.high then enabled = false end

        if previous == nil or previous ~= enabled then
          -- First check or changed state: write the appropriate output.
          component.proxy(rule.address).setOutput(SIDE_BY_NAME[rule.side], enabled and 15 or 0)
        end

        if not quiet or previous == nil or previous ~= enabled then
          print(string.format("%s / %s: %d | %s",
            cfg.blocks[rule.address].name, rule.name, quantity,
            enabled and "ON" or "OFF"))
        end
        state[key] = enabled
        latest[index] = {quantity=quantity, enabled=enabled}

        -- Clamp a missed slot so a slow AE2 query doesn't cause catch-up bursts.
        nextCheck = nextCheck + checkSpacing
        local now = computer.uptime()
        if nextCheck < now then nextCheck = now end
      end

      -- Discover new I/O components once per full cycle, not per rule.
      for _, address in ipairs(activeRedstone()) do
        if not seen[address] then
          seen[address] = true
          if not cfg.blocks[address] then
            print("New/unregistered redstone component detected: " .. address)
          end
        end
      end

      -- Write only the latest value for each rule, after a complete sweep.
      -- Older readings are replaced, not appended.
      if serviceMode then
        local snapshotOK, snapshotErr = writeStatusSnapshot(latest)
        if not snapshotOK then
          print("WARNING: Could not update live status: " .. tostring(snapshotErr))
        end
      end

      local elapsed = computer.uptime() - cycleStart
      if elapsed > TICK_SECONDS + 0.5 then
        print(string.format("WARNING: %d-rule scan took %.2f seconds; exceeds %d-second target.",
          #cfg.rules, elapsed, TICK_SECONDS))
      end
      -- No extra sleep here. nextCheck already spaces queries across each window.
    end
  end

  local ok, err = pcall(loop)
  offAll()
  -- Never leave a stale ON/OFF dashboard after the monitor exits.
  if serviceMode and filesystem.exists(STATUS_FILE) then
    filesystem.remove(STATUS_FILE)
  end
  print(ok and "Stocking stopped." or ("ERROR, stocking stopped: " .. tostring(err)))
  print("Managed connected outputs were commanded OFF.")
  print("Disconnected/unloaded devices cannot be guaranteed OFF.")
end

local args = {...}
local command = args[1] or "manager"
if command == "manager" or command == "setup" then manager()
elseif command == "scan" then listRedstone()
elseif command == "list" then showRules()
elseif command == "optimize" then optimizeRules()
elseif command == "testitem" then testItem(table.concat(args, " ", 2))
elseif command == "testfluid" then testFluid(table.concat(args, " ", 2))
elseif command == "run" and args[2] == "service" then run(true, true)
elseif command == "run" then
  print("Use 'stock manager' to start or stop the persistent background service.")
elseif command == "off" then
  offAll()
  print("Managed online Redstone I/O outputs commanded OFF.")
else
  print("GTNH Stocking Manager v1.0")
  print("stock manager  - open the main manager and automatic service controls")
  print("stock setup    - legacy alias for Stocking Manager")
  print("stock list     - view saved stocking rules")
  print("stock scan     - discover connected Redstone I/O devices")
  print("stock optimize - identify older item and fluid rule keys")
  print("stock testitem Sulfur Dust - test item lookup")
  print("stock testfluid Benzene - test fluid lookup")
  print("stock off      - command all managed connected outputs OFF")
  print("Local configuration: " .. CONFIG)
end
