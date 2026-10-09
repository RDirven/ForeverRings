local _, ns = ...

BINDING_HEADER_FOREVERRINGS = "Forever Rings"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_main:LeftButton"] = "Main ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_food:LeftButton"] = "Food ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_bag:LeftButton"] = "Bag ring (usable items)"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_mount:LeftButton"] = "Mount ring"
_G["BINDING_NAME_CLICK ForeverRingsTrigger_tools:LeftButton"] = "Tools ring"

local INPUTS = {
	rstick = { "PADRSTICKUP", "PADRSTICKRIGHT", "PADRSTICKDOWN", "PADRSTICKLEFT" },
	lstick = { "PADLSTICKUP", "PADLSTICKRIGHT", "PADLSTICKDOWN", "PADLSTICKLEFT" },
	dpad = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT" },
}
local DIRECTIONS = { "up", "right", "down", "left" }

local DEFAULTS = {
	style = "clean",
	input = "rstick",
	confirm = "PAD1",
	back = "PAD2",
	rings = {
		main = { label = "Main", slots = { { ring = "food" }, { ring = "mount" }, { ring = "bag" }, { ring = "tools" } } },
		tools = { label = "Tools", slots = {} },
	},
}

local header
local triggers = {}
local refreshPending, refreshQueued = false, false

local function Print(msg)
	print("|cff59bfffForever Rings|r: " .. msg)
end

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
end

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
		CreateHeader()
		events:RegisterEvent("BAG_UPDATE_DELAYED")
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		events:RegisterEvent("NEW_MOUNT_ADDED")
		events:RegisterEvent("NEW_TOY_ADDED")
		RefreshAll()
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

local function EditableRing(key)
	local ring = ForeverRingsDB.rings[key]
	if not ring then
		Print(ns.autoRings[key] and ("'" .. key .. "' fills itself and can't be edited.") or ("No ring named '" .. key .. "'."))
	end
	return ring
end

local function EntryName(entry)
	if entry.ring then
		return "Ring: " .. ns.RingLabel(entry.ring)
	elseif entry.kind == "spell" then
		return C_Spell.GetSpellName(entry.id) or ("spell " .. entry.id)
	end
	return C_Item.GetItemNameByID(entry.id) or ("item " .. entry.id)
end

local commands = {}

function commands.new(name)
	local key = name:lower()
	if not key:match("^%w+$") then
		return Print("Usage: /frings new <name> (letters and digits)")
	elseif ForeverRingsDB.rings[key] or ns.autoRings[key] then
		return Print("'" .. key .. "' already exists.")
	end
	ForeverRingsDB.rings[key] = { label = name, slots = {} }
	RefreshAll()
	Print("Created '" .. key .. "'. Add it to the main ring with: /frings add main ring:" .. key)
end

function commands.delete(name)
	local key = name:lower()
	if key == "main" then
		return Print("The main ring can't be deleted.")
	elseif not EditableRing(key) then
		return
	end
	ForeverRingsDB.rings[key] = nil
	for _, ring in pairs(ForeverRingsDB.rings) do
		for i = #ring.slots, 1, -1 do
			if ring.slots[i].ring == key then
				table.remove(ring.slots, i)
			end
		end
	end
	RefreshAll()
	Print("Deleted '" .. key .. "'.")
end

function commands.add(args)
	local key, rest = args:match("^(%S+)%s*(.-)$")
	local ring = key and EditableRing(key:lower())
	local entry = ring and ParseEntry(rest)
	if not ring then
		return
	elseif not entry then
		return Print("Usage: /frings add <ring> <shift-click item/spell | ring:name>")
	elseif #ring.slots >= ns.MAX_SLICES then
		return Print("That ring is full (" .. ns.MAX_SLICES .. " slots). Use a sub-ring for more.")
	elseif entry.ring == key:lower() then
		return Print("A ring can't contain itself.")
	end
	table.insert(ring.slots, entry)
	RefreshAll()
	Print("Added " .. EntryName(entry) .. ".")
end

function commands.remove(args)
	local key, index = args:match("^(%S+)%s+(%d+)$")
	if not key then
		return Print("Usage: /frings remove <ring> <number from /frings list>")
	end
	local ring = EditableRing(key:lower())
	if ring and ring.slots[tonumber(index)] then
		local entry = table.remove(ring.slots, tonumber(index))
		RefreshAll()
		Print("Removed " .. EntryName(entry) .. ".")
	elseif ring then
		Print("No slot " .. index .. " in '" .. key:lower() .. "'. See /frings list " .. key:lower())
	end
end

function commands.list(name)
	if name == "" then
		local keys = {}
		for key in pairs(ns.resolved) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		return Print("Rings: " .. table.concat(keys, ", "))
	end
	local ring = EditableRing(name:lower())
	if ring then
		for i, entry in ipairs(ring.slots) do
			Print(("%d. %s"):format(i, EntryName(entry)))
		end
		if #ring.slots == 0 then
			Print("(empty)")
		end
	end
end

function commands.bind(args)
	local key, binding = args:match("^(%S+)%s+(%S+)$")
	if not (key and triggers[key:lower()]) then
		return Print("Usage: /frings bind <ring> <key>, e.g. /frings bind portals PADLSHOULDER")
	end
	SetBindingClick(binding:upper(), "ForeverRingsTrigger_" .. key:lower(), "LeftButton")
	SaveBindings(GetCurrentBindingSet())
	Print("Bound " .. binding:upper() .. " to '" .. key:lower() .. "'.")
end

function commands.style(name)
	if name ~= "clean" and name ~= "classic" then
		return Print("Usage: /frings style clean|classic")
	end
	ForeverRingsDB.style = name
	Print("Style: " .. name)
end

function commands.input(name)
	if not INPUTS[name] then
		return Print("Usage: /frings input rstick|lstick|dpad")
	end
	ForeverRingsDB.input = name
	ApplyInput()
	Print("Aim with: " .. name)
end

function commands.refresh()
	RefreshAll()
	Print("Rings refreshed.")
end

local SECURE_COMMANDS = { new = true, delete = true, add = true, remove = true, bind = true, input = true, refresh = true }

SLASH_FOREVERRINGS1 = "/frings"
SLASH_FOREVERRINGS2 = "/foreverrings"
SlashCmdList.FOREVERRINGS = function(msg)
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local handler = commands[cmd]
	if handler and SECURE_COMMANDS[cmd] and InCombatLockdown() then
		Print("Can't change rings in combat.")
	elseif handler then
		handler(rest)
	else
		Print("Bind rings under Options > Keybindings > AddOns > Forever Rings.")
		Print("Hold the ring button, aim with the stick, release (or press A). B goes back.")
		Print("/frings new|delete <ring>  ·  add <ring> <link|ring:name>  ·  remove <ring> <n>")
		Print("/frings list [ring]  ·  bind <ring> <key>  ·  style clean|classic  ·  input rstick|lstick|dpad")
	end
end
