local _, ns = ...

-- Insecure visuals only. The secure header decides what happens; this file
-- draws the active ring, animates it and highlights the slice that would be
-- picked. Nothing here is protected, so it all keeps running in combat.

local RADIUS = 120
local ICON_SIZE = 46
local POINTER_RADIUS = 52
local OPEN_TIME = 0.22        -- seconds for the ring to open
local STAGGER = 0.02          -- extra delay per slot while opening
local SELECT_SCALE = 1.22
local PING_TIME = 0.3         -- the ring that ripples out on a new selection
local FLASH_TIME = 0.35       -- the icon that flashes when something is used
local IDLE_SPEED = 40         -- degrees per second the track light drifts
local STATE_INTERVAL = 0.2    -- seconds between cooldown/usability checks
local MEDIA = "Interface\\AddOns\\ForeverRings\\Media\\"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION_MARK = 134400

-- The track sits just inside the slots; its texture draws the line at 90% of
-- its radius. The backdrop is sized from the outer edge of the slots.
local TRACK_RADIUS = RADIUS - 36
local TRACK_SIZE = TRACK_RADIUS * 2 / 0.9
local OUTER_SIZE = (RADIUS + ICON_SIZE) * 2

local COLORS = {
	clean = { 0.35, 0.75, 1 },
	classic = { 1, 0.82, 0.25 },
}

local function AddCircleMask(frame, texture)
	local mask = frame:CreateMaskTexture()
	mask:SetAllPoints(texture)
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	texture:AddMaskTexture(mask)
	return mask
end

local function Clamp(p)
	return math.max(0, math.min(1, p))
end

local function EaseOut(p)
	return 1 - (1 - Clamp(p)) ^ 3
end

-- Overshoots a little before settling: the "pop".
local function EaseOutBack(p)
	p = Clamp(p)
	local c = 1.7
	return 1 + (c + 1) * (p - 1) ^ 3 + c * (p - 1) ^ 2
end

-- Moves `current` toward `target` at a frame-rate independent speed.
local function Approach(current, target, elapsed, speed)
	return current + (target - current) * math.min(1, elapsed * speed)
end

local function Texture(parent, layer, file, size, blend)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetTexture(MEDIA .. file)
	tex:SetSize(size, size)
	tex:SetPoint("CENTER")
	if blend then
		tex:SetBlendMode(blend)
	end
	return tex
end

local function CreateSlot(parent)
	local slot = CreateFrame("Frame", nil, parent)
	slot:SetSize(ICON_SIZE, ICON_SIZE)
	slot.scale = 1

	-- Soft light behind the selected slot.
	slot.halo = Texture(slot, "BACKGROUND", "glow", ICON_SIZE * 2.4, "ADD")

	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetAllPoints()
	slot.iconMask = AddCircleMask(slot, slot.icon)

	-- Second, smaller icon (the drink of "Eat & Drink").
	slot.icon2 = slot:CreateTexture(nil, "ARTWORK", nil, 1)
	slot.icon2:SetSize(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	slot.icon2:SetPoint("BOTTOMRIGHT", 4, -4)
	AddCircleMask(slot, slot.icon2)

	-- Clean: thin rim that lights up when selected.
	slot.rim = Texture(slot, "OVERLAY", "rim", ICON_SIZE + 10)
	-- Ripple when the selection lands on this slot.
	slot.ping = Texture(slot, "OVERLAY", "rim", ICON_SIZE + 10, "ADD")
	slot.ping:SetAlpha(0)
	slot.pingAge = PING_TIME

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
	clean = function(slot, color)
		slot.icon:SetTexCoord(0, 1, 0, 1)
		slot.icon:AddMaskTexture(slot.iconMask)
		slot.cooldown:SetSwipeTexture(CIRCLE_MASK)
		slot.border:Hide()
		slot.rim:Show()
		slot.glow:SetAlpha(0)
	end,
	classic = function(slot, color)
		slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		slot.icon:RemoveMaskTexture(slot.iconMask)
		slot.cooldown:SetSwipeTexture("")
		slot.border:Show()
		slot.rim:Hide()
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

-- The flash lives outside the ring, so it keeps playing after the secure code
-- has already hidden the ring.
local function CreateFlash()
	local flash = CreateFrame("Frame", nil, UIParent)
	flash:SetSize(ICON_SIZE * 1.4, ICON_SIZE * 1.4)
	flash:SetPoint("CENTER")
	flash:SetFrameStrata("DIALOG")
	flash.glow = Texture(flash, "BACKGROUND", "glow", ICON_SIZE * 4, "ADD")
	flash.icon = flash:CreateTexture(nil, "ARTWORK")
	flash.icon:SetAllPoints()
	flash.mask = AddCircleMask(flash, flash.icon)
	flash.age, flash.baseScale = FLASH_TIME, 1
	flash:Hide()
	flash:SetScript("OnUpdate", function(self, elapsed)
		self.age = self.age + (elapsed or 0)
		local p = Clamp(self.age / FLASH_TIME)
		self:SetScale(self.baseScale * (1 + 0.5 * EaseOut(p)))
		self:SetAlpha(1 - p)
		if p >= 1 then
			self:Hide()
		end
	end)
	return flash
end

-- While a ring is open the aiming stick shouldn't also turn the camera.
-- The speeds are saved so a crash or reload mid-ring still gets them back.
-- Turning speed, plus how far the stick can look around.
local CAMERA_CVARS = { "GamePadCameraYawSpeed", "GamePadCameraPitchSpeed", "GamePadCameraLookMaxYaw", "GamePadCameraLookMaxPitch" }
local warned = false

function ns.ThawCamera()
	local saved = ForeverRingsDB.camera
	if saved then
		for cvar, value in pairs(saved) do
			SetCVar(cvar, value)
		end
		ForeverRingsDB.camera = nil
	end
end

function ns.FreezeCamera()
	if ForeverRingsDB.input ~= "rstick" or ForeverRingsDB.camera or not GetCVar then
		return
	end
	local saved = {}
	for _, cvar in ipairs(CAMERA_CVARS) do
		local value = GetCVar(cvar)
		if value then
			saved[cvar] = value
			SetCVar(cvar, "0")
			if tonumber(GetCVar(cvar)) ~= 0 and not warned then
				warned = true
				ns.Print("Couldn't hold the camera still (" .. cvar .. " stays " .. tostring(GetCVar(cvar)) .. ").")
			end
		end
	end
	ForeverRingsDB.camera = next(saved) and saved or nil
end

local Display = {}
Display.__index = Display

function ns.CreateDisplay(header)
	local self = setmetatable({
		header = header, slots = {}, slices = {},
		openAge = 0, time = 0, pointerAngle = 0, lightAngle = 0, stateAge = 0,
	}, Display)

	local frame = CreateFrame("Frame", nil, header)
	frame:SetAllPoints()
	self.frame = frame

	self.backdrop = Texture(frame, "BACKGROUND", "vignette", OUTER_SIZE * 1.4)
	self.backdrop:SetVertexColor(0, 0, 0)

	self.track = Texture(frame, "BORDER", "track", TRACK_SIZE)
	-- A light that runs along the track toward the selection.
	self.trackLight = Texture(frame, "ARTWORK", "glow", 90, "ADD")

	self.centerGlow = Texture(frame, "BORDER", "glow", 150, "ADD")

	-- Dot that swings toward the slot the stick points at.
	self.pointer = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	self.pointer:SetSize(10, 10)
	self.pointer:SetColorTexture(1, 1, 1, 1)
	AddCircleMask(frame, self.pointer)
	self.pointer:Hide()

	self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	self.title:SetPoint("CENTER", 0, 8)
	self.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.hint:SetPoint("TOP", self.title, "BOTTOM", 0, -4)

	self.flash = CreateFlash()

	frame:SetScript("OnUpdate", function(_, elapsed) self:Animate(elapsed or 0) end)
	frame:SetScript("OnShow", ns.FreezeCamera)
	frame:SetScript("OnHide", ns.ThawCamera)
	header:HookScript("OnAttributeChanged", function(_, name, value)
		if name == "active" and value then
			self:Render(value)
		elseif name:sub(1, 5) == "last:" and name:sub(-2) == ":v" then
			-- The snippets store the last action right as they use it.
			self:Flash()
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

	local style = ForeverRingsDB.style == "classic" and "classic" or "clean"
	local color = COLORS[style]
	self.color = color
	self.track:SetVertexColor(color[1], color[2], color[3])
	self.trackLight:SetVertexColor(color[1], color[2], color[3])
	self.centerGlow:SetVertexColor(color[1], color[2], color[3])
	self.pointer:SetVertexColor(color[1], color[2], color[3])
	self.flash.glow:SetVertexColor(color[1], color[2], color[3])

	local n = #self.slices
	for i, slice in ipairs(self.slices) do
		local slot = self.slots[i] or CreateSlot(self.frame)
		self.slots[i] = slot
		slot.angle = (i - 1) * 360 / n
		slot.scale = 1
		slot.pingAge = PING_TIME
		slot.icon:SetTexture(slice.icon or QUESTION_MARK)
		slot.icon2:SetTexture(slice.icon2)
		slot.icon2:SetShown(slice.icon2 ~= nil)
		slot.more:SetShown(slice.type == "ring")
		slot.halo:SetVertexColor(color[1], color[2], color[3])
		slot.ping:SetVertexColor(color[1], color[2], color[3])
		STYLES[style](slot, color)
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
	local parts = { "A / click select", depth > 0 and "B / right-click back" or "B / right-click close" }
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

-- Brief flash of the used icon in the middle of the screen.
function Display:Flash()
	local slice = self.selected and self.slices[self.selected]
	if not (slice and slice.icon) then
		return
	end
	local flash = self.flash
	flash.icon:SetTexture(slice.icon)
	flash.baseScale = ForeverRingsDB.scale or 1
	flash.age = 0
	flash:SetScale(flash.baseScale)
	flash:SetAlpha(1)
	flash:Show()
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
		dx, dy = header:GetAttribute("aim-dx") or 0, header:GetAttribute("aim-dy") or 0
	end
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

local function PlaceOnCircle(region, frame, angle, radius)
	local rad = math.rad(angle)
	region:ClearAllPoints()
	region:SetPoint("CENTER", frame, "CENTER", math.sin(rad) * radius, math.cos(rad) * radius)
end

function Display:Animate(elapsed)
	self.time = self.time + elapsed
	self.openAge = self.openAge + elapsed
	self.stateAge = self.stateAge + elapsed
	if self.stateAge >= STATE_INTERVAL then
		self:UpdateState()
	end

	-- Opening: backdrop swells, track turns into place, everything fades in.
	local open = EaseOut(self.openAge / OPEN_TIME)
	self.frame:SetAlpha(open)
	self.backdrop:SetSize(OUTER_SIZE * (1.15 + 0.25 * open), OUTER_SIZE * (1.15 + 0.25 * open))
	self.track:SetRotation(math.rad(-50 * (1 - open)))
	self.track:SetSize(TRACK_SIZE * (0.85 + 0.15 * open), TRACK_SIZE * (0.85 + 0.15 * open))

	local selected = self:SelectedSlice()
	if selected ~= self.selected then
		if selected then
			if StickHeld(self.header) then
				Vibrate()
			end
			self.slots[selected].pingAge = 0
		end
		self.selected = selected
	end

	local clean = ForeverRingsDB.style ~= "classic"
	local pulse = 0.75 + 0.25 * math.sin(self.time * 5)
	local color = self.color or COLORS.clean
	for i = 1, #self.slices do
		local slot = self.slots[i]
		local on = i == selected
		-- Slots pop out from the centre one after another.
		local p = EaseOutBack((self.openAge - (i - 1) * STAGGER) / OPEN_TIME)
		PlaceOnCircle(slot, self.frame, slot.angle, RADIUS * (0.5 + 0.5 * p))
		slot.scale = Approach(slot.scale, on and SELECT_SCALE or 1, elapsed, 14)
		slot:SetScale(math.max(0.01, slot.scale * (0.5 + 0.5 * p)))
		-- With something selected, the rest steps back a little.
		slot:SetAlpha(Clamp(p) * ((selected and not on) and 0.65 or 1))
		slot.halo:SetAlpha(on and pulse or 0)
		slot.glow:SetAlpha(not clean and on and pulse or 0)
		if on then
			slot.rim:SetVertexColor(color[1], color[2], color[3])
			slot.rim:SetAlpha(1)
		else
			slot.rim:SetVertexColor(1, 1, 1)
			slot.rim:SetAlpha(0.3)
		end
		slot.pingAge = slot.pingAge + elapsed
		local ping = Clamp(slot.pingAge / PING_TIME)
		slot.ping:SetAlpha(ping < 1 and (1 - ping) * 0.9 or 0)
		slot.ping:SetSize((ICON_SIZE + 10) * (1 + 0.7 * ping), (ICON_SIZE + 10) * (1 + 0.7 * ping))
	end

	-- The track light follows the selection, or drifts slowly when idle.
	if selected then
		local target = self.slots[selected].angle
		local diff = (target - self.pointerAngle + 180) % 360 - 180
		self.pointerAngle = self.pointer:IsShown() and Approach(self.pointerAngle, self.pointerAngle + diff, elapsed, 20) or target
		self.lightAngle = self.pointerAngle
		PlaceOnCircle(self.pointer, self.frame, self.pointerAngle, POINTER_RADIUS)
		self.pointer:Show()
		self.trackLight:SetAlpha(0.9)
		self.centerGlow:SetAlpha(0.35)
	else
		self.lightAngle = (self.lightAngle + IDLE_SPEED * elapsed) % 360
		self.pointer:Hide()
		self.trackLight:SetAlpha(0.35 + 0.15 * math.sin(self.time * 2))
		self.centerGlow:SetAlpha(0.15)
	end
	PlaceOnCircle(self.trackLight, self.frame, self.lightAngle, TRACK_RADIUS)

	if #self.slices == 0 then
		self.title:SetText(ns.RingLabel(self.key) .. "\n|cff999999(empty)|r")
	elseif selected then
		self.title:SetText(self.slices[selected].name or "")
	else
		self.title:SetText(ns.RingLabel(self.key))
	end
end
