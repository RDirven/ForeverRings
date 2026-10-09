local _, ns = ...

-- Insecure visuals only. The secure header decides what happens; this file
-- draws the active ring, animates it and highlights the slice that would be
-- picked. Nothing here is protected, so it all keeps running in combat.

local RADIUS = 120
local ICON_SIZE = 46
local POINTER_RADIUS = 52
local OPEN_TIME = 0.16        -- seconds for the ring to pop open
local STAGGER = 0.015         -- extra delay per slot while opening
local SELECT_SCALE = 1.2
local STATE_INTERVAL = 0.2    -- seconds between cooldown/usability checks
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ACCENT = { 0.35, 0.75, 1 }
local QUESTION_MARK = 134400

local function AddCircleMask(frame, texture)
	local mask = frame:CreateMaskTexture()
	mask:SetAllPoints(texture)
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	texture:AddMaskTexture(mask)
	return mask
end

local function EaseOut(p)
	p = math.max(0, math.min(1, p))
	return 1 - (1 - p) ^ 3
end

-- Moves `current` toward `target` at a frame-rate independent speed.
local function Approach(current, target, elapsed, speed)
	return current + (target - current) * math.min(1, elapsed * speed)
end

local function CreateSlot(parent)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(ICON_SIZE, ICON_SIZE)
	slot.scale = 1

	-- Clean: accent disc behind the icon when selected.
	slot.disc = slot:CreateTexture(nil, "BACKGROUND")
	slot.disc:SetPoint("CENTER")
	slot.disc:SetSize(ICON_SIZE + 12, ICON_SIZE + 12)
	slot.disc:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
	AddCircleMask(slot, slot.disc)

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetAllPoints()
	slot.iconMask = AddCircleMask(slot, slot.icon)

	-- Second, smaller icon (the drink of "Eat & Drink").
	slot.icon2 = slot:CreateTexture(nil, "ARTWORK", nil, 1)
	slot.icon2:SetSize(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	slot.icon2:SetPoint("BOTTOMRIGHT", 4, -4)
	AddCircleMask(slot, slot.icon2)

	-- Classic: action button border plus additive glow.
	slot.border = slot:CreateTexture(nil, "OVERLAY")
	slot.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	slot.border:SetPoint("CENTER")
	slot.border:SetSize(ICON_SIZE * 64 / 36, ICON_SIZE * 64 / 36)
	slot.glow = slot:CreateTexture(nil, "OVERLAY", nil, 1)
	slot.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	slot.glow:SetBlendMode("ADD")
	slot.glow:SetAllPoints()

	slot.cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
	slot.cooldown:SetAllPoints(slot.icon)
	slot.cooldown:SetDrawEdge(false)

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
		slot.cooldown:SetSwipeTexture(CIRCLE_MASK)
		slot.border:Hide()
		slot.glow:SetAlpha(0)
		display.backdrop:Show()
		display.pointer:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	end,
	classic = function(display, slot)
		slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		slot.icon:RemoveMaskTexture(slot.iconMask)
		slot.cooldown:SetSwipeTexture("")
		slot.border:Show()
		slot.disc:SetAlpha(0)
		display.backdrop:Hide()
		display.pointer:SetColorTexture(1, 0.82, 0, 1)
	end,
}

-- Name for a stored action, for the "Tap:" hint.
local function ActionName(kind, value)
	for _, slices in pairs(ns.resolved or {}) do
		for _, slice in ipairs(slices) do
			if slice.type == kind and slice.value == value and slice.name then
				return slice.name
			end
		end
	end
	if kind == "spell" then
		return C_Spell.GetSpellName(value)
	elseif kind == "toy" then
		return C_Item.GetItemNameByID(value)
	elseif kind == "item" then
		local id = tonumber(tostring(value):match("(%d+)"))
		return id and C_Item.GetItemNameByID(id)
	end
end

local function Vibrate()
	if ForeverRingsDB.vibration and C_GamePad and C_GamePad.SetVibration then
		C_GamePad.SetVibration("Low", 0.35)
		C_Timer.After(0.05, function()
			if C_GamePad.StopVibration then
				C_GamePad.StopVibration()
			end
		end)
	end
end

-- Start and duration go straight to the Cooldown widget without any math on
-- them, which also keeps working if the client hides exact values in combat.
local function Cooldown(slice)
	if slice.type == "spell" then
		local info = C_Spell.GetSpellCooldown(slice.value)
		if info then
			return info.startTime, info.duration
		end
	elseif slice.itemID or slice.type == "toy" then
		return C_Container.GetItemCooldown(slice.itemID or slice.value)
	end
end

-- usable, lacking power
local function Usable(slice)
	if slice.type == "spell" then
		return C_Spell.IsSpellUsable(slice.value)
	elseif slice.itemID then
		return C_Item.IsUsableItem(slice.itemID)
	end
	return true, false
end

local Display = {}
Display.__index = Display

function ns.CreateDisplay(header)
	local self = setmetatable({ header = header, slots = {}, slices = {}, openAge = 0, time = 0, pointerAngle = 0, stateAge = 0 }, Display)

	local frame = CreateFrame("Frame", nil, header)
	frame:SetAllPoints()
	self.frame = frame

	self.backdrop = frame:CreateTexture(nil, "BACKGROUND")
	self.backdrop:SetPoint("CENTER")
	self.backdrop:SetSize((RADIUS + ICON_SIZE) * 2, (RADIUS + ICON_SIZE) * 2)
	self.backdrop:SetColorTexture(0, 0, 0, 0.55)
	AddCircleMask(frame, self.backdrop)

	-- Dot that swings toward the slot the stick points at.
	self.pointer = frame:CreateTexture(nil, "ARTWORK")
	self.pointer:SetSize(10, 10)
	AddCircleMask(frame, self.pointer)
	self.pointer:Hide()

	self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	self.title:SetPoint("CENTER", 0, 8)
	self.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.hint:SetPoint("TOP", self.title, "BOTTOM", 0, -4)

	frame:SetScript("OnUpdate", function(_, elapsed) self:Animate(elapsed or 0) end)
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
	self.openAge = 0
	self.selected = nil
	self.pointer:Hide()
	self.frame:SetScale(ForeverRingsDB.scale or 1)
	local n = #self.slices
	local applyStyle = STYLES[ForeverRingsDB.style] or STYLES.clean
	for i, slice in ipairs(self.slices) do
		local slot = self.slots[i] or CreateSlot(self.frame)
		self.slots[i] = slot
		slot.angle = (i - 1) * 360 / n
		slot.scale = 1
		slot.icon:SetTexture(slice.icon or QUESTION_MARK)
		slot.icon2:SetTexture(slice.icon2)
		slot.icon2:SetShown(slice.icon2 ~= nil)
		slot.more:SetShown(slice.type == "ring")
		applyStyle(self, slot)
		slot:Show()
	end
	for i = n + 1, #self.slots do
		self.slots[i]:Hide()
	end
	self:UpdateHint()
	self:UpdateCounts()
	self:UpdateState()
	self:Animate(0)
end

-- Cooldown swipes and dimming for things you can't use right now.
function Display:UpdateState()
	self.stateAge = 0
	for i, slice in ipairs(self.slices) do
		local slot = self.slots[i]
		local start, duration = Cooldown(slice)
		if start then
			slot.cooldown:SetCooldown(start, duration)
		else
			slot.cooldown:Clear()
		end
		local usable, noPower = Usable(slice)
		if noPower then
			slot.icon:SetVertexColor(0.45, 0.55, 1)
		elseif usable == false then
			slot.icon:SetVertexColor(0.4, 0.4, 0.4)
		else
			slot.icon:SetVertexColor(1, 1, 1)
		end
	end
end

function Display:UpdateHint()
	local header = self.header
	local depth = header:GetAttribute("depth") or 0
	local parts = { "A select", depth > 0 and "B back" or "B close" }
	if depth == 0 and ForeverRingsDB.tapRepeat and not header:GetAttribute("sticky") then
		local name = ActionName(header:GetAttribute("last:" .. self.key .. ":t"), header:GetAttribute("last:" .. self.key .. ":v"))
		if name then
			table.insert(parts, 1, "Tap: " .. name)
		end
	end
	self.hint:SetText(table.concat(parts, "  ·  "))
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

local function StickHeld(header)
	return header:GetAttribute("held-up") or header:GetAttribute("held-right")
		or header:GetAttribute("held-down") or header:GetAttribute("held-left")
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

function Display:Animate(elapsed)
	self.time = self.time + elapsed
	self.openAge = self.openAge + elapsed
	self.stateAge = self.stateAge + elapsed
	if self.stateAge >= STATE_INTERVAL then
		self:UpdateState()
	end
	self.frame:SetAlpha(EaseOut(self.openAge / OPEN_TIME))

	local selected = self:SelectedSlice()
	if selected ~= self.selected then
		if selected and StickHeld(self.header) then
			Vibrate()
		end
		self.selected = selected
	end

	local clean = ForeverRingsDB.style ~= "classic"
	local pulse = 0.8 + 0.2 * math.sin(self.time * 5)
	for i = 1, #self.slices do
		local slot = self.slots[i]
		local on = i == selected
		-- Slots pop out from the centre one after another.
		local p = EaseOut((self.openAge - (i - 1) * STAGGER) / OPEN_TIME)
		local rad = math.rad(slot.angle)
		local radius = RADIUS * (0.55 + 0.45 * p)
		slot:ClearAllPoints()
		slot:SetPoint("CENTER", self.frame, "CENTER", math.sin(rad) * radius, math.cos(rad) * radius)
		slot.scale = Approach(slot.scale, on and SELECT_SCALE or 1, elapsed, 16)
		slot:SetScale(slot.scale * (0.6 + 0.4 * p))
		slot:SetAlpha(p)
		slot.disc:SetAlpha(clean and on and pulse or 0)
		slot.glow:SetAlpha(not clean and on and pulse or 0)
	end

	if selected then
		-- Swing along the shortest way round.
		local target = self.slots[selected].angle
		local diff = (target - self.pointerAngle + 180) % 360 - 180
		self.pointerAngle = self.pointer:IsShown() and Approach(self.pointerAngle, self.pointerAngle + diff, elapsed, 20) or target
		local rad = math.rad(self.pointerAngle)
		self.pointer:ClearAllPoints()
		self.pointer:SetPoint("CENTER", self.frame, "CENTER", math.sin(rad) * POINTER_RADIUS, math.cos(rad) * POINTER_RADIUS)
		self.pointer:Show()
	else
		self.pointer:Hide()
	end

	if #self.slices == 0 then
		self.title:SetText(ns.RingLabel(self.key) .. "\n|cff999999(empty)|r")
	elseif selected then
		self.title:SetText(self.slices[selected].name or "")
	else
		self.title:SetText(ns.RingLabel(self.key))
	end
end
