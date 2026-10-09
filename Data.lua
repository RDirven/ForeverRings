local _, ns = ...

-- Eight slices per ring: one per stick direction (incl. diagonals).
-- Need more? Put a sub-ring in a slot.
ns.MAX_SLICES = 8

-- Item class/subclass IDs (Enum.ItemClass / Enum.ItemConsumableSubclass)
local CLASS_CONSUMABLE = 0
local SUBCLASS_FOOD_DRINK = 5
local CLASS_WEAPON = 2
local CLASS_ARMOR = 4
local CLASS_QUEST = 12

local function ItemSlice(itemID)
	local slice = {
		type = "item",
		value = "item:" .. itemID,
		itemID = itemID,
		icon = C_Item.GetItemIconByID(itemID),
		name = C_Item.GetItemNameByID(itemID),
	}
	if PlayerHasToy and PlayerHasToy(itemID) then
		slice.type, slice.value = "toy", itemID
	end
	return slice
end

local function SpellSlice(spellID)
	return {
		type = "spell",
		value = spellID,
		icon = C_Spell.GetSpellTexture(spellID),
		name = C_Spell.GetSpellName(spellID),
	}
end

local function Truncate(list)
	for i = #list, ns.MAX_SLICES + 1, -1 do
		list[i] = nil
	end
	return list
end

-- Returns the unique itemIDs in the player's bags that pass the filter.
local function ScanBags(filter)
	local found, seen = {}, {}
	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not seen[id] and filter(id) then
				seen[id] = true
				found[#found + 1] = id
			end
		end
	end
	return found
end

ns.ScanBags = ScanBags

local function IsFood(itemID)
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	return classID == CLASS_CONSUMABLE and subClassID == SUBCLASS_FOOD_DRINK
end

-- Usable items for the Bag ring; quest items get their own ring.
local function IsUsable(itemID)
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	if classID == CLASS_WEAPON or classID == CLASS_ARMOR or classID == CLASS_QUEST or IsFood(itemID) then
		return false
	end
	return C_Item.GetItemSpell(itemID) ~= nil
end

local function IsQuestUsable(itemID)
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	return classID == CLASS_QUEST and C_Item.GetItemSpell(itemID) ~= nil
end

-- Raid target markers, skull first. /tm on an already marked target clears it.
local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function MarkerSlices()
	local slices = {}
	for i = 8, 1, -1 do
		slices[#slices + 1] = {
			type = "macro",
			value = "/tm " .. i,
			icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i,
			name = _G["RAID_TARGET_" .. i] or MARKER_NAMES[i],
		}
	end
	return slices
end

-- The spells behind food and drink items are named "Food" and "Drink" (in the
-- client's language), so compare against the names of the base spells.
local FOOD_SPELL, DRINK_SPELL = 433, 430

local function FoodAndDrink(itemID)
	local spellName = C_Item.GetItemSpell(itemID)
	if not spellName then
		return false, false
	end
	local food = C_Spell.GetSpellName(FOOD_SPELL) or "Food"
	local drink = C_Spell.GetSpellName(DRINK_SPELL) or "Drink"
	return spellName:find(food, 1, true) ~= nil, spellName:find(drink, 1, true) ~= nil
end

-- One slot that eats the best food and drinks the best drink at once.
local function EatAndDrinkSlice(sortedIDs)
	local foodID, drinkID
	for _, id in ipairs(sortedIDs) do
		local isFood, isDrink = FoodAndDrink(id)
		if isFood and not isDrink and not foodID then
			foodID = id
		elseif isDrink and not isFood and not drinkID then
			drinkID = id
		end
	end
	if foodID and drinkID then
		return {
			type = "macro",
			value = ("/use item:%d\n/use item:%d"):format(foodID, drinkID),
			icon = C_Item.GetItemIconByID(foodID),
			icon2 = C_Item.GetItemIconByID(drinkID),
			name = "Eat & Drink",
		}
	end
end

local function ItemLevel(itemID)
	return select(4, C_Item.GetItemInfo(itemID)) or 0
end

-- Rings that fill themselves. Everything else comes from ForeverRingsDB.rings.
ns.autoRings = {
	food = {
		label = "Food",
		build = function()
			local ids = ScanBags(IsFood)
			table.sort(ids, function(a, b)
				local la, lb = ItemLevel(a), ItemLevel(b)
				if la ~= lb then
					return la > lb
				end
				return C_Item.GetItemCount(a) > C_Item.GetItemCount(b)
			end)
			local slices = {}
			slices[1] = EatAndDrinkSlice(ids)
			for _, id in ipairs(ids) do
				slices[#slices + 1] = ItemSlice(id)
			end
			return Truncate(slices)
		end,
	},
	bag = {
		label = "Bag",
		build = function()
			local slices = {}
			for i, id in ipairs(Truncate(ScanBags(IsUsable))) do
				slices[i] = ItemSlice(id)
			end
			return slices
		end,
	},
	quest = {
		label = "Quest",
		build = function()
			local slices = {}
			for i, id in ipairs(Truncate(ScanBags(IsQuestUsable))) do
				slices[i] = ItemSlice(id)
			end
			return slices
		end,
	},
	markers = {
		label = "Markers",
		build = MarkerSlices,
	},
	-- Favorites first; all usable mounts when nothing is favorited.
	mount = {
		label = "Mounts",
		build = function()
			if not C_MountJournal then
				return {}
			end
			local favorites, others = {}, {}
			for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
				local name, spellID, icon, _, isUsable, _, isFavorite, _, _, shouldHide, isCollected =
					C_MountJournal.GetMountInfoByID(mountID)
				if isCollected and isUsable and not shouldHide then
					local slice = { type = "spell", value = spellID, icon = icon, name = name }
					table.insert(isFavorite and favorites or others, slice)
				end
			end
			return Truncate(#favorites > 0 and favorites or others)
		end,
	},
}

function ns.RingLabel(key)
	local auto = ns.autoRings[key]
	local custom = ForeverRingsDB.rings[key]
	return auto and auto.label or custom and custom.label or key
end

-- Builds the slices of every ring. Sub-ring slots borrow the icon of the
-- first action in the ring they open.
function ns.ResolveAll()
	local resolved = {}
	for key, auto in pairs(ns.autoRings) do
		resolved[key] = auto.build()
	end
	for key, ring in pairs(ForeverRingsDB.rings) do
		local slices = {}
		for _, entry in ipairs(ring.slots) do
			if entry.ring then
				slices[#slices + 1] = { type = "ring", value = entry.ring, name = ns.RingLabel(entry.ring) }
			elseif entry.kind == "spell" then
				slices[#slices + 1] = SpellSlice(entry.id)
			else
				slices[#slices + 1] = ItemSlice(entry.id)
			end
		end
		resolved[key] = Truncate(slices)
	end
	for _, slices in pairs(resolved) do
		for _, slice in ipairs(slices) do
			if slice.type == "ring" then
				local target = resolved[slice.value]
				local first = target and target[1]
				slice.icon = first and first.type ~= "ring" and first.icon or 134400
			end
		end
	end
	return resolved
end
