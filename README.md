# GTNH Automation

An OpenComputers AE2 stocking manager for GT New Horizons 2.9. Current version: 1.1. It checks the quantities of registered items and fluids and controls Redstone I/O outputs with low and high stocking limits.

## Install

Use the normal OpenOS terminal, not the Lua interpreter.

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stocking.lua /etc/rc.d/stocking.lua
stock manager
```

If `stock` is not found, enter `cd /home` first.

## Stocking Manager, version 1.0

Enter `stock manager` or just `stock`. The old `stock setup` command also opens the manager.

```text
=== GTNH Stocking Manager ===
1) Redstone I/O devices
2) Select main AE2 network
3) Add item/fluid stocking rule
4) Manage stocking rules
5) Test redstone output (1 second)
6) Automatic stocking: START / STOP / STATUS
7) View current stock and diagnostics
8) Exit
```

**Option 1:** Discover, register, or rename connected Redstone I/O blocks.

**Option 2:** Choose the OpenComputers connection to the main AE2 network.

**Option 3:** Add an item or fluid stocking rule. Select a registered I/O block and an available face. Enter the exact AE2 display name, then the minimum and maximum stocking quantities. The manager identifies and saves the item's registry ID or fluid's internal name automatically. Keep a sample of the material in AE2 during registration.

**Option 4:** View, edit amounts, or remove rules. It also provides an option to optimize old rules. Rules referring to broken I/O blocks can be removed individually. For multiple old rules, use the standalone `stock cleanup` command described below. The cleanup option stays out of the main manager.

**Option 5:** Pulse a Redstone I/O output for one second. Only do this when testing is safe.

**Option 6:** Manage the single **background OpenOS stocking service**:

- START enables startup after future computer or Minecraft server restarts and also starts the service now.
- STOP stops the service now and disables automatic startup after future restarts. Selecting START again re-enables automatic startup, so stocking resumes after subsequent server reboots.
- STATUS shows whether the service is running.

These actions run the OpenOS `rc stocking` service. They do not launch a second manual `stock run` instance. The `stock run` command is no longer a way to start manual stocking. The service's internal `stock run service` command is retained for its operation.

**Option 7:** Read the live stocking status file or the separate diagnostic log.

Stop automatic stocking through option 6 before changing or testing outputs. After you save changes, return to option 6 and start stocking again. New and edited rules are loaded when the background service starts.

## Cleaning up broken Redstone I/O blocks

If I replace a broken or disconnected Redstone I/O block, I can remove its old rules without adding another option to the main manager. First stop stocking through option 6, then enter:

```sh
stock cleanup
```

The program lists rules associated with missing I/O blocks and asks for `REMOVE` to confirm. It deletes only those rules and their unused device registrations. Rules from connected blocks, including their saved item and fluid identities and stocking amounts, are kept.

**Important:** An unloaded or temporarily disconnected I/O block also looks missing. I should only confirm cleanup once I am certain the old block is permanently gone. After installing and registering the replacement block, I can add its new rules and restart automatic stocking through option 6.

The saved settings stay in `/home/stock-config.dat`; `/home/stock-config.dat.bak` stores the previous configuration.

## How stocking works

For example, a rule for Sulfur Dust could start production below 30,000 items and stop at 50,000. Between those amounts, the rule keeps its previous ON/OFF state.

Regular monitoring uses targeted item and fluid lookups. The rules are spread across a 15-second window to avoid one large query burst. Redstone outputs are written on the first reading and when the required state changes, not on every inventory check.

Production continues only if the connected wireless control, pump, shutter, or other receiving hardware responds to the signal. The OpenComputers script does not directly move fluids or items.

## Useful commands

```sh
stock manager
stock list
stock scan
stock optimize
stock testitem Sulfur Dust
stock testfluid Benzene
rc stocking status
cat /home/stock-service.log
cat /home/stock-errors.log
```

The older `stock setup` command is still an alias for `stock manager`. For routine operation, use the manager to start and stop stocking rather than manually running `rc` commands.

The status file is a snapshot with one row per stocking rule. Every completed scan replaces it with the newest amounts and ON/OFF states. It is cleared when the service stops. Startup messages and errors go to the separate diagnostics file.

## Updating

Stop the service before replacing files. You can do that in the manager under option 6 or by entering `rc stocking stop` in an older version.

To update the main program:

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stock.lua /home/stock.lua
stock manager
```

If a release also changes `stocking.lua`, update that file too. OpenOS caches loaded services, so restarting OpenOS after updating the service file is the safest way to reload its code.

```sh
wget -f https://raw.githubusercontent.com/Fish-Bone404/GTNH-Automation/main/stocking.lua /etc/rc.d/stocking.lua
```

Existing stocking rules and device registrations are saved locally in `/home/stock-config.dat`, with a prior backup in `/home/stock-config.dat.bak`. Neither file is uploaded to GitHub or overwritten by a program update.

The service still needs a powered-on OpenComputers computer and loaded chunks for AE2, the computer, and its Redstone I/O components.
