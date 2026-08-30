-- Settings for the macOS trackpad helper, written from in game.
--
-- WoW addons are sandboxed: no files, no network, no way to talk to another
-- application while the game is running. The one channel that exists is
-- SavedVariables, which the client flushes to disk on /reload or logout.
-- TrackSteer watches that file and applies whatever it finds.
--
-- So this is one-directional and needs a /reload to take effect. That is a poor
-- trade for something tweaked constantly, and a fine one for setup you do once
-- -- which is why the preset writes these rather than making you hunt for a
-- menu bar icon.

local ADDON, ns = ...

local DEFAULTS = {
	trigger = "rest",      -- "rest" (fingers touching) or "press" (trackpad clicked)
	sensitivity = 1.0,     -- 0.6 slow, 1.0 normal, 1.5 fast, 2.0 faster
	enabled = true,
}

local SPEEDS = {
	slow = 0.6,
	normal = 1.0,
	fast = 1.5,
	faster = 2.0,
}

function ns.TrackSteer()
	local db = ns.DB()
	db.trackSteer = db.trackSteer or {}
	for key, value in pairs(DEFAULTS) do
		if db.trackSteer[key] == nil then
			db.trackSteer[key] = value
		end
	end
	return db.trackSteer
end

function ns.SetGesture(mode)
	mode = ns.Trim(mode):lower()
	if mode ~= "rest" and mode ~= "press" then
		return nil, "Gesture is either 'rest' (fingers touching) or 'press' (trackpad clicked)."
	end

	ns.TrackSteer().trigger = mode
	ns.Changed()
	return mode
end

function ns.SetSpeed(name)
	name = ns.Trim(name):lower()
	local value = SPEEDS[name]
	if not value then
		return nil, "Speed is slow, normal, fast or faster."
	end

	ns.TrackSteer().sensitivity = value
	ns.Changed()
	return name, value
end

function ns.SpeedName()
	local current = ns.TrackSteer().sensitivity
	for name, value in pairs(SPEEDS) do
		if math.abs(current - value) < 0.01 then return name end
	end
	return string.format("%.1f", current)
end
