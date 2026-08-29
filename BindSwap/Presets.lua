-- Ready-made binding sets for situations the default layout handles badly.
--
-- Presets are deliberately ADDITIVE. They only bind movement commands that
-- aren't bound anywhere yet, and only to keys that are currently free. A
-- preset will never take a key away from an ability, because the whole point
-- is to make a laptop playable without dismantling a layout that already works.

local ADDON, ns = ...

ns.Presets = {
	laptop = {
		name = "Laptop / trackpad",
		blurb = "Turn and move on a trackpad, without touching your ability keys.",
		binds = {
			{
				key = "BUTTON3",
				command = "MOVEANDSTEER",
				why = "middle mouse = run and steer (three-finger drag, with MiddleDrag)",
			},
			{
				key = "`",
				command = "MOUSETURN_TOGGLE",
				why = "lock mouse-look so the trackpad turns you (needs the MouseTurn addon)",
			},
			{
				key = "\\",
				command = "TOGGLEAUTORUN",
				why = "auto-run, so you don't hold anything to move forward",
			},
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
		local existing = { GetBindingKey(bind.command) }

		if not ns.CommandExists(bind.command) then
			skipped[#skipped + 1] = {
				command = bind.command,
				reason = "this client doesn't have that command -- is the addon installed?",
			}

		elseif #existing > 0 then
			skipped[#skipped + 1] = {
				command = bind.command,
				reason = "already bound to " .. table.concat(existing, ", "),
			}

		else
			local owner = KeyOwner(bind.key)
			if owner then
				-- Never quietly steal a key that's doing something already.
				skipped[#skipped + 1] = {
					command = bind.command,
					reason = bind.key .. " is already used by " .. owner,
				}
			elseif SetBinding(bind.key, bind.command) then
				applied[#applied + 1] = { key = bind.key, command = bind.command, why = bind.why }
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

	ns.Changed()
	return applied, nil, skipped
end
