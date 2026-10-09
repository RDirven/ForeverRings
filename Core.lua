local _, ns = ...

BINDING_HEADER_FOREVERRINGS = "Forever Rings"
BINDING_NAME_FOREVERRINGS_CONFIG = "Open settings"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_main:LeftButton"] = "Main ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_food:LeftButton"] = "Food ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_bag:LeftButton"] = "Bag ring (usable items)"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_mount:LeftButton"] = "Mount ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_quest:LeftButton"] = "Quest items ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_markers:LeftButton"] = "Target markers ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_tools:LeftButton"] = "Tools ring"

local INPUTS = {
	rstick = { "PADRSTICKUP", "PADRSTICKRIGHT", "PADRSTICKDOWN", "PADRSTICKLEFT" },
	lstick = { "PADLSTICKUP", "PADLSTICKRIGHT", "PADLSTICKDOWN", "PADLSTICKLEFT" },
	dpad = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT" },
}
local DIRECTIONS = { "up", "right", "down", "left" }

ns.STYLES = { "clean", "classic" }
ns.INPUTS = { "rstick", "lstick", "dpad" }
ns.INPUT_LABELS = { rstick = "Right stick", lstick = "Left stick", dpad = "D-pad" }

local DEFAULTS = {
	style = "clean",
	input = "rstick",
	confirm = "PAD1",
	back = "PAD2",
	tapRepeat = true,
	vibration = true,
	scale = 1,
	welcomed = false,
	last = {},
	rings = {
		main = { label = "Main", slots = { { ring = "food" }, { ring = "mount" }, { ring = "bag" }, { ring = "quest" }, { ring = "markers" }, { ring = "tools" }, { settings = true } } },
		tools = { label = "Tools", slots = {} },
	},
}

-- Main ring layouts that shipped as the default. A Main that still matches
-- one of these gets upgraded; anything the player changed is left alone.
local OLD_DEFAULT_MAINS = { "food,mount,bag,tools", "food,mount,bag,quest,markers,tools" }

local function MigrateMain()
	local main = ForeverRingsDB.rings.main
	local keys = {}
	for i, entry in ipairs(main and main.slots or {}) do
		keys[i] = entry.ring or (entry.settings and "settings") or "?"
	end
	local layout = table.concat(keys, ",")
	for _, old in ipairs(OLD_DEFAULT_MAINS) do
		if layout == old then
			main.slots = CopyTable(DEFAULTS.rings.main.slots)
		end
	end
end

local header
local triggers = {}
local refreshPending, refreshQueued = false, false

function ns.Print(msg)
	print("|cff59bfffForever Rings|r: " .. msg)
end
local Print = ns.Print

local function SecureButton(name, snippet, clicks)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button:SetSize(1, 1)
	button:SetPoint("TOPLEFT")
	button:RegisterForClicks(unpack(clicks))
	SecureHandlerWrapScript(button, "OnClick", header, snippet)
	return button
end

local function EnsureTrigger(key)
	if not triggers[key] then
		local trigger = SecureButton("ForeverRingsTrigger_" .. key, ns.snippets.trigger, { "AnyDown", "AnyUp" })
		trigger:SetAttribute("ring", key)
		trigger:SetAttribute("useOnKeyDown", false)
		triggers[key] = trigger
	end
	return triggers[key]
end

local function ApplyInput()
	local keys = INPUTS[ForeverRingsDB.input] or INPUTS.rstick
	for i, dir in ipairs(DIRECTIONS) do
		header:SetAttribute("key-" .. dir, keys[i])
	end
	header:SetAttribute("key-confirm", ForeverRingsDB.confirm)
	header:SetAttribute("key-back", ForeverRingsDB.back)
	header:SetAttribute("tap-repeat", ForeverRingsDB.tapRepeat or nil)
end

local function CreateHeader()
	header = CreateFrame("Frame", "ForeverRingsHeader", UIParent, "SecureHandlerBaseTemplate")
	header:SetAllPoints(UIParent)
	header:SetFrameStrata("DIALOG")
	header:EnableMouse(false)
	header:SetAttribute("depth", 0)
	header:Hide()

	for _, dir in ipairs(DIRECTIONS) do
		SecureButton("ForeverRingsDir_" .. dir, ns.snippets.direction, { "AnyDown", "AnyUp" }):SetAttribute("dir", dir)
	end
	SecureButton("ForeverRingsConfirm", ns.snippets.confirm, { "AnyDown" }):SetAttribute("useOnKeyDown", true)
	SecureButton("ForeverRingsBack", ns.snippets.back, { "AnyDown" })

	ApplyInput()
	for name, value in pairs(ForeverRingsDB.last) do
		header:SetAttribute(name, value)
	end
	-- The snippets record the last action per ring; keep it across reloads.
	header:HookScript("OnAttributeChanged", function(_, name, value)
		if name:sub(1, 5) == "last:" then
			ForeverRingsDB.last[name] = value
		end
	end)
	ns.display = ns.CreateDisplay(header)
end

-- Pushes every ring into the header's secure attributes. Out of combat only.
local lastCounts = {}
local function RefreshAll()
	refreshQueued = false
	if InCombatLockdown() then
		refreshPending = true
		return
	end
	refreshPending = false
	ns.resolved = ns.ResolveAll()
	for key, slices in pairs(ns.resolved) do
		EnsureTrigger(key)
		local prefix = "r:" .. key .. ":"
		for i = 1, math.max(#slices, lastCounts[key] or 0) do
			local slice = slices[i]
			header:SetAttribute(prefix .. "t" .. i, slice and slice.type)
			header:SetAttribute(prefix .. "v" .. i, slice and slice.value)
		end
		header:SetAttribute(prefix .. "n", #slices)
		lastCounts[key] = #slices
	end
	for key in pairs(lastCounts) do
		if not ns.resolved[key] then
			header:SetAttribute("r:" .. key .. ":n", 0)
			lastCounts[key] = nil
		end
	end
	if ns.OnRingsChanged then
		ns.OnRingsChanged()
	end
end
ns.RefreshAll = RefreshAll

-- Bag events come in bursts; coalesce them into one refresh.
local function QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0.3, RefreshAll)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ForeverRingsDB = ForeverRingsDB or {}
		for k, v in pairs(DEFAULTS) do
			if ForeverRingsDB[k] == nil then
				ForeverRingsDB[k] = type(v) == "table" and CopyTable(v) or v
			end
		end
		MigrateMain()
		CreateHeader()
		events:RegisterEvent("BAG_UPDATE_DELAYED")
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		events:RegisterEvent("NEW_MOUNT_ADDED")
		events:RegisterEvent("NEW_TOY_ADDED")
		events:RegisterEvent("UPDATE_MACROS")
		RefreshAll()
		-- First time: open the settings screen so controller players never
		-- have to type anything.
		if not ForeverRingsDB.welcomed then
			C_Timer.After(2, function()
				if not InCombatLockdown() and not ForeverRingsDB.welcomed then
					ns.ShowWelcome()
				end
			end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if refreshPending then
			RefreshAll()
		end
	else
		if event == "BAG_UPDATE_DELAYED" and header:IsShown() then
			ns.display:UpdateCounts()
		end
		QueueRefresh()
	end
end)

-- Ring editing API ----------------------------------------------------------
-- Shared by the slash commands and the settings screen. Everything here
-- changes secure state, so it returns nil plus a message when in combat.

local COMBAT = "Can't change rings in combat."
local BUILTIN_ORDER = { main = 1, food = 2, mount = 3, bag = 4, quest = 5, markers = 6, tools = 7 }

-- main, the auto rings, tools, then custom rings alphabetically.
function ns.RingKeys()
	local keys = {}
	for key in pairs(ns.autoRings) do
		keys[#keys + 1] = key
	end
	for key in pairs(ForeverRingsDB.rings) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		local oa, ob = BUILTIN_ORDER[a] or 99, BUILTIN_ORDER[b] or 99
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	return keys
end

function ns.IsEditable(key)
	return ForeverRingsDB.rings[key] ~= nil
end

function ns.IsDeletable(key)
	return ns.IsEditable(key) and key ~= "main" and key ~= "tools"
end

function ns.EntryName(entry)
	if entry.ring then
		return "Ring: " .. ns.RingLabel(entry.ring)
	elseif entry.settings then
		return "Settings"
	elseif entry.macro then
		return "Macro: " .. entry.macro
	elseif entry.kind == "spell" then
		return C_Spell.GetSpellName(entry.id) or ("spell " .. entry.id)
	end
	return C_Item.GetItemNameByID(entry.id) or ("item " .. entry.id)
end

function ns.NewRing(name)
	if InCombatLockdown() then
		return nil, COMBAT
	end
	local key = name:lower()
	if not key:match("^%w+$") then
		return nil, "Use letters and digits only."
	elseif ForeverRingsDB.rings[key] or ns.autoRings[key] then
		return nil, "'" .. key .. "' already exists."
	end
	ForeverRingsDB.rings[key] = { label = name, slots = {} }
	RefreshAll()
	return key
end

-- Picks the first free "Ring N" name, for creating rings without a keyboard.
function ns.NewNumberedRing()
	local n = 1
	while ForeverRingsDB.rings["ring" .. n] do
		n = n + 1
	end
	return ns.NewRing("Ring" .. n)
end

function ns.DeleteRing(key)
	if InCombatLockdown() then
		return nil, COMBAT
	elseif not ns.IsDeletable(key) then
		return nil, "'" .. ns.RingLabel(key) .. "' can't be deleted."
	end
	ForeverRingsDB.rings[key] = nil
	for _, ring in pairs(ForeverRingsDB.rings) do
		for i = #ring.slots, 1, -1 do
			if ring.slots[i].ring == key then
				table.remove(ring.slots, i)
			end
		end
	end
	ns.BindRing(key, nil)
	RefreshAll()
	return true
end

-- Replaces slot `index`, or appends when index is one past the end.
function ns.SetSlot(key, index, entry)
	local ring = ForeverRingsDB.rings[key]
	if InCombatLockdown() then
		return nil, COMBAT
	elseif not ring then
		return nil, ns.autoRings[key] and "'" .. ns.RingLabel(key) .. "' fills itself and can't be edited." or "No ring named '" .. key .. "'."
	elseif entry.ring == key then
		return nil, "A ring can't contain itself."
	elseif index > #ring.slots + 1 or index > ns.MAX_SLICES then
		return nil, "That ring is full (" .. ns.MAX_SLICES .. " slots). Use a sub-ring for more."
	end
	ring.slots[index] = entry
	RefreshAll()
	return true
end

function ns.RemoveSlot(key, index)
	local ring = ForeverRingsDB.rings[key]
	if InCombatLockdown() then
		return nil, COMBAT
	elseif not (ring and ring.slots[index]) then
		return nil, "No slot " .. index .. " in '" .. key .. "'."
	end
	local entry = table.remove(ring.slots, index)
	RefreshAll()
	return entry
end

-- Buttons Blizzard's own gamepad UI already uses. Allowed, but worth a warning.
local GAMEPAD_UI_KEYS = {
	PADLSHOULDER = "targets allies",
	PADRSHOULDER = "targets enemies",
	PADLTRIGGER = "is an action bar modifier",
	PADRTRIGGER = "is an action bar modifier",
}

-- Clicking the stick you aim with means pressing and tilting it at once.
local AIM_STICK_CLICK = { rstick = "PADRSTICK", lstick = "PADLSTICK" }

-- The stick you don't aim with, as a button name for tips.
function ns.ButtonTip()
	local free = ForeverRingsDB.input == "lstick" and "R3" or "L3"
	return free .. " or paddles work best."
end

function ns.BindingWarning(binding)
	local use = binding and GAMEPAD_UI_KEYS[binding]
	if use then
		return "Note: in Blizzard's gamepad UI this button " .. use .. ". " .. ns.ButtonTip()
	elseif binding and binding == AIM_STICK_CLICK[ForeverRingsDB.input] then
		return "Note: you aim with this stick, so holding it down while aiming is awkward. " .. ns.ButtonTip()
	end
end

function ns.TriggerCommand(key)
	return "CLICK ForeverRingsTrigger_" .. key .. ":LeftButton"
end

function ns.GetRingBinding(key)
	return GetBindingKey(ns.TriggerCommand(key))
end

-- One button per ring: clears the ring's old buttons first. nil just unbinds.
function ns.BindRing(key, binding)
	if InCombatLockdown() then
		return nil, COMBAT
	end
	local old = { GetBindingKey(ns.TriggerCommand(key)) }
	for _, oldKey in ipairs(old) do
		SetBinding(oldKey)
	end
	if binding then
		SetBindingClick(binding, "ForeverRingsTrigger_" .. key, "LeftButton")
	end
	SaveBindings(GetCurrentBindingSet())
	return true
end

function ns.SetStyle(name)
	ForeverRingsDB.style = name
end

function ns.SetTapRepeat(on)
	if InCombatLockdown() then
		return nil, COMBAT
	end
	ForeverRingsDB.tapRepeat = on
	ApplyInput()
	return true
end

function ns.RenameRing(key, label)
	local ring = ForeverRingsDB.rings[key]
	if not ring or key == "main" then
		return nil, "That ring can't be renamed."
	end
	ring.label = label
	if not InCombatLockdown() then
		RefreshAll()
	end
	return true
end

ns.SCALES = { 0.8, 0.9, 1, 1.1, 1.25, 1.5 }

function ns.SetScale(scale)
	ForeverRingsDB.scale = scale
end

function ns.SetVibration(on)
	ForeverRingsDB.vibration = on
end

function ns.SetInput(name)
	if InCombatLockdown() then
		return nil, COMBAT
	end
	ForeverRingsDB.input = name
	ApplyInput()
	return true
end

-- Sharing -------------------------------------------------------------------
-- A ring as one line of text: FR1:<label>:<slot>,<slot>,...
-- with slots s<spellID>, i<itemID>, r<ring key> or o (settings).
-- Macros live only on your own account, so they aren't exported.

local SHARE_PREFIX = "FR1"

function ns.ExportRing(key)
	local ring = ForeverRingsDB.rings[key]
	if not ring then
		return nil, ns.autoRings[key] and "'" .. ns.RingLabel(key) .. "' fills itself, so there's nothing to share." or "No ring named '" .. key .. "'."
	end
	local slots = {}
	for _, entry in ipairs(ring.slots) do
		if entry.ring then
			slots[#slots + 1] = "r" .. entry.ring
		elseif entry.settings then
			slots[#slots + 1] = "o"
		elseif entry.kind then
			slots[#slots + 1] = (entry.kind == "spell" and "s" or "i") .. entry.id
		end
	end
	local label = ring.label:gsub("[^%w ]", "")
	return SHARE_PREFIX .. ":" .. label .. ":" .. table.concat(slots, ",")
end

-- Creates a new ring from a share code. Sub-rings the player doesn't have are
-- skipped. Returns the new key and how many slots were skipped.
function ns.ImportRing(code)
	if InCombatLockdown() then
		return nil, COMBAT
	end
	local prefix, label, list = (code or ""):match("^%s*(%w+):([%w ]*):([%w,]*)%s*$")
	if prefix ~= SHARE_PREFIX then
		return nil, "That doesn't look like a Forever Rings code."
	end
	label = label:match("^%s*(.-)%s*$"):sub(1, 24)
	if label == "" then
		label = "Shared"
	end
	local base = label:lower():gsub("[^%w]", "")
	if base == "" then
		base = "shared"
	end
	local key, n = base, 1
	while ForeverRingsDB.rings[key] or ns.autoRings[key] do
		n = n + 1
		key = base .. n
	end

	local slots, skipped = {}, 0
	for token in list:gmatch("[^,]+") do
		local kind, rest = token:sub(1, 1), token:sub(2)
		local id = tonumber(rest)
		local entry
		if kind == "s" and id then
			entry = { kind = "spell", id = id }
		elseif kind == "i" and id then
			entry = { kind = "item", id = id }
		elseif kind == "r" and (ForeverRingsDB.rings[rest] or ns.autoRings[rest]) then
			entry = { ring = rest }
		elseif token == "o" then
			entry = { settings = true }
		end
		if entry and #slots < ns.MAX_SLICES then
			slots[#slots + 1] = entry
		else
			skipped = skipped + 1
		end
	end
	ForeverRingsDB.rings[key] = { label = n > 1 and (label .. " " .. n) or label, slots = slots }
	RefreshAll()
	return key, skipped
end

-- Slash commands ------------------------------------------------------------

-- Accepts a shift-clicked item/spell link, "ring:<name>" or a plain item ID.
local function ParseEntry(text)
	local sub = text:match("^ring:(%w+)$")
	if sub then
		return { ring = sub:lower() }
	end
	local kind, id = text:match("|H(%a+):(%d+)")
	if not kind then
		id = text:match("^(%d+)$")
		kind = id and "item"
	end
	if kind == "item" or kind == "spell" then
		return { kind = kind, id = tonumber(id) }
	end
end

-- Prints the message when an API call fails; returns the result otherwise.
local function Check(result, err)
	if not result then
		Print(err)
	end
	return result
end

local commands = {}

function commands.new(name)
	if not name:match("^%w+$") then
		return Print("Usage: /frings new <name> (letters and digits)")
	end
	local key = Check(ns.NewRing(name))
	if key then
		Print("Created '" .. key .. "'. Add it to the main ring with: /frings add main ring:" .. key)
	end
end

function commands.delete(name)
	local key = name:lower()
	if not ForeverRingsDB.rings[key] and not ns.autoRings[key] then
		return Print("No ring named '" .. key .. "'.")
	end
	if Check(ns.DeleteRing(key)) then
		Print("Deleted '" .. key .. "'.")
	end
end

function commands.add(args)
	local key, rest = args:match("^(%S+)%s*(.-)$")
	key = key and key:lower()
	local ring = key and ForeverRingsDB.rings[key]
	if not ring then
		return Print(key and ns.autoRings[key] and ("'" .. key .. "' fills itself and can't be edited.") or ("No ring named '" .. tostring(key) .. "'."))
	end
	local entry = ParseEntry(rest)
	if not entry then
		return Print("Usage: /frings add <ring> <shift-click item/spell | ring:name>")
	end
	if Check(ns.SetSlot(key, #ring.slots + 1, entry)) then
		Print("Added " .. ns.EntryName(entry) .. ".")
	end
end

function commands.remove(args)
	local key, index = args:match("^(%S+)%s+(%d+)$")
	if not key then
		return Print("Usage: /frings remove <ring> <number from /frings list>")
	end
	key = key:lower()
	if not ForeverRingsDB.rings[key] then
		return Print(ns.autoRings[key] and ("'" .. key .. "' fills itself and can't be edited.") or ("No ring named '" .. key .. "'."))
	end
	local entry = Check(ns.RemoveSlot(key, tonumber(index)))
	if entry then
		Print("Removed " .. ns.EntryName(entry) .. ".")
	end
end

function commands.list(name)
	if name == "" then
		return Print("Rings: " .. table.concat(ns.RingKeys(), ", "))
	end
	local key = name:lower()
	local ring = ForeverRingsDB.rings[key]
	if not ring then
		return Print(ns.autoRings[key] and ("'" .. key .. "' fills itself and can't be edited.") or ("No ring named '" .. key .. "'."))
	end
	for i, entry in ipairs(ring.slots) do
		Print(("%d. %s"):format(i, ns.EntryName(entry)))
	end
	if #ring.slots == 0 then
		Print("(empty)")
	end
end

function commands.bind(args)
	local key, binding = args:match("^(%S+)%s+(%S+)$")
	if not (key and triggers[key:lower()]) then
		return Print("Usage: /frings bind <ring> <key>, e.g. /frings bind portals PADLSTICK (L3)")
	end
	if Check(ns.BindRing(key:lower(), binding:upper())) then
		Print("Bound " .. binding:upper() .. " to '" .. key:lower() .. "'.")
		local warning = ns.BindingWarning(binding:upper())
		if warning then
			Print(warning)
		end
	end
end

function commands.style(name)
	if name ~= "clean" and name ~= "classic" then
		return Print("Usage: /frings style clean|classic")
	end
	ns.SetStyle(name)
	Print("Style: " .. name)
end

function commands.input(name)
	if not INPUTS[name] then
		return Print("Usage: /frings input rstick|lstick|dpad")
	end
	if Check(ns.SetInput(name)) then
		Print("Aim with: " .. name)
	end
end

function commands.export(name)
	local code = Check(ns.ExportRing(name:lower()))
	if code then
		ns.ShowCopyBox("Share " .. ns.RingLabel(name:lower()), code)
	end
end

function commands.import(code)
	local key, skipped = ns.ImportRing(code)
	if not key then
		Print(skipped)
	else
		Print("Imported '" .. ns.RingLabel(key) .. "'." .. (skipped > 0 and (" Skipped " .. skipped .. " slot(s) you don't have.") or "")
			.. " Add it to Main with: /frings add main ring:" .. key)
	end
end

function commands.refresh()
	RefreshAll()
	Print("Rings refreshed.")
end

function commands.config()
	ns.ToggleConfig()
end

function commands.help()
	Print("Bind rings under Options > Keybindings > AddOns > Forever Rings, or with /frings.")
	Print("Hold the ring button, aim with the stick, release (or press A). B goes back.")
	Print("/frings new|delete <ring>  ·  add <ring> <link|ring:name>  ·  remove <ring> <n>")
	Print("/frings list [ring]  ·  bind <ring> <key>  ·  style clean|classic  ·  input rstick|lstick|dpad")
	Print("/frings export <ring>  ·  import <code>   share rings with friends")
end

local SECURE_COMMANDS = { new = true, delete = true, add = true, remove = true, bind = true, input = true, refresh = true, config = true, import = true }

SLASH_FOREVERRINGS1 = "/frings"
SLASH_FOREVERRINGS2 = "/foreverrings"
SlashCmdList.FOREVERRINGS = function(msg)
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		cmd = "config"
	end
	local handler = commands[cmd] or commands.help
	if SECURE_COMMANDS[cmd] and InCombatLockdown() then
		Print("Can't change rings in combat.")
	else
		handler(rest)
	end
end
