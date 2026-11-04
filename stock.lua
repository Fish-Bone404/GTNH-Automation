-- GTNH OpenComputers AE2 Stocking Controller
-- Version 0.3: handle rules left behind by replaced Redstone I/O blocks.
-- Machine assignments live in /home/stock-config.dat, not in this program.

local component = require("component")
local serialization = require("serialization")
local filesystem = require("filesystem")
local sides = require("sides")

local CONFIG = "/home/stock-config.dat"
local TICK_SECONDS = 10
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
  assert(cfg.meAddress, "First select the main AE2 network in setup.")
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

local function readAmount(me, kind, name, fluidsCache)
  local entries
  if kind == "item" then
    entries = me.getItemsInNetwork({label=name})
  elseif kind == "fluid" then
    entries = fluidsCache or me.getFluidsInNetwork()
  else
    error("Invalid kind " .. tostring(kind))
  end
  assert(type(entries) == "table", "AE2 inventory read failed")
  local total, matches = 0, 0
  for _, entry in ipairs(entries) do
    if entry.label == name or (kind == "fluid" and entry.name == name) then
      matches = matches + 1
      local quantity = tonumber(kind == "fluid" and (entry.amount or entry.size)
        or (entry.size or entry.amount))
      assert(quantity, "AE2 returned an invalid quantity for " .. name)
      total = total + quantity
    end
  end
  return total, matches
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
  local ok, quantity, matches = pcall(readAmount, getME(), kind, name)
  if not ok then print("AE2 query error: " .. tostring(quantity)); return end
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
    address=address, side=face, kind=kind, name=name, low=low, high=high
  }
  saveConfig()
  print("Rule saved. It will be OFF until 'stock run' is started.")
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

local function cleanMissingRules()
  local missing = {}
  local addresses = {}
  for i, rule in ipairs(cfg.rules) do
    if not redstoneOnline(rule.address) then
      missing[#missing + 1] = i
      addresses[rule.address] = true
    end
  end
  if #missing == 0 then
    print("No missing I/O rules found.")
    return
  end
  print("Rules from missing I/O blocks:")
  for _, i in ipairs(missing) do
    local rule = cfg.rules[i]
    local info = cfg.blocks[rule.address]
    print(string.format("%d) %s [%s] / %s / %s", i,
      info and info.name or "UNREGISTERED",
      rule.address:sub(1, 8), rule.side, rule.name))
  end
  print("WARNING: Unloaded or disconnected blocks also look missing.")
  print("These saved rules will be deleted, not the physical redstone signals.")
  if ask("Delete the listed rules? Type REMOVE:") ~= "REMOVE" then
    print("Cancelled.")
    return
  end
  for i = #missing, 1, -1 do
    table.remove(cfg.rules, missing[i])
  end
  for address in pairs(addresses) do
    local stillUsed = false
    for _, rule in ipairs(cfg.rules) do
      if rule.address == address then
        stillUsed = true
        break
      end
    end
    if not stillUsed then cfg.blocks[address] = nil end
  end
  saveConfig()
  print("Removed " .. #missing .. " old rules.")
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
  print("Limits updated. Restart 'stock run' to apply them.")
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

local function setup()
  while true do
    print("\n=== GTNH Stocking Setup ===")
    print("1) Discover redstone devices")
    print("2) Register/name a Redstone I/O")
    print("3) Select main AE2 network")
    print("4) Add item/fluid stocking rule")
    print("5) View registered stocking rules")
    print("6) Test an output (1 second)")
    print("7) Remove a stocking rule")
    print("8) Exit")
    print("9) Edit stocking amounts")
    print("10) Clean up rules for missing I/O blocks")
    local choice = ask("Choose:")
    local actions = {
      ["1"]=listRedstone, ["2"]=registerBlock, ["3"]=chooseME,
      ["4"]=addRule, ["5"]=showRules, ["6"]=testOutput,
      ["7"]=removeRule, ["9"]=editRule, ["10"]=cleanMissingRules
    }
    if choice == "8" then return end
    if actions[choice] then
      local ok, err = pcall(actions[choice])
      if not ok then print("Error: " .. tostring(err)) end
    else
      print("Unknown option.")
    end
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

local function run()
  assert(#cfg.rules > 0, "No rules configured. Run 'stock setup' first.")
  getME()
  for _, rule in ipairs(cfg.rules) do
    assert(cfg.blocks[rule.address], "Unknown block in rule: " .. rule.name)
    assert(component.type(rule.address) == "redstone",
      "Disconnected redstone block: " .. cfg.blocks[rule.address].name)
  end
  offAll()
  local state = {}
  local seen = {}
  print("Stocking active, reading every " .. TICK_SECONDS .. " seconds. Ctrl+C stops.")
  local function loop()
    while true do
      local me = getME()
      local fluids = nil
      for _, rule in ipairs(cfg.rules) do
        if component.type(rule.address) ~= "redstone" then
          error("Lost Redstone I/O block: " .. cfg.blocks[rule.address].name)
        end
        if rule.kind == "fluid" and not fluids then
          fluids = me.getFluidsInNetwork()
          assert(type(fluids) == "table", "Fluid inventory read failed")
        end
        local quantity = readAmount(me, rule.kind, rule.name, fluids)
        local key = rule.address .. ":" .. rule.side
        local enabled = state[key] or false
        if quantity < rule.low then enabled = true
        elseif quantity >= rule.high then enabled = false end
        component.proxy(rule.address).setOutput(SIDE_BY_NAME[rule.side], enabled and 15 or 0)
        state[key] = enabled
        print(string.format("%s / %s: %d | %s",
          cfg.blocks[rule.address].name, rule.name, quantity,
          enabled and "ON" or "OFF"))
      end
      for _, address in ipairs(activeRedstone()) do
        if not seen[address] then
          seen[address] = true
          if not cfg.blocks[address] then
            print("New/unregistered redstone component detected: " .. address)
          end
        end
      end
      os.sleep(TICK_SECONDS)
    end
  end
  local ok, err = pcall(loop)
  offAll()
  print(ok and "Stocking stopped." or ("ERROR, stocking stopped: " .. tostring(err)))
  print("Managed connected outputs were commanded OFF.")
  print("Disconnected/unloaded devices cannot be guaranteed OFF.")
end

local args = {...}
local command = args[1] or "help"
if command == "setup" then setup()
elseif command == "scan" then listRedstone()
elseif command == "list" then showRules()
elseif command == "run" then run()
else
  print("GTNH AE2 Stocking Controller v0.3")
  print("stock setup   - discover, name, register and test outputs")
  print("stock scan    - see detected Redstone I/O/cards")
  print("stock list    - view saved rules")
  print("stock run     - begin automatic AE2 monitoring")
  print("Run again after reboot; automatic startup is not enabled.")
  print("Local settings: " .. CONFIG)
end
