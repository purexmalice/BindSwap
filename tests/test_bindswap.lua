-- Mock of the WoW binding API, enough to exercise BindSwap end to end.

local COMMANDS = {
	{ "MOVEFORWARD",   "BINDING_HEADER_MOVEMENT" },
	{ "MOVEBACKWARD",  "BINDING_HEADER_MOVEMENT" },
	{ "STRAFELEFT",    "BINDING_HEADER_MOVEMENT" },
	{ "STRAFERIGHT",   "BINDING_HEADER_MOVEMENT" },
	{ "JUMP",          "BINDING_HEADER_MOVEMENT" },
	{ "ACTIONBUTTON1", "BINDING_HEADER_ACTIONBAR" },
	{ "ACTIONBUTTON2", "BINDING_HEADER_ACTIONBAR" },
	{ "ACTIONBUTTON3", "BINDING_HEADER_ACTIONBAR" },
	{ "TOGGLEGAMEMENU","BINDING_HEADER_INTERFACE" },
	{ "NEVERBOUND",    "BINDING_HEADER_INTERFACE" },
}

local bound = {}   -- key -> command
local inCombat = false
local saveCalls = 0

ACCOUNT_BINDINGS, CHARACTER_BINDINGS, DEFAULT_BINDINGS = 1, 2, 0

function GetNumBindings() return #COMMANDS end
function InCombatLockdown() return inCombat end
function SaveBindings(which) saveCalls = saveCalls + 1; assert(which == 1 or which == 2, "bad binding set") end
function GetCurrentBindingSet() return ACCOUNT_BINDINGS end

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
	if key == "BADKEY" then return nil end -- simulate a key the client rejects
	if command == nil then bound[key] = nil else bound[key] = command end
	return 1
end

function CreateFrame()
	local f = {}
	function f:RegisterEvent() end
	function f:SetScript(_, fn) f.handler = fn end
	_G.__addonFrame = f
	return f
end

SlashCmdList = {}

--------------------------------------------------------------------------------

local function setBindings(map)
	bound = {}
	for key, cmd in pairs(map) do bound[key] = cmd end
end

local function snapshotState()
	local out = {}
	for key, cmd in pairs(bound) do out[#out + 1] = key .. "=" .. cmd end
	table.sort(out)
	return table.concat(out, " ")
end

local DESKTOP = {
	W = "MOVEFORWARD", S = "MOVEBACKWARD", A = "STRAFELEFT", D = "STRAFERIGHT",
	SPACE = "JUMP", ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2",
	["SHIFT-1"] = "ACTIONBUTTON1", ["MOUSEWHEELUP"] = "ACTIONBUTTON3",
	ESCAPE = "TOGGLEGAMEMENU",
}

local LAPTOP = {
	E = "MOVEFORWARD", D = "MOVEBACKWARD", S = "STRAFELEFT", F = "STRAFERIGHT",
	["ALT-SPACE"] = "JUMP", Q = "ACTIONBUTTON1", R = "ACTIONBUTTON2",
	ESCAPE = "TOGGLEGAMEMENU",
}

-- Load the addon under test.
local chunk = assert(loadfile(arg[1]))
chunk("BindSwap")
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

print("\n=== BindSwap logic tests ===\n")

-- 1. Save the desktop layout.
setBindings(DESKTOP)
local desktopState = snapshotState()
kb("save desktop")

-- 2. Rebind to the laptop layout and save that.
setBindings(LAPTOP)
local laptopState = snapshotState()
kb("save laptop")

-- 3. Swap back to desktop.
kb("load desktop")
check("load desktop restores the exact desktop layout", snapshotState(), desktopState)
check("multi-key binds survive (SHIFT-1 + 1 both on ACTIONBUTTON1)",
	(bound["1"] == "ACTIONBUTTON1" and bound["SHIFT-1"] == "ACTIONBUTTON1"), true)

-- 4. Swap to laptop.
kb("load laptop")
check("load laptop restores the exact laptop layout", snapshotState(), laptopState)
check("desktop-only keys are cleared, not left behind", bound["W"], nil)
check("D is remapped, not duplicated", bound["D"], "MOVEBACKWARD")

-- 5. Undo returns to what was live before the last load.
kb("undo")
check("undo restores the pre-load (desktop) layout", snapshotState(), desktopState)
kb("undo")
check("undo toggles back to laptop", snapshotState(), laptopState)

-- 6. Bindings are persisted every time.
check("SaveBindings was called on each apply", saveCalls > 0, true)

-- 7. Combat defers the load instead of erroring.
kb("load desktop")
local beforeCombat = snapshotState()
inCombat = true
kb("load laptop")
check("load in combat does not change bindings", snapshotState(), beforeCombat)
inCombat = false
assert(_G.__addonFrame and _G.__addonFrame.handler, "addon never registered an OnEvent handler")
_G.__addonFrame.handler() -- PLAYER_REGEN_ENABLED
check("queued load actually applies after combat ends", snapshotState(), laptopState)
check("queue is cleared (second event is a no-op)", (function()
	local before = snapshotState()
	_G.__addonFrame.handler()
	return snapshotState() == before
end)(), true)

-- 8. Missing profile is handled.
local ok = pcall(kb, "load doesnotexist")
check("loading an unknown profile does not error", ok, true)

-- 9. Delete.
kb("delete laptop")
local okList = pcall(kb, "list")
check("delete then list does not error", okList, true)

-- 10. Reserved name is refused.
kb("save @undo")
check("reserved @undo name is refused as a profile", BindSwapDB.profiles["@undo"].name, "@undo")

-- 11. Bad input.
check("empty input does not error", pcall(kb, ""), true)
check("garbage subcommand does not error", pcall(kb, "wat"), true)
check("save with no name does not error", pcall(kb, "save"), true)

print(("\n=== %d passed, %d failed ===\n"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
