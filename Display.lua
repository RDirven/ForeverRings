local _, ns = ...

-- Insecure visuals only. The secure header decides what happens; this file
-- just draws the active ring and highlights the slice that would be picked.

local RADIUS = 120
local ICON_SIZE = 46
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ACCENT = { 0.35, 0.75, 1 }

local function AddCircleMask(frame, texture)
	local mask = frame:CreateMaskTexture()
	mask:SetAllPoints(texture)
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	texture:AddMaskTexture(mask)
	return mask
end

local function CreateSlot(parent)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(ICON_SIZE, ICON_SIZE)

	-- Clean: accent disc behind the icon when selected.
	slot.disc = slot:CreateTexture(nil, "BACKGROUND")
	slot.disc:SetPoint("CENTER")
	slot.disc:SetSize(ICON_SIZE + 12, ICON_SIZE + 12)
	slot.disc:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
	AddCircleMask(slot, slot.disc)

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetAllPoints()
	slot.iconMask = AddCircleMask(slot, slot.icon)

	-- Classic: action button border plus additive glow.
	slot.border = slot:CreateTexture(nil, "OVERLAY")
	slot.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	slot.border:SetPoint("CENTER")
	slot.border:SetSize(ICON_SIZE * 64 / 36, ICON_SIZE * 64 / 36)
	slot.glow = slot:CreateTexture(nil, "OVERLAY", nil, 1)
	slot.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	slot.glow:SetBlendMode("ADD")
	slot.glow:SetAllPoints()

	slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	slot.count:SetPoint("BOTTOMRIGHT", -2, 2)

	-- Marks slots that open another ring.
	slot.more = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	slot.more:SetPoint("TOPRIGHT", 4, 4)
	slot.more:SetText("+")
	return slot
end

local STYLES = {
	clean = function(display, slot)
		slot.icon:SetTexCoord(0, 1, 0, 1)
		slot.icon:AddMaskTexture(slot.iconMask)
		slot.border:Hide()
		slot.glow:SetAlpha(0)
		display.backdrop:Show()
	end,
	classic = function(display, slot)
		slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		slot.icon:RemoveMaskTexture(slot.iconMask)
		slot.border:Show()
		slot.disc:SetAlpha(0)
		display.backdrop:Hide()
	end,
}

local Display = {}
Display.__index = Display

function ns.CreateDisplay(header)
	local self = setmetatable({ header = header, slots = {}, slices = {} }, Display)

	local frame = CreateFrame("Frame", nil, header)
	frame:SetAllPoints()
	self.frame = frame

	self.backdrop = frame:CreateTexture(nil, "BACKGROUND")
	self.backdrop:SetPoint("CENTER")
	self.backdrop:SetSize((RADIUS + ICON_SIZE) * 2, (RADIUS + ICON_SIZE) * 2)
	self.backdrop:SetColorTexture(0, 0, 0, 0.55)
	AddCircleMask(frame, self.backdrop)

	self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	self.title:SetPoint("CENTER", 0, 8)
	self.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.hint:SetPoint("TOP", self.title, "BOTTOM", 0, -4)

	frame:SetScript("OnUpdate", function() self:UpdateHighlight() end)
	header:HookScript("OnAttributeChanged", function(_, name, value)
		if name == "active" and value then
			self:Render(value)
		end
	end)
	return self
end

function Display:Render(key)
	self.key = key
	self.slices = ns.resolved and ns.resolved[key] or {}
	local n = #self.slices
	local applyStyle = STYLES[ForeverRingsDB.style] or STYLES.clean
	for i, slice in ipairs(self.slices) do
		local slot = self.slots[i] or CreateSlot(self.frame)
		self.slots[i] = slot
		local angle = math.rad((i - 1) * 360 / n)
		slot:ClearAllPoints()
		slot:SetPoint("CENTER", self.frame, "CENTER", math.sin(angle) * RADIUS, math.cos(angle) * RADIUS)
		slot.icon:SetTexture(slice.icon or 134400)
		slot.more:SetShown(slice.type == "ring")
		applyStyle(self, slot)
		slot:Show()
	end
	for i = n + 1, #self.slots do
		self.slots[i]:Hide()
	end
	self.hint:SetText((self.header:GetAttribute("depth") or 0) > 0 and "A select  ·  B back" or "A select  ·  B close")
	self:UpdateCounts()
end

-- Display only, safe in combat.
function Display:UpdateCounts()
	for i, slice in ipairs(self.slices) do
		local slot = self.slots[i]
		local count = slice.itemID and C_Item.GetItemCount(slice.itemID) or 0
		slot.count:SetText(count > 1 and count or "")
		slot.icon:SetDesaturated(slice.itemID ~= nil and count == 0)
	end
end

-- Mirrors the PICK snippet so the highlight matches what will be used.
function Display:SelectedSlice()
	local header, n = self.header, #self.slices
	local dx, dy = 0, 0
	if header:GetAttribute("held-right") then dx = dx + 1 end
	if header:GetAttribute("held-left") then dx = dx - 1 end
	if header:GetAttribute("held-up") then dy = dy + 1 end
	if header:GetAttribute("held-down") then dy = dy - 1 end
	if dx == 0 and dy == 0 then
		local mx0, my0 = header:GetAttribute("mx0"), header:GetAttribute("my0")
		if mx0 then
			local cx, cy = GetCursorPosition()
			local scale = header:GetEffectiveScale()
			local ex, ey = cx / scale - header:GetLeft() - mx0, cy / scale - header:GetBottom() - my0
			if ex * ex + ey * ey >= ns.DEAD_ZONE * ns.DEAD_ZONE then
				dx, dy = ex, ey
			end
		end
	end
	if n == 0 or (dx == 0 and dy == 0) then
		return nil
	end
	local step = 360 / n
	local angle = math.deg(math.atan2(dx, dy)) % 360
	return math.floor((angle + step / 2) / step) % n + 1
end

function Display:UpdateHighlight()
	local selected = self:SelectedSlice()
	local clean = ForeverRingsDB.style ~= "classic"
	for i = 1, #self.slices do
		local slot = self.slots[i]
		local on = i == selected
		slot.disc:SetAlpha(clean and on and 1 or 0)
		slot.glow:SetAlpha(not clean and on and 1 or 0)
		slot:SetScale(on and 1.15 or 1)
	end
	if #self.slices == 0 then
		self.title:SetText(ns.RingLabel(self.key) .. "\n|cff999999(empty)|r")
	elseif selected then
		self.title:SetText(self.slices[selected].name or "")
	else
		self.title:SetText(ns.RingLabel(self.key))
	end
end
