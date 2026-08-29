-- Mocks enough of the WoW API to exercise BindSwap's Core.lua outside the game.
-- UI.lua is not covered here; it needs the real frame system.
--
--   lua tests/test_core.lua BindSwap/Core.lua

local COMMANDS = {
	{ "MOVEFORWARD",    "BINDING_HEADER_MOVEMENT" },
	{ "MOVEBACKWARD",   "BINDING_HEADER_MOVEMENT" },
	{ "STRAFELEFT",     "BINDING_HEADER_MOVEMENT" },
	{ "STRAFERIGHT",    "BINDING_HEADER_MOVEMENT" },
	{ "JUMP",           "BINDING_HEADER_MOVEMENT" },
	{ "ACTIONBUTTON1",  "BINDING_HEADER_ACTIONBAR" },
	{ "ACTIONBUTTON2",  "BINDING_HEADER_ACTIONBAR" },
	{ "ACTIONBUTTON3",  "BINDING_HEADER_ACTIONBAR" },
	{ "TOGGLEGAMEMENU", "BINDING_HEADER_INTERFACE" },
	{ "NEVERBOUND",     "BINDING_HEADER_INTERFACE" },
}

local bound = {}
local inCombat = false
local saveCalls = 0
local frames = {}
local timers = {}

ACCOUNT_BINDINGS, CHARACTER_BINDINGS, DEFAULT_BINDINGS = 1, 2, 0

function GetNumBindings() return #COMMANDS end
function InCombatLockdown() return inCombat end
function GetCurrentBindingSet() return ACCOUNT_BINDINGS end
function UnitName() return "Testchar" end
function GetRealmName() return "Testrealm" end

function SaveBindings(which)
	saveCalls = saveCalls + 1
	assert(which == 1 or which == 2, "SaveBindings got a bad binding set: " .. tostring(which))
end

function GetBindingKey(command)
	local keys = {}
	for key, cmd in pairs(bound) do
		if cmd == command then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return unpack(keys)
end

function GetBinding(index)
	local entry = COMMANDS[index]
	if not entry then return nil end
	return entry[1], entry[2], GetBindingKey(entry[1])
end

function SetBinding(key, command)
	if type(key) ~= "string" or key == "" then return nil end
	if command == nil then bound[key] = nil else bound[key] = command end
	return 1
end

function CreateFrame()
	local f = { events = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(_, fn) self.handler = fn end
	frames[#frames + 1] = f
	return f
end

-- Defer timers so we control when login autoload actually fires.
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

local function fireEvent(event)
	for _, f in ipairs(frames) do
		if f.events[event] and f.handler then f.handler(f, event) end
	end
end

local function runTimers()
	local queued = timers
	timers = {}
	for _, fn in ipairs(queued) do fn() end
end

SlashCmdList = {}

--------------------------------------------------------------------------------

local function setBindings(map)
	bound = {}
	for key, cmd in pairs(map) do bound[key] = cmd end
end

local function state()
	local out = {}
	for key, cmd in pairs(bound) do out[#out + 1] = key .. "=" .. cmd end
	table.sort(out)
	return table.concat(out, " ")
end

local DESKTOP = {
	W = "MOVEFORWARD", S = "MOVEBACKWARD", A = "STRAFELEFT", D = "STRAFERIGHT",
	SPACE = "JUMP", ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2",
	["SHIFT-1"] = "ACTIONBUTTON1", MOUSEWHEELUP = "ACTIONBUTTON3",
	ESCAPE = "TOGGLEGAMEMENU",
}

local LAPTOP = {
	E = "MOVEFORWARD", D = "MOVEBACKWARD", S = "STRAFELEFT", F = "STRAFERIGHT",
	["ALT-SPACE"] = "JUMP", Q = "ACTIONBUTTON1", R = "ACTIONBUTTON2",
	ESCAPE = "TOGGLEGAMEMENU",
}

-- Load the addon under test, capturing its private namespace.
local ns = {}
assert(loadfile(arg[1]))("BindSwap", ns)
local kb = SlashCmdList.BINDSWAP
assert(kb, "slash handler not registered")

local pass, fail = 0, 0
local function check(label, got, want)
	if got == want then
		pass = pass + 1
		print(("  PASS  %s"):format(label))
	else
		fail = fail + 1
		print(("  FAIL  %s\n        got:  %s\n        want: %s"):format(label, tostring(got), tostring(want)))
	end
end

print("\n=== BindSwap core tests ===\n")

--------------------------------------------------------------------------------
print("-- profiles --")

setBindings(DESKTOP)
local desktopState = state()
kb("save desktop")

setBindings(LAPTOP)
local laptopState = state()
kb("save laptop")

kb("load desktop")
check("load restores the exact desktop layout", state(), desktopState)
check("multi-key binds survive (1 and SHIFT-1 both on ACTIONBUTTON1)",
	bound["1"] == "ACTIONBUTTON1" and bound["SHIFT-1"] == "ACTIONBUTTON1", true)

kb("load laptop")
check("load restores the exact laptop layout", state(), laptopState)
check("keys only in the old profile are cleared", bound["W"], nil)
check("a key reused by both profiles is remapped, not duplicated", bound["D"], "MOVEBACKWARD")
check("SaveBindings is called on every apply", saveCalls > 0, true)

--------------------------------------------------------------------------------
print("-- undo --")

kb("undo")
check("undo restores the pre-load layout", state(), desktopState)
kb("undo")
check("undo toggles back", state(), laptopState)

--------------------------------------------------------------------------------
print("-- autoload (per character) --")

check("no autoload by default", ns.GetAutoload(), nil)

kb("auto desktop")
check("autoload can be set by name", ns.GetAutoload().name, "desktop")
check("autoload is stored per character, not account-wide", BindSwapCharDB.autoload, "desktop")

ns.ToggleAutoload("desktop")
check("toggling the same profile clears autoload", ns.GetAutoload(), nil)

ns.ToggleAutoload("desktop")
check("toggling again re-arms it", ns.GetAutoload().name, "desktop")

kb("auto off")
check("/kb auto off clears it", ns.GetAutoload(), nil)

--------------------------------------------------------------------------------
print("-- autoload fires at login --")

ns.SetAutoload("desktop")
setBindings(LAPTOP)
fireEvent("PLAYER_LOGIN")
check("login does not apply bindings before the timer runs", state(), laptopState)
runTimers()
check("autoload applies the character's profile at login", state(), desktopState)

setBindings(LAPTOP)
runTimers()
fireEvent("PLAYER_LOGIN")
runTimers()
check("autoload only runs once per session", state(), laptopState)

--------------------------------------------------------------------------------
print("-- combat --")

kb("load desktop")
local beforeCombat = state()
inCombat = true
kb("load laptop")
check("a load during combat changes nothing", state(), beforeCombat)
inCombat = false
fireEvent("PLAYER_REGEN_ENABLED")
check("the queued load applies once combat ends", state(), laptopState)

local settled = state()
fireEvent("PLAYER_REGEN_ENABLED")
check("the queue is cleared, so a second event is a no-op", state(), settled)

--------------------------------------------------------------------------------
print("-- rename and delete --")

ns.SetAutoload("desktop")
check("rename succeeds", ns.Rename("desktop", "battlestation"), "battlestation")
check("the old name is gone", ns.Get("desktop"), nil)
check("the bindings came with it", ns.CountKeys(ns.Get("battlestation").bindings), 10)
check("autoload follows the rename", ns.GetAutoload().name, "battlestation")

local ok, err = ns.Rename("battlestation", "laptop")
check("renaming onto an existing name is refused", ok, nil)
check("...with a useful message", err, "A profile named laptop already exists.")

ns.Delete("battlestation")
check("deleting the autoload profile clears autoload", ns.GetAutoload(), nil)
check("...and removes the profile", ns.Get("battlestation"), nil)

--------------------------------------------------------------------------------
print("-- guards --")

check("names are case-insensitive", ns.Get("LAPTOP") ~= nil, true)
check("the reserved @undo name is refused", select(2, ns.Save("@undo")), "@undo is reserved. Pick another name.")

setBindings({})
check("saving with nothing bound is refused", select(2, ns.Save("empty")),
	"You have no keys bound -- nothing to save.")
setBindings(LAPTOP)

check("loading an unknown profile does not error", pcall(kb, "load nope"), true)
check("empty input does not error", pcall(kb, ""), true)
check("garbage subcommand does not error", pcall(kb, "wat"), true)
check("save with no name does not error", pcall(kb, "save"), true)
check("rename with no args does not error", pcall(kb, "rename"), true)
check("auto with an unknown profile does not error", pcall(kb, "auto nope"), true)
check("list does not error", pcall(kb, "list"), true)

print(("\n=== %d passed, %d failed ===\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
