-- Ready-made binding sets for situations the default layout handles badly.
--
-- A preset OVERWRITES. If a key it needs is already doing something else, it
-- takes it -- that is the entire point. On a laptop, being able to move and
-- turn matters more than whatever was on that key, and a preset that politely
-- declined to bind anything would achieve nothing.
--
-- What makes that safe is the snapshot taken before applying: Undo puts the
-- whole layout back in one click. Everything displaced is reported by name, so
-- nothing disappears quietly.

local ADDON, ns = ...

-- The middle button is driven by a trackpad gesture supplied outside the game
-- (TrackSteer on macOS). That gesture consumes two-finger scroll inside WoW, so
-- camera zoom moves onto keys here. Three fingers is deliberately left alone --
-- macOS uses it for switching Spaces, above the game.
ns.Presets = {
	laptop = {
		name = "Trackpad",
		blurb = "Move and steer on a two-finger drag, with camera zoom on keys.",
		binds = {
			{ key = "BUTTON3", command = "MOVEANDSTEER",
			  why = "middle mouse = run and steer, held on a two-finger drag" },
			{ key = "\\", command = "TOGGLEAUTORUN",
			  why = "auto-run, so nothing is held to move forward" },
			-- Two-finger drag eats two-finger scroll, so zoom needs somewhere else.
			{ key = "=", command = "CAMERAZOOMIN",
			  why = "zoom in -- two-finger scroll is taken by the drag" },
			{ key = "-", command = "CAMERAZOOMOUT",
			  why = "zoom out -- two-finger scroll is taken by the drag" },
		},
	},
}

--------------------------------------------------------------------------------

-- Does this client (plus loaded addons) actually know this binding command?
function ns.CommandExists(command)
	for i = 1, GetNumBindings() do
		if GetBinding(i) == command then
			return true
		end
	end
	return false
end

-- What command currently owns this key, if any.
local function KeyOwner(key)
	if type(GetBindingAction) == "function" then
		local action = GetBindingAction(key)
		if action and action ~= "" then return action end
	end
	return nil
end

-- Returns applied, skipped. Never throws; a preset that can do nothing simply
-- reports why, so the player learns what's missing instead of seeing silence.
function ns.ApplyPreset(id)
	local preset = ns.Presets[id]
	if not preset then
		return nil, string.format("No preset called %s.", tostring(id))
	end

	if InCombatLockdown() then
		return nil, "Can't change bindings in combat."
	end

	-- Snapshot first so the existing Undo reverts the whole preset in one go.
	ns.DB().profiles[ns.BACKUP] = { name = ns.BACKUP, bindings = ns.Snapshot() }

	local applied, skipped = {}, {}

	for _, bind in ipairs(preset.binds) do
		if not ns.CommandExists(bind.command) then
			-- The only real reason to skip: the client has never heard of this
			-- command, usually because the addon providing it isn't loaded.
			skipped[#skipped + 1] = {
				command = bind.command,
				reason = "this client doesn't have that command -- is the addon installed?",
			}
		else
			-- Note what we're displacing so the player can see the cost.
			local displaced = KeyOwner(bind.key)
			if displaced == bind.command then displaced = nil end

			if SetBinding(bind.key, bind.command) then
				applied[#applied + 1] = {
					key = bind.key,
					command = bind.command,
					why = bind.why,
					displaced = displaced,
				}
			else
				skipped[#skipped + 1] = {
					command = bind.command,
					reason = "the client refused the key " .. bind.key,
				}
			end
		end
	end

	if #applied > 0 then
		SaveBindings(ns.CurrentBindingSet())
	end

	-- A Mac trackpad has no middle button at all, so Move and Steer silently
	-- does nothing without a helper. Say so here rather than let someone
	-- conclude the preset is broken.
	local boundMiddle = false
	for _, bind in ipairs(applied) do
		if bind.key == "BUTTON3" then boundMiddle = true end
	end

	if boundMiddle and type(IsMacClient) == "function" and IsMacClient() then
		ns.Print("on a Mac trackpad, |cffffff00Move and Steer|r needs a middle button, which trackpads don't have.")
		print("  Free helper: |cff33ff99github.com/purexmalice/TrackSteer/releases|r")
		print("  |cff888888Not needed if you play with a mouse.|r")
	end

	ns.Changed()
	return applied, nil, skipped
end
