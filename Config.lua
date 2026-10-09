local _, ns = ...

-- Settings screen, driven by the gamepad first:
--   LB / RB   switch tab (or picker category)
--   D-pad     move
--   A         open / choose        B   back / close
--   X         clear / delete       Y   set a button for the ring
-- Keyboard (arrows, Enter, Esc, Tab, Delete) and mouse work as well.

local WIDTH, HEIGHT = 760, 480
local ROW_HEIGHT, VISIBLE_ROWS = 34, 10
local LIST_WIDTH = 320
local PREVIEW_RADIUS, SLOT_SIZE = 95, 42
local ACCENT = { 0.35, 0.75, 1 }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION_MARK = 134400

local KEYS = {
	PADDUP = "up", PADLSTICKUP = "up", UP = "up",
	PADDDOWN = "down", PADLSTICKDOWN = "down", DOWN = "down",
	PADDLEFT = "left", PADLSTICKLEFT = "left", LEFT = "left",
	PADDRIGHT = "right", PADLSTICKRIGHT = "right", RIGHT = "right",
	PAD1 = "accept", ENTER = "accept",
	PAD2 = "back", ESCAPE = "back",
	PAD3 = "x", DELETE = "x",
	PAD4 = "y",
	PADLSHOULDER = "prevTab", PADRSHOULDER = "nextTab", TAB = "nextTab",
}

-- Keys that can't become a ring button: they select and go back inside rings.
local RESERVED = { PAD1 = "A", PAD2 = "B", ESCAPE = "Esc" }
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local ui
local state = {
	tab = "rings",      -- "rings" | "settings"
	mode = "list",      -- rings tab: "list" | "edit" | "pick"
	ringIndex = 1,
	slot = 1,
	pickCategory = 1,
	pickIndex = 1,
	settingIndex = 1,
	capture = nil,      -- ring key, or "config" for the settings button
	confirmDelete = nil,
	message = nil,
}

-- Picker sources ----------------------------------------------------------------

local function SortByName(list)
	table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
	return list
end

local PICKERS = {
	{
		label = "Bags",
		build = function()
			local list = {}
			for _, id in ipairs(ns.ScanBags(function(itemID) return C_Item.GetItemSpell(itemID) ~= nil end)) do
				list[#list + 1] = { entry = { kind = "item", id = id }, name = C_Item.GetItemNameByID(id) or ("item " .. id), icon = C_Item.GetItemIconByID(id) }
			end
			return SortByName(list)
		end,
	},
	{
		label = "Spells",
		build = function()
			local list = {}
			local book = C_SpellBook
			if not (book and book.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank) then
				return list
			end
			for line = 1, book.GetNumSpellBookSkillLines() do
				local info = book.GetSpellBookSkillLineInfo(line)
				if info and not info.offSpecID then
					for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
						local item = book.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
						if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive and item.spellID then
							list[#list + 1] = { entry = { kind = "spell", id = item.spellID }, name = item.name, icon = item.iconID }
						end
					end
				end
			end
			return SortByName(list)
		end,
	},
	{
		label = "Mounts",
		build = function()
			local list = {}
			if not C_MountJournal then
				return list
			end
			for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
				local name, spellID, icon, _, _, _, _, _, _, shouldHide, isCollected = C_MountJournal.GetMountInfoByID(mountID)
				if isCollected and not shouldHide then
					list[#list + 1] = { entry = { kind = "spell", id = spellID }, name = name, icon = icon }
				end
			end
			return SortByName(list)
		end,
	},
	{
		label = "Toys",
		build = function()
			local list = {}
			if not (C_ToyBox and C_ToyBox.GetNumFilteredToys) then
				return list
			end
			for i = 1, C_ToyBox.GetNumFilteredToys() do
				local itemID = C_ToyBox.GetToyFromIndex(i)
				if itemID and itemID > 0 and PlayerHasToy(itemID) then
					local _, name, icon = C_ToyBox.GetToyInfo(itemID)
					list[#list + 1] = { entry = { kind = "item", id = itemID }, name = name, icon = icon }
				end
			end
			return SortByName(list)
		end,
	},
	{
		label = "Rings",
		build = function(currentKey)
			local list = {}
			for _, key in ipairs(ns.RingKeys()) do
				if key ~= currentKey then
					local slices = ns.resolved[key]
					local first = slices and slices[1]
					list[#list + 1] = { entry = { ring = key }, name = ns.RingLabel(key), icon = first and first.type ~= "ring" and first.icon or QUESTION_MARK }
				end
			end
			return list
		end,
	},
}

-- Settings rows -----------------------------------------------------------------

local function Cycle(list, current, step)
	for i, value in ipairs(list) do
		if value == current then
			return list[(i - 1 + step) % #list + 1]
		end
	end
	return list[1]
end

local function BindingText(binding)
	return binding and (GetBindingText and GetBindingText(binding) or binding) or "|cff888888none|r"
end

local SETTINGS = {
	{
		label = "Style",
		value = function() return ForeverRingsDB.style == "classic" and "Classic" or "Clean" end,
		help = "Clean: round icons on a dark disc.\nClassic: Blizzard-style borders and glow.",
		change = function(step) ns.SetStyle(Cycle(ns.STYLES, ForeverRingsDB.style, step)) return true end,
	},
	{
		label = "Aim with",
		value = function() return ns.INPUT_LABELS[ForeverRingsDB.input] end,
		help = "What you point with while a ring is open.\nA always selects, B always goes back.",
		change = function(step) return ns.SetInput(Cycle(ns.INPUTS, ForeverRingsDB.input, step)) end,
	},
	{
		label = "Settings button",
		value = function() return BindingText(GetBindingKey("FOREVERRINGS_CONFIG")) end,
		help = "Press A, then the button that should open this screen.\nOr type /frings.",
		accept = function() state.capture = "config" end,
	},
}

-- Widgets -----------------------------------------------------------------------

local function Text(parent, template, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if size then
		fs:SetWidth(size)
	end
	return fs
end

local function Fill(parent, layer, r, g, b, a)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetColorTexture(r, g, b, a)
	return tex
end

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(LIST_WIDTH, ROW_HEIGHT - 2)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row.bg = Fill(row, "BACKGROUND", ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
	row.bg:SetAllPoints()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 8, ROW_HEIGHT - 8)
	row.icon:SetPoint("LEFT", 6, 0)
	row.text = Text(row)
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.text:SetJustifyH("LEFT")
	row.right = Text(row, "GameFontDisable")
	row.right:SetPoint("RIGHT", -8, 0)
	row.right:SetJustifyH("RIGHT")
	row:RegisterForClicks("LeftButtonUp")
	return row
end

local function CreateSlot(parent)
	local slot = CreateFrame("Button", nil, parent)
	slot:SetSize(SLOT_SIZE, SLOT_SIZE)
	slot.disc = Fill(slot, "BACKGROUND", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	slot.disc:SetPoint("CENTER")
	slot.disc:SetSize(SLOT_SIZE + 12, SLOT_SIZE + 12)
	local discMask = slot:CreateMaskTexture()
	discMask:SetAllPoints(slot.disc)
	discMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	slot.disc:AddMaskTexture(discMask)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetAllPoints()
	local iconMask = slot:CreateMaskTexture()
	iconMask:SetAllPoints(slot.icon)
	iconMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	slot.icon:AddMaskTexture(iconMask)
	slot.plus = Text(slot, "GameFontNormalHuge")
	slot.plus:SetPoint("CENTER")
	slot.plus:SetText("+")
	slot:RegisterForClicks("LeftButtonUp")
	return slot
end

-- Rendering ---------------------------------------------------------------------

local Render

local function CurrentRingKey()
	return ui.ringKeys[state.ringIndex]
end

local function SetHint(text)
	ui.hint:SetText(state.message and ("|cffffd100" .. state.message .. "|r   " .. text) or text)
end

local function RenderList(items, selected)
	local offset = math.max(0, math.min(selected - VISIBLE_ROWS, #items - VISIBLE_ROWS))
	offset = math.max(offset, 0)
	ui.listOffset = offset
	for i = 1, VISIBLE_ROWS do
		local row, item = ui.rows[i], items[offset + i]
		if item then
			row.icon:SetTexture(item.icon or QUESTION_MARK)
			row.icon:SetShown(item.icon ~= false)
			row.text:SetText(item.text)
			row.right:SetText(item.right or "")
			row.bg:SetShown(offset + i == selected)
			row:Show()
		else
			row:Hide()
		end
	end
	ui.empty:SetShown(#items == 0)
end

-- Slots of a ring as the preview shows them: real slices, plus a "+" slot
-- while editing a ring that has room.
local function PreviewSlices(key)
	local slices = {}
	for i, slice in ipairs(ns.resolved[key] or {}) do
		slices[i] = slice
	end
	if state.mode ~= "list" and ns.IsEditable(key) and #slices < ns.MAX_SLICES then
		slices[#slices + 1] = { add = true, name = "Add" }
	end
	return slices
end

local function RenderPreview(key, selected)
	local slices = PreviewSlices(key)
	local n = #slices
	for i, slice in ipairs(slices) do
		local slot = ui.slots[i] or CreateSlot(ui.preview)
		ui.slots[i] = slot
		local angle = math.rad((i - 1) * 360 / n)
		slot:ClearAllPoints()
		slot:SetPoint("CENTER", ui.preview, "CENTER", math.sin(angle) * PREVIEW_RADIUS, math.cos(angle) * PREVIEW_RADIUS)
		slot.icon:SetTexture(slice.add and nil or (slice.icon or QUESTION_MARK))
		slot.icon:SetShown(not slice.add)
		slot.plus:SetShown(slice.add == true)
		slot.disc:SetShown(i == selected)
		slot:Show()
	end
	for i = n + 1, #ui.slots do
		ui.slots[i]:Hide()
	end
	local current = selected and slices[selected]
	ui.center:SetText(current and current.name or ns.RingLabel(key))
	return slices
end

local function RenderTabs()
	ui.tabRings:SetTextColor(state.tab == "rings" and 1 or 0.5, state.tab == "rings" and 1 or 0.5, state.tab == "rings" and 1 or 0.5)
	ui.tabSettings:SetTextColor(state.tab == "settings" and 1 or 0.5, state.tab == "settings" and 1 or 0.5, state.tab == "settings" and 1 or 0.5)
	ui.tabLine:ClearAllPoints()
	local active = state.tab == "rings" and ui.tabRings or ui.tabSettings
	ui.tabLine:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -4)
	ui.tabLine:SetPoint("TOPRIGHT", active, "BOTTOMRIGHT", 0, -4)
end

local function RenderRings()
	ui.ringKeys = ns.RingKeys()
	state.ringIndex = math.min(state.ringIndex, #ui.ringKeys + 1)
	local key = CurrentRingKey()

	if state.mode == "pick" then
		local picker = PICKERS[state.pickCategory]
		ui.pickItems = picker.build(key)
		state.pickIndex = math.max(1, math.min(state.pickIndex, #ui.pickItems))
		local items = {}
		for i, item in ipairs(ui.pickItems) do
			items[i] = { text = item.name, icon = item.icon }
		end
		local labels = {}
		for i, p in ipairs(PICKERS) do
			labels[i] = i == state.pickCategory and ("|cffffffff" .. p.label .. "|r") or ("|cff888888" .. p.label .. "|r")
		end
		ui.listTitle:SetText(table.concat(labels, "   "))
		RenderList(items, state.pickIndex)
		RenderPreview(key, state.slot)
		ui.info:SetText("Choose what goes in slot " .. state.slot .. ".")
		return SetHint("LB/RB category   A choose   B back")
	end

	local items = {}
	for i, ringKey in ipairs(ui.ringKeys) do
		local auto = ns.autoRings[ringKey] ~= nil
		items[i] = {
			text = ns.RingLabel(ringKey) .. (auto and " |cff888888(auto)|r" or ""),
			icon = (ns.resolved[ringKey] and ns.resolved[ringKey][1] and ns.resolved[ringKey][1].icon) or QUESTION_MARK,
			right = BindingText(ns.GetRingBinding(ringKey)),
		}
	end
	items[#items + 1] = { text = "|cff59bfff+ New ring|r", icon = false }
	ui.listTitle:SetText("Rings")
	RenderList(items, state.ringIndex)

	if not key then
		RenderPreview("main")
		ui.preview:SetAlpha(0.3)
		ui.info:SetText("Create a new ring. Put it in your Main ring\nor give it its own button.")
		return SetHint("A create   B close")
	end
	ui.preview:SetAlpha(1)

	if state.mode == "edit" then
		local slices = RenderPreview(key, state.slot)
		if ns.IsEditable(key) then
			ui.info:SetText(("Slot %d of %d.  Each ring holds up to %d."):format(state.slot, #slices, ns.MAX_SLICES))
			return SetHint("D-pad slot   A choose   X clear   B back")
		end
		ui.info:SetText("This ring fills itself from your bags and collection.")
		return SetHint("D-pad look around   B back")
	end

	RenderPreview(key)
	local lines = { "Button: " .. BindingText(ns.GetRingBinding(key)) }
	if ns.autoRings[key] then
		lines[#lines + 1] = "Fills itself from your bags and collection."
	end
	ui.info:SetText(table.concat(lines, "\n"))
	if state.confirmDelete == key then
		return SetHint("|cffff5555Press X again to delete " .. ns.RingLabel(key) .. "|r   B cancel")
	end
	SetHint("A " .. (ns.IsEditable(key) and "edit" or "view") .. "   Y set button" .. (ns.IsDeletable(key) and "   X delete" or "") .. "   B close")
end

local function RenderSettings()
	local items = {}
	for i, setting in ipairs(SETTINGS) do
		items[i] = { text = setting.label, right = "|cffffffff" .. setting.value() .. "|r", icon = false }
	end
	ui.listTitle:SetText("Settings")
	RenderList(items, state.settingIndex)
	RenderPreview("main")
	ui.preview:SetAlpha(1)
	ui.info:SetText(SETTINGS[state.settingIndex].help)
	SetHint(SETTINGS[state.settingIndex].accept and "A change   B close" or "D-pad left/right change   B close")
end

Render = function()
	if not (ui and ui.frame:IsShown()) then
		return
	end
	RenderTabs()
	if state.capture then
		local target = state.capture == "config" and "the settings screen" or ns.RingLabel(state.capture)
		ui.capture:SetText("Press the button for " .. target .. "\n\n|cff888888B or Esc cancels|r")
		ui.capture:Show()
		SetHint("")
		return
	end
	ui.capture:Hide()
	if state.tab == "rings" then
		RenderRings()
	else
		RenderSettings()
	end
end

-- Input -------------------------------------------------------------------------

local function Say(msg)
	state.message = msg
end

local function Try(result, err)
	if not result then
		Say(err)
	end
	return result
end

local ApplyBindings, StartCapture

local function Close()
	if not ui then
		return
	end
	state.capture = nil
	state.confirmDelete = nil
	ui.frame:EnableKeyboard(false)
	ui.frame:EnableGamePadButton(false)
	if not InCombatLockdown() then
		ClearOverrideBindings(ui.frame)
	end
	ui.frame:Hide()
end

local function Move(current, step, count)
	if count == 0 then
		return 1
	end
	return (current - 1 + step) % count + 1
end

local actions = {}

function actions.rings(action)
	local key = CurrentRingKey()
	local mode = state.mode

	if mode == "pick" then
		if action == "up" or action == "down" then
			state.pickIndex = Move(state.pickIndex, action == "up" and -1 or 1, #ui.pickItems)
		elseif action == "prevTab" or action == "nextTab" then
			state.pickCategory = Move(state.pickCategory, action == "prevTab" and -1 or 1, #PICKERS)
			state.pickIndex = 1
		elseif action == "accept" then
			local item = ui.pickItems[state.pickIndex]
			if item and Try(ns.SetSlot(key, state.slot, item.entry)) then
				state.mode = "edit"
			end
		elseif action == "back" then
			state.mode = "edit"
		end
		return
	end

	if mode == "edit" then
		local count = #PreviewSlices(key)
		if action == "left" or action == "up" then
			state.slot = Move(state.slot, -1, count)
		elseif action == "right" or action == "down" then
			state.slot = Move(state.slot, 1, count)
		elseif action == "accept" and ns.IsEditable(key) then
			state.mode, state.pickIndex = "pick", 1
		elseif action == "x" and ns.IsEditable(key) and ForeverRingsDB.rings[key].slots[state.slot] then
			if Try(ns.RemoveSlot(key, state.slot)) then
				state.slot = math.max(1, math.min(state.slot, #ForeverRingsDB.rings[key].slots))
			end
		elseif action == "back" then
			state.mode = "list"
		end
		return
	end

	-- Ring list
	local count = #ui.ringKeys + 1
	if action ~= "x" then
		state.confirmDelete = nil
	end
	if action == "up" or action == "down" then
		state.ringIndex = Move(state.ringIndex, action == "up" and -1 or 1, count)
	elseif action == "prevTab" or action == "nextTab" then
		state.tab = "settings"
	elseif action == "accept" then
		if not key then
			local newKey = Try(ns.NewNumberedRing())
			if newKey then
				ui.ringKeys = ns.RingKeys()
				for i, k in ipairs(ui.ringKeys) do
					if k == newKey then
						state.ringIndex = i
					end
				end
				state.mode, state.slot = "edit", 1
				Say("Created " .. ns.RingLabel(newKey) .. ". Add it to Main from Main's picker > Rings.")
			end
		else
			state.mode, state.slot = "edit", 1
		end
	elseif action == "y" and key then
		StartCapture(key)
	elseif action == "x" and key and ns.IsDeletable(key) then
		if state.confirmDelete == key then
			state.confirmDelete = nil
			if Try(ns.DeleteRing(key)) then
				Say("Deleted.")
			end
		else
			state.confirmDelete = key
		end
	elseif action == "back" then
		Close()
	end
end

function actions.settings(action)
	local setting = SETTINGS[state.settingIndex]
	if action == "up" or action == "down" then
		state.settingIndex = Move(state.settingIndex, action == "up" and -1 or 1, #SETTINGS)
	elseif action == "prevTab" or action == "nextTab" then
		state.tab = "rings"
	elseif (action == "left" or action == "right") and setting.change then
		Try(setting.change(action == "left" and -1 or 1))
	elseif action == "accept" then
		if setting.accept then
			StartCapture("config")
		elseif setting.change then
			Try(setting.change(1))
		end
	elseif action == "back" then
		Close()
	end
end

local function HandleKey(key)
	local action = KEYS[key]
	if not action or InCombatLockdown() then
		return
	end
	state.message = nil
	actions[state.tab](action)
	Render()
end

local function FinishCapture(key)
	local target = state.capture
	if key == "ESCAPE" or key == "PAD2" then
		state.capture = nil
	elseif RESERVED[key] then
		Say(RESERVED[key] .. " is used inside rings. Pick another button.")
		Render()
		return
	elseif target == "config" then
		for _, old in ipairs({ GetBindingKey("FOREVERRINGS_CONFIG") }) do
			SetBinding(old)
		end
		SetBinding(key, "FOREVERRINGS_CONFIG")
		SaveBindings(GetCurrentBindingSet())
		Say("Settings button: " .. key)
		state.capture = nil
	elseif Try(ns.BindRing(target, key)) then
		Say(ns.RingLabel(target) .. " button: " .. key)
		state.capture = nil
	end
	ui.frame:EnableKeyboard(false)
	ui.frame:EnableGamePadButton(false)
	ApplyBindings()
	Render()
end

-- While capturing, our own override bindings are off so every key reaches us.
StartCapture = function(target)
	state.capture = target
	ClearOverrideBindings(ui.frame)
	ui.frame:EnableKeyboard(true)
	ui.frame:SetPropagateKeyboardInput(false)
	ui.frame:EnableGamePadButton(true)
end

ApplyBindings = function()
	ClearOverrideBindings(ui.frame)
	for key in pairs(KEYS) do
		SetOverrideBindingClick(ui.frame, true, key, "ForeverRingsConfigInput", key)
	end
end

-- Frame -------------------------------------------------------------------------

local function Build()
	ui = { rows = {}, slots = {}, ringKeys = {}, pickItems = {} }
	ns.configUI, ns.configState = ui, state -- for tests

	local frame = CreateFrame("Frame", "ForeverRingsConfig", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:Hide()
	ui.frame = frame

	local bg = Fill(frame, "BACKGROUND", 0.05, 0.06, 0.09, 0.96)
	bg:SetAllPoints()
	local bar = Fill(frame, "BORDER", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(3)

	local title = Text(frame, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 20, -18)
	title:SetText("Forever Rings")

	ui.tabRings = Text(frame, "GameFontHighlightLarge")
	ui.tabRings:SetPoint("TOP", -60, -18)
	ui.tabRings:SetText("Rings")
	ui.tabSettings = Text(frame, "GameFontHighlightLarge")
	ui.tabSettings:SetPoint("TOP", 60, -18)
	ui.tabSettings:SetText("Settings")
	ui.tabLine = Fill(frame, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	ui.tabLine:SetHeight(2)
	local lb = Text(frame, "GameFontDisable")
	lb:SetPoint("RIGHT", ui.tabRings, "LEFT", -16, 0)
	lb:SetText("LB")
	local rb = Text(frame, "GameFontDisable")
	rb:SetPoint("LEFT", ui.tabSettings, "RIGHT", 16, 0)
	rb:SetText("RB")

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -12, -12)
	local closeText = Text(close, "GameFontNormalLarge")
	closeText:SetPoint("CENTER")
	closeText:SetText("×")
	close:SetScript("OnClick", Close)

	ui.listTitle = Text(frame, "GameFontNormal")
	ui.listTitle:SetPoint("TOPLEFT", 20, -62)
	ui.listTitle:SetJustifyH("LEFT")

	local list = CreateFrame("Frame", nil, frame)
	list:SetSize(LIST_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
	list:SetPoint("TOPLEFT", 20, -84)
	for i = 1, VISIBLE_ROWS do
		local row = CreateRow(list, i)
		row:SetScript("OnEnter", function()
			if state.capture then
				return
			end
			local index = ui.listOffset + i
			if state.tab == "settings" then
				state.settingIndex = index
			elseif state.mode == "pick" then
				state.pickIndex = index
			elseif state.mode == "list" then
				state.ringIndex = index
			end
			Render()
		end)
		row:SetScript("OnClick", function() HandleKey("PAD1") end)
		ui.rows[i] = row
	end
	ui.empty = Text(list, "GameFontDisable")
	ui.empty:SetPoint("TOP", 0, -20)
	ui.empty:SetText("Nothing here yet.")

	ui.preview = CreateFrame("Frame", nil, frame)
	ui.preview:SetSize(PREVIEW_RADIUS * 2 + SLOT_SIZE * 2, PREVIEW_RADIUS * 2 + SLOT_SIZE * 2)
	ui.preview:SetPoint("TOPRIGHT", -40, -70)
	local disc = Fill(ui.preview, "BACKGROUND", 0, 0, 0, 0.5)
	disc:SetAllPoints()
	local discMask = ui.preview:CreateMaskTexture()
	discMask:SetAllPoints(disc)
	discMask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	disc:AddMaskTexture(discMask)
	ui.center = Text(ui.preview, "GameFontHighlight", 110)
	ui.center:SetPoint("CENTER")

	ui.info = Text(frame, "GameFontHighlightSmall", 320)
	ui.info:SetPoint("TOP", ui.preview, "BOTTOM", 0, -12)

	ui.hint = Text(frame, "GameFontNormal")
	ui.hint:SetPoint("BOTTOM", 0, 16)

	ui.capture = Text(frame, "GameFontHighlightLarge")
	ui.capture:SetPoint("CENTER")
	ui.capture:Hide()

	local input = CreateFrame("Button", "ForeverRingsConfigInput", frame)
	input:RegisterForClicks("AnyDown")
	input:SetScript("OnClick", function(_, key) HandleKey(key) end)

	frame:SetScript("OnKeyDown", function(_, key)
		if state.capture and not MODIFIERS[key] then
			FinishCapture(key)
		end
	end)
	frame:SetScript("OnGamePadButtonDown", function(_, button)
		if state.capture then
			FinishCapture(button)
		end
	end)
	frame:SetScript("OnEvent", function()
		if frame:IsShown() then
			Close()
			ns.Print("Settings closed for combat.")
		end
	end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function ns.ToggleConfig()
	if ui and ui.frame:IsShown() then
		return Close()
	end
	if InCombatLockdown() then
		return ns.Print("Settings can't be opened in combat.")
	end
	if not ui then
		Build()
	end
	state.mode, state.message, state.capture = "list", nil, nil
	ui.frame:Show()
	ApplyBindings()
	Render()
end

function ns.OnRingsChanged()
	Render()
end

ForeverRings_ToggleConfig = ns.ToggleConfig
