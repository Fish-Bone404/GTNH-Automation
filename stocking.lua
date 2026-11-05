-- GTNH AE2 Stocking Controller: OpenOS background startup service.
-- Install at /etc/rc.d/stocking.lua, then run: rc stocking enable
-- Starts stocking and keeps a refreshed status snapshot separate from diagnostics.

local thread = require("thread")
local filesystem = require("filesystem")
local PROGRAM = "/home/stock.lua"
local STATUS_LOG = "/home/stock-service.log"
local DIAGNOSTIC_LOG = "/home/stock-errors.log"
local worker
local stopping = false

local function log(message)
  local file = io.open(DIAGNOSTIC_LOG, "a")
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
  -- Clear stale dashboard and old diagnostics when starting a new service.
  if filesystem.exists(STATUS_LOG) then filesystem.remove(STATUS_LOG) end
  local file = io.open(DIAGNOSTIC_LOG, "w")
  if file then file:close() end

  worker = thread.create(function()
    os.sleep(10)
    while not stopping do
      if filesystem.exists(PROGRAM) then
        local ok, err = pcall(os.execute, PROGRAM .. " run service >> " .. DIAGNOSTIC_LOG)
        if not ok then log("Stocking command error: " .. tostring(err)) end
      else
        log("Stocking file not found: " .. PROGRAM)
      end

      -- An exited monitor no longer has current status data.
      if filesystem.exists(STATUS_LOG) then filesystem.remove(STATUS_LOG) end

      -- If AE2 or the I/O network was unavailable, try again later.
      if not stopping then os.sleep(30) end
    end
  end):detach()

  print("Stocking service running in background.")
  print("Live status: " .. STATUS_LOG)
  print("Errors: " .. DIAGNOSTIC_LOG)
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
  if filesystem.exists(STATUS_LOG) then filesystem.remove(STATUS_LOG) end
  print("Stocking service stopped. Verify disconnected outputs manually.")
end

function status()
  local running = worker and worker:status() ~= "dead"
  print(running and "Stocking service: RUNNING" or "Stocking service: STOPPED")
  print("Live status: " .. STATUS_LOG)
  print("Errors: " .. DIAGNOSTIC_LOG)
end
