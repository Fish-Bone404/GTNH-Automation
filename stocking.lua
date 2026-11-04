-- GTNH AE2 Stocking Controller: OpenOS background startup service.
-- Install at /etc/rc.d/stocking.lua, then run: rc stocking enable
-- This service starts /home/stock.lua after boot and retries on failure.

local thread = require("thread")
local filesystem = require("filesystem")
local PROGRAM = "/home/stock.lua"
local LOG = "/home/stock-service.log"
local worker
local stopping = false

local function log(message)
  local file = io.open(LOG, "a")
  if file then
    file:write(tostring(message) .. "\n")
    file:close()
  end
end

function start()
  if worker and worker:status() ~= "dead" then
    print("Stocking service is already running.")
    return
  end

  stopping = false
  local file = io.open(LOG, "w")
  if file then
    file:write("Stocking service started.\n")
    file:close()
  end

  worker = thread.create(function()
    os.sleep(10)
    while not stopping do
      if filesystem.exists(PROGRAM) then
        local ok, err = pcall(os.execute, PROGRAM .. " run quiet >> " .. LOG)
        if not ok then log("Stocking command error: " .. tostring(err)) end
      else
        log("Stocking file not found: " .. PROGRAM)
      end

      -- If AE2 or the I/O network was unavailable, try again later.
      if not stopping then os.sleep(30) end
    end
  end):detach()

  print("Stocking service running in background.")
  print("See " .. LOG .. " for stocking status.")
end

function stop()
  stopping = true
  if worker and worker:status() ~= "dead" then worker:kill() end
  worker = nil

  -- Killing a thread does not guarantee its Lua cleanup runs.
  -- Command all currently connected configured outputs OFF separately.
  if filesystem.exists(PROGRAM) then
    local ok, err = pcall(os.execute, PROGRAM .. " off")
    if not ok then
      print("WARNING: Could not command outputs OFF: " .. tostring(err))
    end
  end
  print("Stocking service stopped. Verify disconnected outputs manually.")
end

function status()
  local running = worker and worker:status() ~= "dead"
  print(running and "Stocking service: RUNNING" or "Stocking service: STOPPED")
  print("Log: " .. LOG)
end
