local _, ns = ...

-- Eight slices per ring: one per stick direction (incl. diagonals).
-- Need more? Put a sub-ring in a slot.
ns.MAX_SLICES = 8

-- Item class/subclass IDs (Enum.ItemClass / Enum.ItemConsumableSubclass)
local CLASS_CONSUMABLE = 0
local SUBCLASS_FOOD_DRINK = 5
local CLASS_WEAPON = 2
local CLASS_ARMOR = 4

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

local function IsFood(itemID)
	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
	return classID == CLASS_CONSUMABLE and subClassID == SUBCLASS_FOOD_DRINK
end

local function IsUsable(itemID)
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	if classID == CLASS_WEAPON or classID == CLASS_ARMOR or IsFood(itemID) then
		return false
	end
	return C_Item.GetItemSpell(itemID) ~= nil
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
			for i, id in ipairs(Truncate(ids)) do
				slices[i] = ItemSlice(id)
			end
			return slices
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
