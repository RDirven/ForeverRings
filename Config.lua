local _, ns = ...

-- Settings screen, driven by the gamepad first:
--   LB / RB   switch tab (or picker category)
--   D-pad     move
--   A         open / choose        B   back / close
--   X         clear / delete       Y   set a button for the ring
-- Keyboard (arrows, Enter, Esc, Tab, Delete) and mouse work as well: click
-- rows, tabs and slots, right-click a slot to clear it, and drag spells, items,
-- mounts and macros straight onto a slot.

local WIDTH, HEIGHT = 900, 540
-- Rows of the left column: the title row (where you are + its buttons), the
-- picker's category row, then the list.
local TITLE_Y, CATEGORY_Y, LIST_Y, LIST_Y_PICK = -58, -96, -100, -130
local ROW_HEIGHT, VISIBLE_ROWS = 34, 10
local LIST_WIDTH = 480

-- Buttons on every ring row, left to right.
local CELLS = {
	{ name = "edit", label = "Edit", width = 46, tip = "Edit this ring." },
	{ name = "setbar", label = "Set key", width = 80, tip = "Then press the action bar button where this ring\nshould go, e.g. L2 + Triangle." },
	{ name = "clearbar", label = "Clear", width = 54, tip = "Take this ring off your action bars." },
	{ name = "plus", label = "+", width = 26, tip = "Add something to this ring." },
	{ name = "minus", label = "-", width = 26, tip = "Delete this ring (click twice)." },
}
local PREVIEW_RADIUS, SLOT_SIZE = 95, 42
local ACCENT = { 0.35, 0.75, 1 }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local KEYS = {
	PADDUP = "up", PADLSTICKUP = "up", UP = "up",
	PADDDOWN = "down", PADLSTICKDOWN = "down", DOWN = "down",
	PADDLEFT = "left", PADLSTICKLEFT = "left", LEFT = "left",
	PADDRIGHT = "right", PADLSTICKRIGHT = "right", RIGHT = "right",
	PADRSTICKUP = "up", PADRSTICKDOWN = "down", PADRSTICKLEFT = "left", PADRSTICKRIGHT = "right",
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
	nameIndex = 1,
	welcome = false,
	capture = nil,      -- ring key, or "config" for the settings button
	barPick = nil,      -- ring waiting for an action bar button (capture = "bar")
	confirmDelete = nil,
	message = nil,
	col = nil,          -- ring list: focused row button (gamepad), index into CELLS
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
							list[#list + 1] = {
								entry = { kind = "spell", id = item.spellID },
								name = ns.SpellLabel(item.spellID) or item.name,
								baseName = item.name or "",
								rank = tonumber(((ns.SpellRank(item.spellID) or ""):match("(%d+)"))) or 0,
								icon = item.iconID,
							}
						end
					end
				end
			end
			-- Same spell together, highest rank first.
			table.sort(list, function(a, b)
				if a.baseName ~= b.baseName then
					return a.baseName < b.baseName
				end
				return a.rank > b.rank
			end)
			return list
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
		label = "Macros",
		build = function()
			local list = {}
			local global, perChar = GetNumMacros()
			local indexes = {}
			for i = 1, global do
				indexes[#indexes + 1] = i
			end
			for i = 1, perChar do
				indexes[#indexes + 1] = ns.MAX_ACCOUNT_MACROS + i
			end
			for _, index in ipairs(indexes) do
				local name, icon = GetMacroInfo(index)
				if name then
					list[#list + 1] = { entry = { macro = name }, name = name, icon = icon }
				end
			end
			return SortByName(list)
		end,
	},
	{
		label = "Menus",
		build = function()
			local list = {}
			for _, slice in ipairs(ns.AvailableMenus()) do
				list[#list + 1] = { entry = { menu = slice.menu }, name = slice.name, icon = slice.icon }
			end
			return list
		end,
	},
	{
		label = "Rings",
		build = function(currentKey)
			local list = { { entry = { settings = true }, name = "Settings (this screen)", icon = ns.SETTINGS_ICON } }
			for _, key in ipairs(ns.RingKeys()) do
				if key ~= currentKey then
					list[#list + 1] = { entry = { ring = key }, name = ns.RingLabel(key), icon = ns.RingIcon(key) }
				end
			end
			return list
		end,
	},
}

local WELCOME = "|cff59bfffWelcome to Forever Rings!|r\n\n"
	.. "1. Main is selected. Press |cffffffffY|r (or Set key), then the\n   action bar button where it should go.\n"
	.. "2. Press that button to open the ring, aim with the\n   stick, let go to use.\n\n"
	.. "The Settings slot in Main brings you back here."

-- Names to pick from, since typing on a controller is no fun.
local NAMES = {
	"Portals", "Travel", "Buffs", "Pets", "Toys", "Utility", "Combat", "Defensive",
	"Healing", "Cooldowns", "Professions", "Raid", "PvP", "Fun", "Gathering", "Misc",
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
		label = "Ring size",
		value = function() return math.floor((ForeverRingsDB.scale or 1) * 100 + 0.5) .. "%" end,
		help = "How big the rings are on screen.",
		change = function(step) ns.SetScale(Cycle(ns.SCALES, ForeverRingsDB.scale or 1, step)) return true end,
	},
	{
		label = "Pick on stick release",
		value = function() return ForeverRingsDB.releasePick and "On" or "Off" end,
		help = "On: aim, let go of the stick, and that slot is used.\nOff: letting go keeps the selection; release the\nring button or press A to use it.",
		change = function() return ns.SetReleasePick(not ForeverRingsDB.releasePick) end,
	},
	{
		label = "Hold camera still",
		value = function() return ForeverRingsDB.holdCamera and "On" or "Off" end,
		help = "While a ring is open, the right stick only aims\nand doesn't move the camera.",
		change = function() ns.SetHoldCamera(not ForeverRingsDB.holdCamera) return true end,
	},
	{
		label = "Tap to repeat",
		value = function() return ForeverRingsDB.tapRepeat and "On" or "Off" end,
		help = "Tap a ring button without aiming to use the\nlast thing you picked from that ring again.",
		change = function() return ns.SetTapRepeat(not ForeverRingsDB.tapRepeat) end,
	},
	{
		label = "Vibration",
		value = function() return ForeverRingsDB.vibration and "On" or "Off" end,
		help = "A short rumble when the stick moves to another slot.",
		change = function() ns.SetVibration(not ForeverRingsDB.vibration) return true end,
	},
	{
		label = "Settings button",
		value = function() return BindingText(GetBindingKey("FOREVERRINGS_CONFIG")) end,
		help = "Press A, then the button that should open this screen.\nOr type /frings.",
		accept = "capture",
	},
	{
		label = "Main ring",
		value = function() return state.confirmReset and "|cffff5555Press again|r" or "Reset" end,
		help = "Puts Main back to its default slots: Food, Mounts,\nBag, Quest, Markers, Tools, Menu and Settings.",
		accept = "reset",
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

local SlotClicked, DropOnSlot

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
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
	slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	slot:SetScript("OnClick", function(self, button) SlotClicked(self.index, button) end)
	slot:SetScript("OnReceiveDrag", function(self) DropOnSlot(self.index) end)
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

local function SetEnabled(button, on)
	if on then
		button:Enable()
	else
		button:Disable()
	end
end

-- The Edit / key / Bar / + / - buttons of a ring row.
local function RenderCells(row, key, selected)
	local show = key ~= nil and state.tab == "rings" and state.mode == "list"
	for c, b in ipairs(row.cells) do
		b:SetShown(show)
		if show and selected and state.col == c then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end
	if not show then
		return
	end
	local cells = row.cells
	SetEnabled(cells[3], ns.RingOnBar(key) ~= nil)
	SetEnabled(cells[4], ns.IsEditable(key))
	SetEnabled(cells[5], ns.IsDeletable(key))
	cells[5]:SetText(state.confirmDelete == key and "|cffff5555?|r" or "-")
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
			RenderCells(row, item.ring, offset + i == selected)
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
		slot.index = i
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
		ui.listTitle:SetText(ns.RingLabel(key) .. "  |cff888888>  slot " .. state.slot .. "|r")
		for i, b in ipairs(ui.categories) do
			local on = i == state.pickCategory
			b.label:SetTextColor(on and 1 or 0.55, on and 1 or 0.55, on and 1 or 0.55)
			b.line:SetShown(on)
		end
		RenderList(items, state.pickIndex)
		RenderPreview(key, state.slot)
		ui.info:SetText("Choose what goes in slot " .. state.slot .. ".")
		return SetHint("LB/RB category   A choose   B back")
	end

	if key and state.mode == "name" then
		local items = {}
		for i, name in ipairs(NAMES) do
			items[i] = { text = name, icon = false }
		end
		ui.listTitle:SetText("Rename " .. ns.RingLabel(key))
		RenderList(items, state.nameIndex)
		RenderPreview(key)
		ui.info:SetText("Pick a name. To type your own, use\n/frings new <name> on a keyboard.")
		return SetHint("A choose   B back")
	end

	-- The editor lists the ring's own slots.
	if key and state.mode == "edit" then
		local slices = PreviewSlices(key)
		state.slot = math.max(1, math.min(state.slot, #slices))
		local items = {}
		for i, slice in ipairs(slices) do
			items[i] = slice.add and { text = "|cff59bfff+ Add|r", icon = false }
				or { text = slice.name or "?", icon = slice.icon }
		end
		ui.listTitle:SetText(ns.RingLabel(key))
		RenderList(items, state.slot)
		RenderPreview(key, state.slot)
		if ns.IsEditable(key) then
			if state.confirmClear == state.slot then
				ui.info:SetText("")
				return SetHint("|cffff5555Press X (or right-click) again to clear this slot|r   B cancel")
			end
			ui.info:SetText(("Slot %d of %d.  Each ring holds up to %d.\n|cff888888Drag a spell, item, mount or macro onto a slot.\nRight-click a slot to clear it.|r"):format(state.slot, #slices, ns.MAX_SLICES))
			return SetHint("Up/Down slot   A choose   X clear" .. (key ~= "main" and "   Y rename" or "") .. "   B back")
		end
		ui.info:SetText("This ring fills itself from your bags and collection.")
		return SetHint("Up/Down look around   B back")
	end

	local items = {}
	for i, ringKey in ipairs(ui.ringKeys) do
		local auto = ns.autoRings[ringKey] ~= nil
		items[i] = {
			text = ns.RingLabel(ringKey) .. (auto and " |cff888888(auto)|r" or ""),
			icon = ns.RingIcon(ringKey),
			ring = ringKey,
		}
	end
	items[#items + 1] = { text = "|cff59bfff+ New ring|r", icon = false }
	ui.listTitle:SetText("Rings")
	RenderList(items, state.ringIndex)

	if not key then
		RenderPreview("main")
		ui.preview:SetAlpha(0.3)
		ui.info:SetText("Create a new ring. Put it in your Main ring\nor on your action bar.")
		return SetHint("A create   B close")
	end
	ui.preview:SetAlpha(1)

	RenderPreview(key)
	local slot = ns.RingOnBar(key)
	local lines = { slot and ("On your action bar (slot " .. slot .. ").") or "Not on your action bar yet: press Set key." }
	if ns.autoRings[key] then
		lines[#lines + 1] = "Fills itself from your bags and collection."
	else
		lines[#lines + 1] = "|cff888888Share it: /frings export " .. key .. "|r"
	end
	ui.info:SetText(state.welcome and WELCOME or table.concat(lines, "\n"))
	if state.confirmDelete == key then
		return SetHint("|cffff5555Press - (or X) again to delete " .. ns.RingLabel(key) .. "|r   B cancel")
	end
	if state.col then
		return SetHint("Left/Right choose   A press   B back")
	end
	SetHint("A " .. (ns.IsEditable(key) and "edit" or "view") .. "   Y set key (action bar)" .. (ns.IsDeletable(key) and "   X delete" or "") .. "   Right row buttons   B close")
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

-- Small buttons above the list while editing a ring: Back, Rename, + and -.
local function RenderToolbar()
	local key = CurrentRingKey()
	local rings = not state.capture and state.tab == "rings" and key ~= nil
	local editing = rings and state.mode == "edit" and ns.IsEditable(key)
	local picking = rings and state.mode == "pick"
	ui.back:SetShown(rings and state.mode ~= "list")
	for _, b in ipairs(ui.categories) do
		b:SetShown(picking)
	end
	ui.list:ClearAllPoints()
	ui.list:SetPoint("TOPLEFT", 20, picking and LIST_Y_PICK or LIST_Y)
	ui.rename:SetShown(editing and key ~= "main")
	ui.plus:SetShown(editing)
	ui.minus:SetShown(editing)
	if state.tab ~= "rings" or state.mode ~= "list" then
		state.col = nil
	end
	if state.mode ~= "edit" then
		state.confirmClear = nil
	end
end

Render = function()
	if not (ui and ui.frame:IsShown()) then
		return
	end
	RenderTabs()
	if state.capture then
		RenderToolbar()
		if state.capture == "bar" then
			ui.capture:SetText("Press the action bar button where " .. ns.RingLabel(state.barPick) .. " should go\n(for example L2 + Triangle). An empty one is best.\n\n|cff888888Right-click here or wait 15 seconds to cancel.|r")
		else
			ui.capture:SetText("Press the button that opens this screen.\n\n|cff888888B, Esc or right-click cancels.|r")
		end
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
	RenderToolbar()
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
	state.welcome = false
	state.col = nil
	state.barPick, state.barToken = nil, nil
	ui.frame:EnableKeyboard(false)
	ui.frame:EnableGamePadButton(false)
	ns.configOpen = false
	if not InCombatLockdown() then
		ClearOverrideBindings(ui.frame)
		ns.ApplyRingBindings()
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
local NextCell, RowAction, StartBarPick, EndBarPick

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

	if mode == "name" then
		if action == "up" or action == "down" then
			state.nameIndex = Move(state.nameIndex, action == "up" and -1 or 1, #NAMES)
		elseif action == "accept" then
			if Try(ns.RenameRing(key, NAMES[state.nameIndex])) then
				state.mode = "edit"
			end
		elseif action == "back" then
			state.mode = "edit"
		end
		return
	end

	if mode == "edit" then
		if action ~= "x" then
			state.confirmClear = nil
		end
		local count = #PreviewSlices(key)
		if action == "left" or action == "up" then
			state.slot = Move(state.slot, -1, count)
		elseif action == "right" or action == "down" then
			state.slot = Move(state.slot, 1, count)
		elseif action == "accept" and ns.IsEditable(key) then
			state.mode, state.pickIndex = "pick", 1
		elseif action == "y" and ns.IsEditable(key) and key ~= "main" then
			state.mode, state.nameIndex = "name", 1
		elseif action == "x" and ns.IsEditable(key) and ForeverRingsDB.rings[key].slots[state.slot] then
			if state.confirmClear ~= state.slot then
				state.confirmClear = state.slot
				return
			end
			state.confirmClear = nil
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
	if key and (action == "right" or (action == "left" and state.col)) then
		state.col = NextCell(key, state.col or 0, action == "right" and 1 or -1)
		return
	elseif key and state.col and action == "accept" then
		return RowAction(key, CELLS[state.col].name, "LeftButton")
	elseif state.col and action == "back" then
		state.col = nil
		return
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
		StartBarPick(key)
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
		if setting.accept == "capture" then
			StartCapture("config")
		elseif setting.accept == "reset" then
			if state.confirmReset then
				state.confirmReset = nil
				if Try(ns.ResetMain()) then
					Say("Main is back to its default slots.")
				end
			else
				state.confirmReset = true
			end
			return
		elseif setting.change then
			Try(setting.change(1))
		end
	elseif action == "back" then
		Close()
	end
	state.confirmReset = nil
end

-- Next usable row button from `col` in direction `step`; nil when moving left
-- off the first one.
NextCell = function(key, col, step)
	local c = col + step
	while c >= 1 and c <= #CELLS do
		local name = CELLS[c].name
		if (name ~= "plus" or ns.IsEditable(key)) and (name ~= "minus" or ns.IsDeletable(key))
			and (name ~= "clearbar" or ns.RingOnBar(key)) then
			return c
		end
		c = c + step
	end
	if c < 1 then
		return nil
	end
	return col > 0 and col or nil
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

-- What's on the cursor, as a ring entry: spells, items (and toys), mounts
-- and macros dragged from the spellbook, bags, mount journal or macro frame.
-- nil when the cursor is empty, false for something a ring can't hold.
local function CursorEntry()
	local kind, a, b, c = GetCursorInfo()
	if kind == "item" and a then
		return { kind = "item", id = a }
	elseif kind == "spell" then
		local id = c or (b == nil and a)
		return id and { kind = "spell", id = id } or false
	elseif kind == "macro" and a then
		local name = GetMacroInfo(a)
		return name and { macro = name } or false
	elseif kind == "mount" and C_MountJournal then
		local _, spellID = C_MountJournal.GetMountInfoByID(a)
		if not spellID and C_MountJournal.GetDisplayedMountInfo then
			_, spellID = C_MountJournal.GetDisplayedMountInfo(b or a)
		end
		return spellID and { kind = "spell", id = spellID } or false
	elseif kind == "companion" and GetCompanionInfo then
		local _, _, spellID = GetCompanionInfo(b, a)
		return spellID and { kind = "spell", id = spellID } or false
	end
	return kind and false
end

-- Puts whatever is on the cursor into slot `index` of ring `key` (no index
-- appends). Returns true when the cursor held something.
local function DropOnRing(key, index)
	local entry = CursorEntry()
	if entry == nil then
		return false
	end
	ClearCursor()
	state.message = nil
	if not entry then
		Say("That can't go in a ring.")
	elseif not key or not ns.IsEditable(key) then
		Say("That ring fills itself. Drop it on Main, Tools or your own ring.")
	else
		local slots = ForeverRingsDB.rings[key].slots
		if Try(ns.SetSlot(key, math.min(index or #slots + 1, #slots + 1), entry)) then
			Say("Added " .. ns.EntryName(entry) .. " to " .. ns.RingLabel(key) .. ".")
		end
	end
	Render()
	return true
end

DropOnSlot = function(index)
	if state.capture or state.tab ~= "rings" then
		return
	end
	if DropOnRing(CurrentRingKey(), index) and state.mode == "list" then
		state.mode, state.slot = "edit", index
		Render()
	end
end

-- Left click: select the slot, or choose what goes in it when it's already
-- selected. Right click: clear it.
SlotClicked = function(index, button)
	if state.capture or state.tab ~= "rings" or not CurrentRingKey() then
		return
	end
	if GetCursorInfo() then
		return DropOnSlot(index)
	end
	state.message = nil
	if state.mode == "pick" then
		state.slot = index
	elseif button == "RightButton" then
		state.mode, state.slot = "edit", index
		return HandleKey("PAD3")
	elseif state.mode == "edit" and state.slot == index then
		return HandleKey("PAD1")
	else
		state.mode, state.slot = "edit", index
	end
	Render()
end

-- Editor toolbar +: add a slot (opens the picker).
local function Plus()
	local key = CurrentRingKey()
	if state.capture or state.mode ~= "edit" or not (key and ns.IsEditable(key)) then
		return
	end
	local slots = ForeverRingsDB.rings[key].slots
	if #slots >= ns.MAX_SLICES then
		Say("That ring is full (" .. ns.MAX_SLICES .. " slots). Use a sub-ring for more.")
		return Render()
	end
	state.slot = #slots + 1
	HandleKey("PAD1")
end

-- Editor toolbar -: clear the selected slot.
local function Minus()
	if not state.capture and state.mode == "edit" then
		HandleKey("PAD3")
	end
end

local function PutOnActionBar(key)
	local message, err = ns.PlaceRingOnBar(key)
	Say(message or err)
	if message and GetCursorInfo() then
		-- No free slot: the macro is on the cursor, so get out of the way.
		Close()
		return ns.Print(message)
	end
	Render()
end

-- Set key: the next action bar button pressed gets the ring. The menu's own
-- buttons step aside so the game's bindings (and L2/R2 pages) work as usual.
EndBarPick = function(message)
	state.capture, state.barPick, state.barConfirm, state.barToken = nil, nil, nil, nil
	Say(message)
	ApplyBindings()
	Render()
end

StartBarPick = function(key)
	state.capture, state.barPick, state.barConfirm = "bar", key, nil
	ClearOverrideBindings(ui.frame)
	ui.frame:EnableKeyboard(false)
	ui.frame:EnableGamePadButton(false)
	ns.HookActionButtons()
	local token = {}
	state.barToken = token
	C_Timer.After(15, function()
		if state.barToken == token then
			EndBarPick("No button pressed, cancelled.")
		end
	end)
	Render()
end

-- Called (via hooks) whenever an action button is pressed.
function ns.OnActionButtonPressed(slot)
	if state.capture ~= "bar" or not (ui and ui.frame:IsShown()) or type(slot) ~= "number" then
		return
	end
	local key = state.barPick
	if HasAction(slot) and ns.RingOnBar(key) ~= slot and state.barConfirm ~= slot then
		state.barConfirm = slot
		Say("That button already has something. Press it again to replace it, or pick an empty one.")
		return Render()
	end
	local message, err = ns.PlaceRingInSlot(key, slot)
	EndBarPick(message or err)
end

-- A ring row's button: edit, Set key (action bar), Clear, + or -.
RowAction = function(key, name, button)
	state.message = nil
	if name ~= "minus" then
		state.confirmDelete = nil
	end
	if name == "edit" then
		state.mode, state.slot, state.col = "edit", 1, nil
	elseif name == "setbar" then
		state.mode = "list"
		return StartBarPick(key)
	elseif name == "clearbar" then
		state.mode = "list"
		Say(ns.RemoveRingFromBar(key))
	elseif name == "plus" then
		if not ns.IsEditable(key) then
			Say(ns.RingLabel(key) .. " fills itself.")
		elseif #ForeverRingsDB.rings[key].slots >= ns.MAX_SLICES then
			Say("That ring is full (" .. ns.MAX_SLICES .. " slots). Use a sub-ring for more.")
		else
			state.mode, state.slot, state.pickIndex, state.col = "pick", #ForeverRingsDB.rings[key].slots + 1, 1, nil
		end
	elseif name == "minus" then
		state.mode = "list"
		if not ns.IsDeletable(key) then
			Say(ns.RingLabel(key) .. " can't be deleted.")
		elseif state.confirmDelete == key then
			local label = ns.RingLabel(key)
			state.confirmDelete, state.col = nil, nil
			if Try(ns.DeleteRing(key)) then
				Say("Deleted " .. label .. ".")
			end
		else
			state.confirmDelete = key
		end
	end
	Render()
end

-- Gamepad buttons the client turns into Shift/Ctrl/Alt
-- (Options > Gamepad, or the GamePadEmulate* settings).
local function IsEmulatedModifier(button)
	for _, cvar in ipairs({ "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }) do
		if GetCVar and GetCVar(cvar) == button then
			return true
		end
	end
end

-- "SHIFT-PAD2" when a modifier is held, in WoW's ALT-CTRL-SHIFT order.
local function WithModifiers(key)
	return (IsAltKeyDown and IsAltKeyDown() and "ALT-" or "")
		.. (IsControlKeyDown and IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or "") .. key
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
		local warning = ns.BindingWarning(key)
		Say(ns.RingLabel(target) .. " button: " .. key .. (warning and ("  " .. warning) or ""))
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

-- The screen reads the gamepad and keyboard itself instead of through key
-- bindings: right after a reload, Blizzard's gamepad navigation could get to
-- bindings first and the controller did nothing until the screen reopened.
ApplyBindings = function()
	ClearOverrideBindings(ui.frame)
	ui.frame:EnableKeyboard(true)
	ui.frame:EnableGamePadButton(true)
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
	ui.tabButtons = {}
	for _, tab in ipairs({ { ui.tabRings, "rings" }, { ui.tabSettings, "settings" } }) do
		local hit = CreateFrame("Button", nil, frame)
		ui.tabButtons[tab[2]] = hit
		hit:SetPoint("TOPLEFT", tab[1], "TOPLEFT", -8, 6)
		hit:SetPoint("BOTTOMRIGHT", tab[1], "BOTTOMRIGHT", 8, -6)
		hit:SetScript("OnClick", function()
			if not state.capture then
				state.tab, state.mode, state.message, state.confirmDelete, state.col = tab[2], "list", nil, nil, nil
				Render()
			end
		end)
	end
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

	-- Title row: where you are on the left, its buttons on the right.
	ui.listTitle = Text(frame, "GameFontNormalLarge")
	ui.listTitle:SetPoint("TOPLEFT", 22, TITLE_Y - 6)
	ui.listTitle:SetJustifyH("LEFT")

	local function SmallButton(label, width, right, onClick)
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetSize(width, 22)
		b:SetText(label)
		b:SetPoint("TOPRIGHT", frame, "TOPLEFT", 20 + LIST_WIDTH - right, TITLE_Y)
		b:SetScript("OnClick", onClick)
		return b
	end
	-- Picker categories, clickable (LB/RB on a gamepad).
	ui.categories = {}
	for i, picker in ipairs(PICKERS) do
		local b = CreateFrame("Button", nil, frame)
		b.label = Text(b, "GameFontHighlight")
		b.label:SetPoint("CENTER")
		b.label:SetText(picker.label)
		b:SetSize(b.label:GetStringWidth() + 16, 24)
		b.line = Fill(b, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
		b.line:SetPoint("BOTTOMLEFT", 4, 0)
		b.line:SetPoint("BOTTOMRIGHT", -4, 0)
		b.line:SetHeight(2)
		if i == 1 then
			b:SetPoint("TOPLEFT", 14, CATEGORY_Y)
		else
			b:SetPoint("LEFT", ui.categories[i - 1], "RIGHT", 4, 0)
		end
		b:SetScript("OnClick", function()
			if not state.capture and state.mode == "pick" then
				state.pickCategory, state.pickIndex, state.message = i, 1, nil
				Render()
			end
		end)
		b:Hide()
		ui.categories[i] = b
	end

	ui.minus = SmallButton("-", 26, 0, Minus)
	ui.plus = SmallButton("+", 26, 30, Plus)
	ui.rename = SmallButton("Rename", 70, 60, function() HandleKey("PAD4") end)
	ui.back = SmallButton("Back", 56, 134, function() HandleKey("ESCAPE") end)

	local list = CreateFrame("Frame", nil, frame)
	list:SetSize(LIST_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
	list:SetPoint("TOPLEFT", 20, LIST_Y)
	for i = 1, VISIBLE_ROWS do
		local row = CreateRow(list, i)
		local function Select()
			state.col = nil
			local index = ui.listOffset + i
			if state.tab == "settings" then
				state.settingIndex = index
			elseif state.mode == "pick" then
				state.pickIndex = index
			elseif state.mode == "edit" then
				state.slot = index
			elseif state.mode == "list" then
				state.ringIndex = index
			end
		end
		row:SetScript("OnEnter", function()
			if not state.capture then
				Select()
				Render()
			end
		end)
		row:SetScript("OnClick", function(_, button)
			if state.capture then
				return
			end
			Select()
			if state.tab == "rings" and (state.mode == "list" or state.mode == "edit") and GetCursorInfo() then
				DropOnRing(CurrentRingKey(), state.mode == "edit" and state.slot or nil)
			elseif button == "RightButton" then
				if state.tab == "settings" then
					HandleKey("LEFT")
				elseif state.mode == "edit" then
					HandleKey("PAD3")
				else
					HandleKey("ESCAPE")
				end
			else
				HandleKey("PAD1")
			end
		end)
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnDragStart", function()
			if not state.capture and state.tab == "rings" and state.mode == "list" then
				Select()
				if CurrentRingKey() then
					PutOnActionBar(CurrentRingKey())
				end
			end
		end)
		row:SetScript("OnReceiveDrag", function()
			if state.tab == "rings" and state.mode == "list" then
				state.ringIndex = ui.listOffset + i
				DropOnRing(CurrentRingKey())
			elseif state.tab == "rings" and state.mode == "edit" then
				state.slot = ui.listOffset + i
				DropOnRing(CurrentRingKey(), state.slot)
			end
		end)
		row.cells = {}
		local x = -4
		for c = #CELLS, 1, -1 do
			local cell = CELLS[c]
			local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			b:SetSize(cell.width, ROW_HEIGHT - 10)
			b:SetPoint("RIGHT", x, 0)
			b:SetText(cell.label)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b:SetScript("OnClick", function(_, button)
				local index = ui.listOffset + i
				local key = ui.ringKeys[index]
				if state.capture or not key then
					return
				end
				state.ringIndex, state.col = index, nil
				RowAction(key, cell.name, button)
			end)
			b:SetScript("OnEnter", function(self)
				if GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(cell.tip, 1, 1, 1, 1, true)
					GameTooltip:Show()
				end
			end)
			b:SetScript("OnLeave", function()
				if GameTooltip then
					GameTooltip:Hide()
				end
			end)
			row.cells[c] = b
			x = x - cell.width - 3
		end
		ui.rows[i] = row
	end
	ui.list = list
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		if not state.capture then
			HandleKey(delta > 0 and "UP" or "DOWN")
		end
	end)
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

	local rule = Fill(frame, "BORDER", 1, 1, 1, 0.08)
	rule:SetPoint("BOTTOMLEFT", 20, 44)
	rule:SetPoint("BOTTOMRIGHT", -20, 44)
	rule:SetHeight(1)

	ui.hint = Text(frame, "GameFontNormal")
	ui.hint:SetPoint("BOTTOM", 0, 16)

	ui.capture = Text(frame, "GameFontHighlightLarge")
	ui.capture:SetPoint("CENTER")
	ui.capture:Hide()

	-- Middle and side mouse buttons can open rings too; right click cancels.
	local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5", RightButton = "ESCAPE" }
	frame:SetScript("OnMouseDown", function(_, button)
		if state.capture == "bar" then
			if button == "RightButton" then
				EndBarPick("Cancelled.")
			end
			return
		end
		if state.capture and MOUSE_KEYS[button] then
			FinishCapture(MOUSE_KEYS[button])
		end
	end)


	-- Modifiers alone don't count: hold one and press the second button.
	-- Keys the screen doesn't use (chat, screenshots...) go on to the game.
	frame:SetScript("OnKeyDown", function(self, key)
		if state.capture then
			self:SetPropagateKeyboardInput(false)
			if not MODIFIERS[key] then
				FinishCapture(WithModifiers(key))
			end
			return
		end
		self:SetPropagateKeyboardInput(KEYS[key] == nil)
		if KEYS[key] then
			HandleKey(key)
		end
	end)
	frame:SetScript("OnGamePadButtonDown", function(_, button)
		if state.capture then
			if not IsEmulatedModifier(button) then
				FinishCapture(WithModifiers(button))
			end
		elseif KEYS[button] then
			HandleKey(button)
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

-- Copy box for share codes. Copying needs a keyboard (Ctrl+C); WoW has no
-- clipboard API for addons.
local copyBox

function ns.ShowCopyBox(title, text)
	if not copyBox then
		copyBox = CreateFrame("Frame", "ForeverRingsCopyBox", UIParent)
		copyBox:SetSize(460, 110)
		copyBox:SetPoint("TOP", 0, -140)
		copyBox:SetFrameStrata("FULLSCREEN_DIALOG")
		copyBox:EnableMouse(true)
		local bg = Fill(copyBox, "BACKGROUND", 0.05, 0.06, 0.09, 0.97)
		bg:SetAllPoints()
		local bar = Fill(copyBox, "BORDER", ACCENT[1], ACCENT[2], ACCENT[3], 1)
		bar:SetPoint("TOPLEFT")
		bar:SetPoint("TOPRIGHT")
		bar:SetHeight(3)
		copyBox.title = Text(copyBox, "GameFontNormal")
		copyBox.title:SetPoint("TOP", 0, -14)
		local edit = CreateFrame("EditBox", nil, copyBox, "InputBoxTemplate")
		edit:SetSize(400, 24)
		edit:SetPoint("CENTER", 0, -2)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
		edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
		-- Read-only: typing puts the code back.
		edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(copyBox.code)
				self:HighlightText()
			end
		end)
		copyBox.edit = edit
		local hint = Text(copyBox, "GameFontDisableSmall")
		hint:SetPoint("BOTTOM", 0, 12)
		hint:SetText("Ctrl+C to copy, Esc to close. Friends paste it after /frings import")
	end
	copyBox.code = text
	copyBox.title:SetText(title)
	copyBox.edit:SetText(text)
	copyBox:Show()
	copyBox.edit:SetFocus()
	copyBox.edit:HighlightText()
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
	state.mode, state.message, state.capture, state.col = "list", nil, nil, nil
	ui.frame:Show()
	ns.configOpen = true
	ns.ApplyRingBindings()
	ApplyBindings()
	Render()
end

-- First login: open on the Main ring with a short how-to.
function ns.ShowWelcome()
	ForeverRingsDB.welcomed = true
	if ui and ui.frame:IsShown() then
		return
	end
	ns.ToggleConfig()
	state.welcome = true
	state.tab, state.ringIndex = "rings", 1
	Render()
end

function ns.OnRingsChanged()
	Render()
end

-- A page under Options > AddOns, reachable with the gamepad menus.
local function RegisterOptionsPage()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return
	end
	local page = CreateFrame("Frame")
	local title = Text(page, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Forever Rings")
	local about = Text(page, "GameFontHighlight", 500)
	about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	about:SetJustifyH("LEFT")
	about:SetText("Rings, buttons and settings live in their own controller-friendly screen.")
	local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	open:SetSize(220, 32)
	open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -16)
	open:SetText("Open Forever Rings")
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then
			HideUIPanel(SettingsPanel)
		end
		if not (ui and ui.frame:IsShown()) then
			ns.ToggleConfig()
		end
	end)
	local category = Settings.RegisterCanvasLayoutCategory(page, "Forever Rings")
	Settings.RegisterAddOnCategory(category)
	ns.optionsButton = open -- for tests
end

RegisterOptionsPage()

ForeverRings_ToggleConfig = ns.ToggleConfig
