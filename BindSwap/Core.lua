-- BindSwap core: the binding engine, the profile store, and slash commands.
-- Deliberately independent of UI.lua so the addon still works if the window
-- fails to build on a future patch.

local ADDON, ns = ...

local PREFIX = "|cff33ff99BindSwap|r: "
local BACKUP = "@undo" -- reserved profile, rewritten on every load

ns.BACKUP = BACKUP

local pendingLoad -- profile queued because we were in combat
local autoloadDone -- autoload runs once per session, not per loading screen

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

function ns.Print(msg, ...)
	if select("#", ...) > 0 then
		msg = string.format(msg, ...)
	end
	print(PREFIX .. msg)
end

local Print = ns.Print

function ns.Trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function ns.CharacterKey()
	local name = UnitName("player")
	local realm = GetRealmName()
	if not name then return "?" end
	return realm and (name .. " - " .. realm) or name
end

-- Callbacks so the UI can redraw itself after any mutation.
local listeners = {}

function ns.OnChanged(fn)
	listeners[#listeners + 1] = fn
end

function ns.Changed()
	for _, fn in ipairs(listeners) do
		pcall(fn)
	end
end

--------------------------------------------------------------------------------
-- Binding engine
--------------------------------------------------------------------------------

-- Bindings save into either the account-wide or the character-specific set.
-- Mirror whichever set the player is on so a swap doesn't silently move their
-- bindings between the two.
local function CurrentBindingSet()
	if type(GetCurrentBindingSet) == "function" then
		local set = GetCurrentBindingSet()
		if set == ACCOUNT_BINDINGS or set == CHARACTER_BINDINGS then
			return set
		end
	end
	return ACCOUNT_BINDINGS
end

ns.CurrentBindingSet = CurrentBindingSet

-- Record the keys attached to every binding command. GetBindingKey returns
-- *all* keys as varargs, not just the two the default UI shows, so commands
-- with extra binds survive the round trip.
function ns.Snapshot()
	local bindings, count = {}, 0
	for i = 1, GetNumBindings() do
		local command = GetBinding(i)
		if command then
			local keys = { GetBindingKey(command) }
			if #keys > 0 then
				bindings[command] = keys
				count = count + #keys
			end
		end
	end
	return bindings, count
end

local function ClearAllBindings()
	-- Collect first, then clear, so we aren't mutating bindings mid-read.
	local keys = {}
	for i = 1, GetNumBindings() do
		local command = GetBinding(i)
		if command then
			for _, key in ipairs({ GetBindingKey(command) }) do
				keys[#keys + 1] = key
			end
		end
	end
	for _, key in ipairs(keys) do
		SetBinding(key)
	end
end

local function Apply(bindings)
	ClearAllBindings()

	local applied, failed = 0, {}
	for command, keys in pairs(bindings) do
		for _, key in ipairs(keys) do
			if SetBinding(key, command) then
				applied = applied + 1
			else
				failed[#failed + 1] = key .. " -> " .. command
			end
		end
	end

	SaveBindings(CurrentBindingSet())
	return applied, failed
end

ns.Apply = Apply

function ns.CountKeys(bindings)
	local count = 0
	for _, keys in pairs(bindings or {}) do
		count = count + #keys
	end
	return count
end

--------------------------------------------------------------------------------
-- Profile store
--------------------------------------------------------------------------------

function ns.DB()
	BindSwapDB = BindSwapDB or {}
	BindSwapDB.profiles = BindSwapDB.profiles or {}
	return BindSwapDB
end

function ns.CharDB()
	BindSwapCharDB = BindSwapCharDB or {}
	return BindSwapCharDB
end

function ns.Key(name)
	return ns.Trim(name):lower()
end

function ns.Get(name)
	return ns.DB().profiles[ns.Key(name)]
end

-- Every profile except the reserved undo slot, sorted for stable display.
function ns.List()
	local out = {}
	for key, profile in pairs(ns.DB().profiles) do
		if key ~= BACKUP then
			out[#out + 1] = profile
		end
	end
	table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
	return out
end

function ns.Save(name)
	name = ns.Trim(name)
	if name == "" then
		return nil, "Give the profile a name."
	end
	if ns.Key(name) == BACKUP then
		return nil, string.format("%s is reserved. Pick another name.", BACKUP)
	end

	local bindings, count = ns.Snapshot()
	if count == 0 then
		return nil, "You have no keys bound -- nothing to save."
	end

	local existing = ns.Get(name)
	ns.DB().profiles[ns.Key(name)] = {
		name = existing and existing.name or name,
		bindings = bindings,
	}
	ns.DB().current = existing and existing.name or name
	ns.Changed()
	return count, nil, existing ~= nil
end

function ns.Delete(name)
	local profile = ns.Get(name)
	if not profile then
		return nil, string.format("No profile named %s.", name)
	end

	ns.DB().profiles[ns.Key(name)] = nil
	if ns.CharDB().autoload == ns.Key(name) then
		ns.CharDB().autoload = nil
	end
	if ns.DB().current == profile.name then
		ns.DB().current = nil
	end
	ns.Changed()
	return profile.name
end

function ns.Rename(oldName, newName)
	local profile = ns.Get(oldName)
	if not profile then
		return nil, string.format("No profile named %s.", oldName)
	end

	newName = ns.Trim(newName)
	if newName == "" then
		return nil, "Give the profile a name."
	end
	if ns.Key(newName) == BACKUP then
		return nil, string.format("%s is reserved. Pick another name.", BACKUP)
	end
	if ns.Get(newName) and ns.Key(newName) ~= ns.Key(oldName) then
		return nil, string.format("A profile named %s already exists.", newName)
	end

	local wasAutoload = ns.CharDB().autoload == ns.Key(oldName)
	ns.DB().profiles[ns.Key(oldName)] = nil
	profile.name = newName
	ns.DB().profiles[ns.Key(newName)] = profile
	if wasAutoload then
		ns.CharDB().autoload = ns.Key(newName)
	end
	ns.Changed()
	return newName
end

--------------------------------------------------------------------------------
-- Load
--------------------------------------------------------------------------------

function ns.Load(name, quiet)
	local profile = ns.Get(name)
	if not profile then
		Print("no profile named |cffffff00%s|r. Try |cffffff00/kb list|r.", tostring(name))
		return false
	end

	if InCombatLockdown() then
		pendingLoad = profile.name
		Print("in combat -- will load |cffffff00%s|r when you drop out.", profile.name)
		return false
	end

	-- Stash the live setup so a mistaken load is one click away from undone.
	ns.DB().profiles[BACKUP] = { name = BACKUP, bindings = ns.Snapshot() }

	local applied, failed = Apply(profile.bindings)
	ns.DB().current = profile.name
	ns.Changed()

	if not quiet then
		Print("loaded |cffffff00%s|r (%d keys).", profile.name, applied)
	end
	if #failed > 0 then
		Print("|cffff5555%d key(s) failed to bind:|r %s", #failed, table.concat(failed, ", "))
	end
	return true
end

function ns.Undo()
	local backup = ns.DB().profiles[BACKUP]
	if not backup then
		Print("nothing to undo.")
		return false
	end
	if InCombatLockdown() then
		Print("can't change binds in combat.")
		return false
	end

	local current = ns.Snapshot()
	local applied = Apply(backup.bindings)
	-- Make undo a toggle: what we just replaced becomes the new backup.
	ns.DB().profiles[BACKUP] = { name = BACKUP, bindings = current }
	ns.DB().current = nil
	ns.Changed()

	Print("restored the previous binds (%d keys).", applied)
	return true
end

--------------------------------------------------------------------------------
-- Per-character autoload
--------------------------------------------------------------------------------

function ns.GetAutoload()
	local key = ns.CharDB().autoload
	if not key then return nil end

	local profile = ns.DB().profiles[key]
	if not profile then
		-- Profile was deleted out from under us.
		ns.CharDB().autoload = nil
		return nil
	end
	return profile
end

function ns.SetAutoload(name)
	if name == nil then
		ns.CharDB().autoload = nil
		ns.Changed()
		return nil
	end

	local profile = ns.Get(name)
	if not profile then
		return nil, string.format("No profile named %s.", name)
	end

	ns.CharDB().autoload = ns.Key(name)
	ns.Changed()
	return profile.name
end

function ns.ToggleAutoload(name)
	local profile = ns.Get(name)
	if not profile then return nil end

	if ns.CharDB().autoload == ns.Key(name) then
		return ns.SetAutoload(nil)
	end
	return ns.SetAutoload(name)
end

local function RunAutoload()
	if autoloadDone then return end

	local profile = ns.GetAutoload()
	if not profile then
		autoloadDone = true
		return
	end

	if InCombatLockdown() then
		pendingLoad = profile.name -- retry when combat ends
		return
	end

	autoloadDone = true
	if ns.Load(profile.name, true) then
		Print("autoloaded |cffffff00%s|r for %s.", profile.name, ns.CharacterKey())
	end
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function Usage()
	Print("keybinding profiles:")
	print("  |cffffff00/kb|r                  - open the window")
	print("  |cffffff00/kb save <name>|r      - save current keybinds as <name>")
	print("  |cffffff00/kb load <name>|r      - switch to <name>")
	print("  |cffffff00/kb list|r             - show saved profiles")
	print("  |cffffff00/kb delete <name>|r    - remove a profile")
	print("  |cffffff00/kb rename <old> <new>|r - rename a profile")
	print("  |cffffff00/kb auto <name>|r      - autoload <name> on this character")
	print("  |cffffff00/kb auto off|r         - stop autoloading on this character")
	print("  |cffffff00/kb preset laptop|r   - add trackpad-friendly movement binds")
	print("  |cffffff00/kb gesture rest|press|r - how the trackpad drag triggers (macOS)")
	print("  |cffffff00/kb speed <name>|r     - turn speed: slow, normal, fast, faster")
	print("  |cffffff00/kb undo|r             - restore the binds from before the last load")
end

local handlers = {}

function handlers.save(name)
	local count, err, overwrote = ns.Save(name)
	if not count then
		Print(err)
		return
	end
	Print("%s |cffffff00%s|r (%d keys).", overwrote and "overwrote" or "saved", ns.Trim(name), count)
end

function handlers.load(name)
	if ns.Trim(name) == "" then
		Print("load what? |cffffff00/kb load laptop|r")
		return
	end
	ns.Load(name)
end

function handlers.list()
	local profiles = ns.List()
	if #profiles == 0 then
		Print("no profiles yet. Set your keys up, then |cffffff00/kb save desktop|r.")
		return
	end

	local autoload = ns.GetAutoload()
	Print("%d profile(s):", #profiles)
	for _, profile in ipairs(profiles) do
		local tags = ""
		if ns.DB().current == profile.name then
			tags = tags .. " |cff33ff99(current)|r"
		end
		if autoload and autoload.name == profile.name then
			tags = tags .. " |cffffd100(auto)|r"
		end
		print(string.format("  |cffffff00%s|r - %d keys%s", profile.name, ns.CountKeys(profile.bindings), tags))
	end
end

function handlers.delete(name)
	local deleted, err = ns.Delete(name)
	if not deleted then
		Print(err)
		return
	end
	Print("deleted |cffffff00%s|r.", deleted)
end

function handlers.rename(rest)
	local oldName, newName = rest:match("^(%S+)%s+(.+)$")
	if not oldName then
		Print("usage: |cffffff00/kb rename <old> <new>|r")
		return
	end

	local renamed, err = ns.Rename(oldName, newName)
	if not renamed then
		Print(err)
		return
	end
	Print("renamed to |cffffff00%s|r.", renamed)
end

function handlers.auto(name)
	name = ns.Trim(name)

	if name == "" then
		local profile = ns.GetAutoload()
		if profile then
			Print("%s autoloads |cffffff00%s|r.", ns.CharacterKey(), profile.name)
		else
			Print("%s has no autoload profile. |cffffff00/kb auto <name>|r to set one.", ns.CharacterKey())
		end
		return
	end

	if name:lower() == "off" or name:lower() == "none" then
		ns.SetAutoload(nil)
		Print("autoload off for %s.", ns.CharacterKey())
		return
	end

	local set, err = ns.SetAutoload(name)
	if not set then
		Print(err)
		return
	end
	Print("|cffffff00%s|r will autoload on %s at login.", set, ns.CharacterKey())
end

function handlers.preset(name)
	name = ns.Trim(name):lower()

	if name == "" then
		Print("presets:")
		for id, preset in pairs(ns.Presets or {}) do
			print(string.format("  |cffffff00/kb preset %s|r - %s", id, preset.blurb))
		end
		return
	end

	local applied, err, skipped = ns.ApplyPreset(name)
	if not applied then
		Print(err)
		return
	end

	if #applied == 0 then
		Print("nothing to change -- you already have these bound.")
	else
		Print("applied |cffffff00%s|r:", ns.Presets[name].name)
		for _, bind in ipairs(applied) do
			local took = bind.displaced and (" |cffff9999(took it from " .. bind.displaced .. ")|r") or ""
			print(string.format("  |cffffff00%s|r -> %s  (%s)%s", bind.key, bind.command, bind.why, took))
		end
		Print("|cffffff00/kb save laptop|r to keep it, or |cffffff00/kb undo|r to revert.")
	end

	for _, skip in ipairs(skipped or {}) do
		print(string.format("  |cff888888skipped %s: %s|r", skip.command, skip.reason))
	end
end

-- Trackpad helper settings. These reach TrackSteer through SavedVariables,
-- which the client only writes on /reload or logout -- hence the reminder.
function handlers.gesture(mode)
	if ns.Trim(mode) == "" then
		Print("gesture is |cffffff00%s|r. Use |cffffff00/kb gesture rest|r or |cffffff00press|r.",
			ns.TrackSteer().trigger)
		return
	end

	local set, err = ns.SetGesture(mode)
	if not set then Print(err) return end
	Print("gesture: |cffffff00%s|r. |cffffff00/reload|r to apply it.", set)
end

function handlers.speed(name)
	if ns.Trim(name) == "" then
		Print("turn speed is |cffffff00%s|r. Options: slow, normal, fast, faster.", ns.SpeedName())
		return
	end

	local set, err = ns.SetSpeed(name)
	if not set then Print(err) return end
	Print("turn speed: |cffffff00%s|r. |cffffff00/reload|r to apply it.", set)
end

function handlers.undo()
	ns.Undo()
end

handlers.help = Usage

function handlers.ui()
	if ns.ToggleWindow then ns.ToggleWindow() end
end

SLASH_BINDSWAP1 = "/kb"
SLASH_BINDSWAP2 = "/bindswap"

SlashCmdList.BINDSWAP = function(input)
	local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()

	if command == "" then
		if ns.ToggleWindow then
			ns.ToggleWindow()
		else
			Usage()
		end
		return
	end

	local handler = handlers[command]
	if handler then
		handler(rest or "")
	else
		Usage()
	end
end

-- Addon compartment (the dropdown next to the minimap).
function BindSwap_OnCompartmentClick()
	if ns.ToggleWindow then ns.ToggleWindow() end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- Give the client a moment to finish loading bindings before we stomp them.
		if C_Timer and C_Timer.After then
			C_Timer.After(1, RunAutoload)
		else
			RunAutoload()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingLoad then
			local name = pendingLoad
			pendingLoad = nil
			autoloadDone = true
			ns.Load(name)
		end
	end
end)

ns.RunAutoload = RunAutoload
