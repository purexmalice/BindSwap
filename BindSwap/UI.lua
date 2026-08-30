-- BindSwap window: pick a profile, load it, and choose what autoloads on this
-- character. Built lazily on first open so a template that disappears in a
-- future patch can't stop the slash commands from working.

local ADDON, ns = ...

local WIDTH, HEIGHT = 400, 470
local ROW_HEIGHT = 28

local window        -- the frame, once built
local selectedKey   -- profile key currently highlighted
local pendingDelete -- delete is a two-click confirm, no popup needed

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Label(parent, font, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
	fs:SetText(text or "")
	return fs
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- BasicFrameTemplateWithInset is long-lived but not guaranteed; fall back to a
-- plain backdrop frame rather than erroring out on a future patch.
local function CreateShell()
	local ok, frame = pcall(CreateFrame, "Frame", "BindSwapFrame", UIParent, "BasicFrameTemplateWithInset")
	if ok and frame then
		return frame, true
	end

	frame = CreateFrame("Frame", "BindSwapFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})
		frame:SetBackdropColor(0, 0, 0, 0.9)
		frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	end
	return frame, false
end

--------------------------------------------------------------------------------
-- Row rendering
--------------------------------------------------------------------------------

local function SetStatus(text, isError)
	if not window then return end
	window.status:SetText(text or "")
	if isError then
		window.status:SetTextColor(1, 0.35, 0.35)
	else
		window.status:SetTextColor(0.6, 0.6, 0.6)
	end
end

local function InitRow(row, data)
	if not row.built then
		row.built = true
		row:SetHeight(ROW_HEIGHT)

		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetAllPoints()
		row.selected:SetColorTexture(0.2, 0.8, 0.6, 0.20)
		row.selected:Hide()

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)

		row.auto = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.auto:SetSize(22, 22)
		row.auto:SetPoint("LEFT", row, "LEFT", 2, 0)
		row.auto:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Autoload on this character")
			GameTooltip:AddLine("Load this profile automatically when " .. ns.CharacterKey() .. " logs in.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row.auto:SetScript("OnLeave", function() GameTooltip:Hide() end)

		row.name = Label(row, "GameFontHighlight")
		row.name:SetPoint("LEFT", row.auto, "RIGHT", 6, 0)
		row.name:SetJustifyH("LEFT")

		row.count = Label(row, "GameFontDisableSmall")
		row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end

	row.profileKey = data.key

	row.name:SetText(data.name)
	if data.isCurrent then
		row.name:SetTextColor(0.2, 1, 0.6)
	else
		row.name:SetTextColor(1, 0.82, 0)
	end

	row.count:SetText(data.count .. " keys")
	row.selected:SetShown(selectedKey == data.key)

	row.auto:SetChecked(data.isAuto)
	row.auto:SetScript("OnClick", function()
		ns.ToggleAutoload(data.name)
		local profile = ns.GetAutoload()
		if profile then
			SetStatus(profile.name .. " will load at login on this character.")
		else
			SetStatus("Autoload off for this character.")
		end
	end)

	row:SetScript("OnClick", function()
		selectedKey = data.key
		pendingDelete = nil
		window.nameBox:SetText(data.name)
		window.nameBox:ClearFocus()
		ns.Changed()
	end)

	row:SetScript("OnDoubleClick", function()
		ns.Load(data.name)
	end)
	row:RegisterForClicks("LeftButtonUp")
end

local function Refresh()
	if not window then return end

	window.character:SetText("Character: |cffffffff" .. ns.CharacterKey() .. "|r")

	local profiles = ns.List()
	local autoload = ns.GetAutoload()
	local current = ns.DB().current

	local items = {}
	for _, profile in ipairs(profiles) do
		items[#items + 1] = {
			key = ns.Key(profile.name),
			name = profile.name,
			count = ns.CountKeys(profile.bindings),
			isAuto = autoload and autoload.name == profile.name or false,
			isCurrent = current == profile.name,
		}
	end

	-- Drop a stale selection (profile deleted or renamed).
	local stillThere = false
	for _, item in ipairs(items) do
		if item.key == selectedKey then stillThere = true break end
	end
	if not stillThere then selectedKey = nil end

	window.empty:SetShown(#items == 0)

	local provider = CreateDataProvider(items)
	window.view:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil)

	local hasSelection = selectedKey ~= nil
	window.loadButton:SetEnabled(hasSelection)
	window.renameButton:SetEnabled(hasSelection)
	window.deleteButton:SetEnabled(hasSelection)
	window.deleteButton:SetText(pendingDelete and "Sure?" or "Delete")
	window.undoButton:SetEnabled(ns.DB().profiles[ns.BACKUP] ~= nil)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function SelectedName()
	if not selectedKey then return nil end
	local profile = ns.DB().profiles[selectedKey]
	return profile and profile.name or nil
end

local function Build()
	local frame, styled = CreateShell()
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.DB().window = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	frame:Hide()

	-- Own title rather than reaching into template internals, which move around.
	frame.titleText = Label(frame, "GameFontNormalLarge", "BindSwap")
	frame.titleText:SetPoint("TOP", frame, "TOP", 0, styled and -5 or -10)

	if not styled then
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	end

	frame.character = Label(frame, "GameFontNormalSmall")
	frame.character:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, styled and -32 or -36)

	local hint = Label(frame, "GameFontDisableSmall", "Double-click a profile to load it. Checkbox = autoload here.")
	hint:SetPoint("TOPLEFT", frame.character, "BOTTOMLEFT", 0, -4)

	-- Scrolling profile list.
	local box = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
	box:SetSize(WIDTH - 52, 250)

	local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 8, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

	frame.box, frame.view = box, view

	frame.empty = Label(frame, "GameFontDisable", "No profiles yet.\nBind your keys, type a name below, and hit Save.")
	frame.empty:SetPoint("CENTER", box, "CENTER", 0, 0)
	frame.empty:SetJustifyH("CENTER")

	-- Save row.
	local saveLabel = Label(frame, "GameFontNormalSmall", "Save current keybinds as:")
	saveLabel:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -14)

	local nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	nameBox:SetSize(WIDTH - 150, 20)
	nameBox:SetPoint("TOPLEFT", saveLabel, "BOTTOMLEFT", 6, -6)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)
	frame.nameBox = nameBox

	local function DoSave()
		local count, err, overwrote = ns.Save(nameBox:GetText())
		if not count then
			SetStatus(err, true)
			return
		end
		local name = ns.Trim(nameBox:GetText())
		selectedKey = ns.Key(name)

		-- Empty the box on success. Leaving the name sitting there reads as if
		-- the save is still pending; the new row in the list is the confirmation.
		nameBox:SetText("")
		nameBox:ClearFocus()

		SetStatus(string.format("%s %s (%d keys).", overwrote and "Overwrote" or "Saved", name, count))
	end

	nameBox:SetScript("OnEnterPressed", DoSave)

	local saveButton = Button(frame, "Save", 70, DoSave)
	saveButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

	-- Action row.
	frame.loadButton = Button(frame, "Load", 84, function()
		local name = SelectedName()
		if not name then return end
		if ns.Load(name) then
			SetStatus("Loaded " .. name .. ".")
		end
	end)
	frame.loadButton:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -14)

	frame.renameButton = Button(frame, "Rename", 84, function()
		local name = SelectedName()
		if not name then return end

		local renamed, err = ns.Rename(name, nameBox:GetText())
		if not renamed then
			SetStatus(err, true)
			return
		end
		selectedKey = ns.Key(renamed)
		SetStatus("Renamed to " .. renamed .. ".")
	end)
	frame.renameButton:SetPoint("LEFT", frame.loadButton, "RIGHT", 6, 0)

	frame.deleteButton = Button(frame, "Delete", 84, function()
		local name = SelectedName()
		if not name then return end

		-- First click arms, second click deletes. Cheaper than a popup.
		if pendingDelete ~= selectedKey then
			pendingDelete = selectedKey
			SetStatus("Click Delete again to remove " .. name .. ".", true)
			ns.Changed()
			return
		end

		pendingDelete = nil
		local deleted, err = ns.Delete(name)
		if not deleted then
			SetStatus(err, true)
			return
		end
		SetStatus("Deleted " .. deleted .. ".")
	end)
	frame.deleteButton:SetPoint("LEFT", frame.renameButton, "RIGHT", 6, 0)

	frame.undoButton = Button(frame, "Undo", 84, function()
		if ns.Undo() then
			SetStatus("Restored the previous keybinds.")
		end
	end)
	frame.undoButton:SetPoint("TOPLEFT", frame.loadButton, "BOTTOMLEFT", 0, -6)

	-- One-click trackpad setups. Additive-free: they take the keys they need,
	-- and the snapshot ApplyPreset takes means Undo reverts the lot.
	local function ApplyPreset(id)
		local applied, err, skipped = ns.ApplyPreset(id)
		if not applied then
			SetStatus(err, true)
			return
		end

		if #applied == 0 then
			local reason = skipped and skipped[1] and skipped[1].reason or "nothing to change"
			SetStatus("Already set up (" .. reason .. ").")
		else
			local took = 0
			for _, bind in ipairs(applied) do
				if bind.displaced then took = took + 1 end
			end
			nameBox:SetText(ns.Presets[id].name)
			SetStatus(string.format(
				"Set %d bind(s)%s. Save to keep it as a profile, or Undo to put everything back.",
				#applied,
				took > 0 and (", " .. took .. " taken from other commands (see chat)") or ""))
		end
		ns.Changed()
	end

	local function PresetTooltip(self, id)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ns.Presets[id].name)
		GameTooltip:AddLine(ns.Presets[id].blurb, 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		for _, bind in ipairs(ns.Presets[id].binds) do
			GameTooltip:AddLine(bind.key .. "  ->  " .. bind.why, 0.7, 0.7, 0.75, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Takes the keys it needs. Undo puts everything back.", 1, 0.7, 0.4, true)
		GameTooltip:Show()
	end

	frame.preset = Button(frame, "Trackpad setup", 150, function() ApplyPreset("laptop") end)
	frame.preset:SetPoint("LEFT", frame.undoButton, "RIGHT", 6, 0)
	frame.preset:SetScript("OnEnter", function(self) PresetTooltip(self, "laptop") end)
	frame.preset:SetScript("OnLeave", function() GameTooltip:Hide() end)

	frame.status = Label(frame, "GameFontDisableSmall", "")
	frame.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
	frame.status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetWordWrap(true)

	-- Restore where the player left it.
	local pos = ns.DB().window
	if pos and pos.point then
		frame:ClearAllPoints()
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	end

	tinsert(UISpecialFrames, "BindSwapFrame") -- Escape closes it

	window = frame
	ns.OnChanged(Refresh)
	Refresh()
	return frame
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function ns.ToggleWindow()
	if not window then
		local ok, err = pcall(Build)
		if not ok then
			window = nil
			ns.Print("|cffff5555couldn't build the window|r (%s). Slash commands still work -- try |cffffff00/kb list|r.", tostring(err))
			return
		end
	end

	if window:IsShown() then
		window:Hide()
	else
		Refresh()
		window:Show()
	end
end

-- A tiny panel under Settings > AddOns so the addon is discoverable.
local function RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

	local panel = CreateFrame("Frame")
	panel.name = "BindSwap"

	local title = Label(panel, "GameFontNormalLarge", "BindSwap")
	title:SetPoint("TOPLEFT", 16, -16)

	local blurb = Label(panel, "GameFontHighlightSmall",
		"Save your keybinds as named profiles and swap between them.\n" ..
		"Each character can autoload its own profile at login.")
	blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	blurb:SetJustifyH("LEFT")

	local open = Button(panel, "Open BindSwap", 140, function() ns.ToggleWindow() end)
	open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -16)

	local slash = Label(panel, "GameFontDisableSmall", "Slash commands: /kb  or  /bindswap")
	slash:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -16)

	local category = Settings.RegisterCanvasLayoutCategory(panel, "BindSwap")
	Settings.RegisterAddOnCategory(category)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	pcall(RegisterSettings)
end)
