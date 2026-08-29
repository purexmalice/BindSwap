-- BindSwap: save and load keybinding profiles with slash commands.

local ADDON = ...
local PREFIX = "|cff33ff99BindSwap|r: "
local BACKUP = "@undo" -- reserved profile, overwritten on every load

local pendingLoad -- profile queued because we were in combat

local frame = CreateFrame("Frame")

local function Print(msg, ...)
	print(PREFIX .. string.format(msg, ...))
end

-- Bindings save into either the account-wide or the character-specific set.
-- Mirror whichever set the player is currently using so a swap doesn't
-- silently move their bindings between the two.
local function CurrentBindingSet()
	if type(GetCurrentBindingSet) == "function" then
		local set = GetCurrentBindingSet()
		if set == ACCOUNT_BINDINGS or set == CHARACTER_BINDINGS then
			return set
		end
	end
	return ACCOUNT_BINDINGS
end

-- Walk every binding command the client knows about and record the keys
-- currently attached to it. GetBindingKey returns *all* keys as varargs,
-- not just the two the default UI shows, so multi-bound commands survive.
local function Snapshot()
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
	-- Collect first, then clear, so we're not mutating bindings mid-read.
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

--------------------------------------------------------------------------------
-- Profile store
--------------------------------------------------------------------------------

local function Store()
	BindSwapDB = BindSwapDB or {}
	BindSwapDB.profiles = BindSwapDB.profiles or {}
	return BindSwapDB
end

local function Find(name)
	local key = name:lower()
	return Store().profiles[key], key
end

local function SaveProfile(name)
	local bindings, count = Snapshot()
	local _, key = Find(name)
	Store().profiles[key] = { name = name, bindings = bindings }
	return count
end

local function LoadProfile(name)
	local profile = Find(name)
	if not profile then
		Print("no profile named |cffffff00%s|r. Try |cffffff00/kb list|r.", name)
		return
	end

	if InCombatLockdown() then
		pendingLoad = name
		Print("in combat -- will load |cffffff00%s|r when you drop out.", profile.name)
		return
	end

	-- Stash the current setup so a mistaken load is one command away from undone.
	local backup = Snapshot()
	Store().profiles[BACKUP] = { name = BACKUP, bindings = backup }

	local applied, failed = Apply(profile.bindings)
	Store().current = profile.name

	Print("loaded |cffffff00%s|r (%d keys). |cffffff00/kb undo|r to revert.", profile.name, applied)
	if #failed > 0 then
		Print("|cffff5555%d key(s) failed to bind:|r %s", #failed, table.concat(failed, ", "))
	end
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local function Usage()
	Print("keybinding profiles:")
	print("  |cffffff00/kb save <name>|r   - save current keybinds as <name>")
	print("  |cffffff00/kb load <name>|r   - switch to <name>")
	print("  |cffffff00/kb list|r          - show saved profiles")
	print("  |cffffff00/kb delete <name>|r - remove a profile")
	print("  |cffffff00/kb undo|r          - restore the binds from before the last load")
end

local handlers = {}

function handlers.save(name)
	if name == "" then
		Print("name it: |cffffff00/kb save laptop|r")
		return
	end
	if name:lower() == BACKUP then
		Print("|cffffff00%s|r is reserved. Pick another name.", BACKUP)
		return
	end
	local count = SaveProfile(name)
	Store().current = name
	Print("saved |cffffff00%s|r (%d keys).", name, count)
end

function handlers.load(name)
	if name == "" then
		Print("load what? |cffffff00/kb load laptop|r")
		return
	end
	LoadProfile(name)
end

function handlers.list()
	local profiles = Store().profiles
	local names = {}
	for key, profile in pairs(profiles) do
		if key ~= BACKUP then
			names[#names + 1] = profile.name
		end
	end

	if #names == 0 then
		Print("no profiles yet. Set your keys up, then |cffffff00/kb save desktop|r.")
		return
	end

	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	Print("%d profile(s):", #names)
	for _, name in ipairs(names) do
		local marker = (Store().current == name) and " |cff33ff99(current)|r" or ""
		local profile = Find(name)
		local count = 0
		for _, keys in pairs(profile.bindings) do
			count = count + #keys
		end
		print(string.format("  |cffffff00%s|r - %d keys%s", name, count, marker))
	end
end

function handlers.delete(name)
	local profile, key = Find(name)
	if not profile then
		Print("no profile named |cffffff00%s|r.", name)
		return
	end
	Store().profiles[key] = nil
	Print("deleted |cffffff00%s|r.", profile.name)
end

function handlers.undo()
	local backup = Store().profiles[BACKUP]
	if not backup then
		Print("nothing to undo.")
		return
	end
	if InCombatLockdown() then
		Print("can't change binds in combat.")
		return
	end

	local current = Snapshot()
	local applied = Apply(backup.bindings)
	-- Make undo a toggle: the setup we just replaced becomes the new backup.
	Store().profiles[BACKUP] = { name = BACKUP, bindings = current }
	Store().current = nil
	Print("restored the previous binds (%d keys).", applied)
end

handlers.help = Usage

SLASH_BINDSWAP1 = "/kb"
SLASH_BINDSWAP2 = "/bindswap"

SlashCmdList.BINDSWAP = function(input)
	local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()

	local handler = handlers[command]
	if handler then
		handler(rest or "")
	else
		Usage()
	end
end

--------------------------------------------------------------------------------
-- Deferred load after combat
--------------------------------------------------------------------------------

frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
	if pendingLoad then
		local name = pendingLoad
		pendingLoad = nil
		LoadProfile(name)
	end
end)
