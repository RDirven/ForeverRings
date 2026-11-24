local _, ns = ...

-- Insecure visuals only. The secure header decides what happens; this file
-- draws the active ring, animates it and highlights the slice that would be
-- picked. Nothing here is protected, so it all keeps running in combat.

local RADIUS = 120
local ICON_SIZE = 46
local WEDGE_SIZE = (120 + 46) * 2 -- Party ring: diameter of the pizza
local RINGS = 12                   -- health rings per slice, crust to centre
local RING_RANGE = 0.01            -- a ring goes from empty to full over 1% health
local DEBUFF_SIZE = 22             -- dispellable debuff icons under a name
local AURA_INTERVAL = 0.25         -- seconds between debuff scans
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
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

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

	-- The slot's own key, if it has one.
	slot.keyLabel = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	slot.keyLabel:SetPoint("TOPLEFT", -4, 4)

	-- Party ring: the member's name, on their pizza slice (see LayoutWedges),
	-- and the debuffs you can dispel from them under it.
	slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	slot.label:SetPoint("CENTER")
	slot.hots = {}
	for h = 1, 3 do
		local icon = slot:CreateTexture(nil, "OVERLAY", nil, 2)
		icon:SetSize(DEBUFF_SIZE - 4, DEBUFF_SIZE - 4)
		icon:SetPoint("BOTTOM", slot.label, "TOP", (h - 2) * (DEBUFF_SIZE - 1), 4)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:Hide()
		slot.hots[h] = icon
	end
	slot.debuffs = {}
	for d = 1, 3 do
		local icon = slot:CreateTexture(nil, "OVERLAY", nil, 2)
		icon:SetSize(DEBUFF_SIZE, DEBUFF_SIZE)
		icon:SetPoint("TOP", slot.label, "BOTTOM", (d - 2) * (DEBUFF_SIZE + 3), -4)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:Hide()
		slot.debuffs[d] = icon
	end

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
		return ns.SpellLabel(value)
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

-- A plain value we may use. In combat newer clients hand addons "secret"
-- health and cooldown values: health still goes to a StatusBar as it is,
-- but addon code can't compare them or give them to a Cooldown.
local function Plain(v)
	return v ~= nil and not (issecretvalue and issecretvalue(v))
end

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
-- A frame takes the sticks, free look goes off and the stick camera speeds go
-- as low as the client allows (WoW Forever won't go below 0.1). What was there is saved, so a crash or reload mid-ring still
-- gets it back.
local CAMERA_CVARS = { "GamePadCameraYawSpeed", "GamePadCameraPitchSpeed", "GamePadCameraLookMaxYaw", "GamePadCameraLookMaxPitch" }
local FREELOOK = "freelook"

-- A frame that takes the sticks while a ring is open, so they don't reach
-- the camera. The stick direction buttons (PADRSTICKUP...) still go to the
-- ring's bindings.
local stickEater

-- What the client is (and isn't) sending, for /frings debug.
ns.diag = { opens = 0, stickEvents = 0, dirPresses = 0, fallbackAims = 0 }

-- Which stick names count as the aiming stick.
local AIM_STICKS = {
	rstick = { Right = true, Camera = true, Look = true },
	lstick = { Left = true, Movement = true, Move = true },
}

-- Backup for the stick direction buttons. Some sessions the client doesn't
-- deliver PADRSTICKUP and friends to the ring until a /reload, while the
-- stick itself still reaches this frame. Out of combat we then write the aim
-- ourselves, so aiming works and releasing the ring button (or A) picks.
-- In combat only the secure bindings may change the ring.
local function OnStick(_, stick, x, y)
	local header = ns.header
	local wanted = AIM_STICKS[ForeverRingsDB.input]
	if not (header and header:IsShown() and wanted and wanted[stick] and x and y) then
		return
	end
	ns.diag.stickEvents = ns.diag.stickEvents + 1
	ns.lastStickY = y
	if InCombatLockdown() or x * x + y * y < 0.25 then
		-- Let go: keep the last aim, like the secure code does.
		return
	end
	ns.diag.fallbackAims = ns.diag.fallbackAims + 1
	header:SetAttribute("aim-dx", x)
	header:SetAttribute("aim-dy", y * (ForeverRingsDB.stickYSign or 1))
	header:SetAttribute("moved", true)
end

local function EatSticks(on)
	if not stickEater then
		stickEater = CreateFrame("Frame", nil, UIParent)
		if not stickEater.EnableGamePadStick then
			return
		end
		stickEater:SetScript("OnGamePadStick", OnStick)
	end
	if stickEater.EnableGamePadStick then
		pcall(stickEater.EnableGamePadStick, stickEater, on)
	end
end

-- Some clients refuse 0 for the camera speeds; take the lowest value that sticks.
local LOW_VALUES = { "0", "0.001", "0.01", "0.05", "0.1", "0.2" }

local function SetLowest(cvar)
	for _, value in ipairs(LOW_VALUES) do
		SetCVar(cvar, value)
		local now = tonumber(GetCVar(cvar))
		if now and now <= tonumber(value) + 0.0001 then
			return
		end
	end
end

function ns.ThawCamera()
	local saved = ForeverRingsDB.camera
	if not saved then
		return
	end
	ForeverRingsDB.camera = nil
	EatSticks(false)
	for name, value in pairs(saved) do
		if name == "sticks" then
			-- only the sticks were taken, given back above
		elseif name == FREELOOK then
			if SetGamePadFreeLook then
				pcall(SetGamePadFreeLook, value)
			end
		else
			SetCVar(name, value)
		end
	end
end

function ns.FreezeCamera()
	if not ForeverRingsDB.holdCamera or ForeverRingsDB.input == "dpad" or ForeverRingsDB.camera then
		return
	end
	local saved = {}
	-- Taking the sticks stops the camera (right stick) and walking (left).
	EatSticks(true)
	if ForeverRingsDB.input ~= "rstick" then
		ForeverRingsDB.camera = { sticks = true }
		return
	end
	if SetGamePadFreeLook and IsGamePadFreelookEnabled then
		local on = IsGamePadFreelookEnabled() and true or false
		if pcall(SetGamePadFreeLook, false) then
			saved[FREELOOK] = on
		end
	end
	for _, cvar in ipairs(CAMERA_CVARS) do
		local value = GetCVar and GetCVar(cvar)
		if value then
			saved[cvar] = value
			SetLowest(cvar)
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
	frame:SetScript("OnShow", function()
		ns.diag.opens = ns.diag.opens + 1
		ns.FreezeCamera()
	end)
	frame:SetScript("OnHide", ns.ThawCamera)
	header:HookScript("OnAttributeChanged", function(_, name, value)
		if value and name:sub(1, 5) == "held-" and name ~= "held-" then
			ns.diag.dirPresses = ns.diag.dirPresses + 1
			-- Learn which way is up from a real direction press, in case the
			-- client reports stick y the other way round.
			local y = ns.lastStickY
			if y and math.abs(y) > 0.5 and (name == "held-up" or name == "held-down") then
				local up = (name == "held-up") == (y > 0)
				ForeverRingsDB.stickYSign = up and 1 or -1
			end
		end
	end)
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

-- Party ring: the ring becomes a pizza, one slice per member. Health fills a
-- slice from the crust toward the centre: twelve thin rings, each a
-- StatusBar (the only thing that takes the client's secret health values)
-- that is either full or empty depending on whether health is above its
-- step. Losing health empties the rings near the centre first.
local function NewHealthRing(frame, k)
	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetFrameLevel(frame:GetFrameLevel())
	bar:SetSize(WEDGE_SIZE, WEDGE_SIZE)
	bar:SetPoint("CENTER")
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	-- Full above this ring's step, empty below: k = 1 (the crust) lights at
	-- any health, the innermost only near full.
	local step = (k - 1) / RINGS
	bar:SetMinMaxValues(step, step + RING_RANGE)
	bar.step = step
	local texture = bar:GetStatusBarTexture()
	bar.wedgeMask = bar:CreateMaskTexture()
	bar.wedgeMask:SetSize(WEDGE_SIZE, WEDGE_SIZE)
	bar.wedgeMask:SetPoint("CENTER", frame, "CENTER")
	texture:AddMaskTexture(bar.wedgeMask)
	bar.ringMask = bar:CreateMaskTexture()
	bar.ringMask:SetSize(WEDGE_SIZE, WEDGE_SIZE)
	bar.ringMask:SetPoint("CENTER", frame, "CENTER")
	bar.k = k
	texture:AddMaskTexture(bar.ringMask)
	return bar
end

function Display:LayoutWedges()
	self.wedges = self.wedges or {}
	local n = self.key == "party" and #self.slices or 0
	for i = 1, math.max(n, #self.wedges) do
		local w = self.wedges[i]
		if i <= n and not w then
			w = { bands = {} }
			w.bg = self.frame:CreateTexture(nil, "BACKGROUND", nil, 3)
			w.bg:SetSize(WEDGE_SIZE, WEDGE_SIZE)
			w.bg:SetPoint("CENTER")
			for k = 1, RINGS do
				w.bands[k] = NewHealthRing(self.frame, k)
			end
			self.wedges[i] = w
		end
		if w then
			local on = i <= n
			local member = on and self.slices[i].unit ~= nil
			w.bg:SetShown(on)
			local file = on and (MEDIA .. "wedge" .. n .. "_" .. i)
			-- Health grows from the crust inward, or from the centre outward.
			local rings = ForeverRingsDB.partyFill == "centre" and "ringc" or "ring"
			for _, band in ipairs(w.bands) do
				band:SetShown(member)
				band.ringMask:SetTexture(MEDIA .. rings .. band.k, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				if file then
					band.wedgeMask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
				end
			end
			if on then
				w.bg:SetTexture(file)
				w.bg:SetVertexColor(0.05, 0.06, 0.09, 0.92)
				self.slots[i].bands = w.bands
			end
		end
	end
end

-- Icons of the debuffs on `unit` that you can dispel ("RAID" filter), up to
-- three. Newer clients may hide aura details in combat: then nothing shows.
local function DispelIcons(unit)
	local icons = {}
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HARMFUL|RAID")
			if not ok or not aura then
				break
			end
			icons[#icons + 1] = aura.icon
			if #icons == 3 then
				break
			end
		end
	elseif UnitDebuff then
		for index = 1, 40 do
			local name, icon = UnitDebuff(unit, index, "RAID")
			if not name then
				break
			end
			icons[#icons + 1] = icon
			if #icons == 3 then
				break
			end
		end
	end
	return icons
end

-- /frings partydebug: what the Party ring's health rings look like to the
-- client, to see why a slice stays dark.
function ns.PartyDebug()
	local d = ns.display
	local function Show(v)
		if v == nil then return "nil" end
		if issecretvalue and issecretvalue(v) then return "secret" end
		return tostring(v)
	end
	ns.Print("UnitHealthPercent: " .. (UnitHealthPercent and Show(UnitHealthPercent("player")) or "missing")
		.. "  health: " .. Show(UnitHealth("player")) .. "/" .. Show(UnitHealthMax("player")))
	local slot = d and d.slots[1]
	local band = slot and slot.bands and slot.bands[1]
	if not band then
		return ns.Print("No Party ring drawn yet: open it once first.")
	end
	local tex = band:GetStatusBarTexture()
	local lo, hi = band:GetMinMaxValues()
	ns.Print(("ring 1: shown %s visible %s alpha %s  range %s-%s value %s  size %dx%d  masks %s  file %s"):format(
		tostring(band:IsShown()), tostring(band:IsVisible()), Show(band:GetAlpha()), Show(lo), Show(hi), Show(band:GetValue()),
		band:GetWidth(), band:GetHeight(), tex.GetNumMaskTextures and tostring(tex:GetNumMaskTextures()) or "?", tostring(tex:GetTexture())))
end

-- Icons of your own buffs (HoTs, shields) on `unit`, up to three.
-- Which of your buffs count: not the ones you hid (/frings hidebuff), and
-- with "HoTs only" nothing that lasts over five minutes (Blessing of the
-- Bronze, Fortitude...). When the client hides the details in combat, a buff
-- shows.
local HOT_MAX = 300

local function ShowsBuff(name, duration)
	local ok, hidden = pcall(function()
		return name ~= nil and ForeverRingsDB.hiddenBuffs[name:lower()] == true
	end)
	if ok and hidden then
		return false
	end
	if ForeverRingsDB.partyBuffs ~= "all" then
		local okLong, long = pcall(function()
			return duration ~= nil and (duration == 0 or duration > HOT_MAX)
		end)
		if okLong and long then
			return false
		end
	end
	return true
end

local function YourHots(unit)
	local icons = {}
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL|PLAYER")
			if not ok or not aura then
				break
			end
			if ShowsBuff(aura.name, aura.duration) then
				icons[#icons + 1] = aura.icon
				if #icons == 3 then
					break
				end
			end
		end
	elseif UnitBuff then
		for index = 1, 40 do
			local name, icon, _, _, duration = UnitBuff(unit, index, "PLAYER")
			if not name then
				break
			end
			if ShowsBuff(name, duration) then
				icons[#icons + 1] = icon
				if #icons == 3 then
					break
				end
			end
		end
	end
	return icons
end

local function ShowIcons(textures, icons)
	local any = false
	for d, texture in ipairs(textures) do
		local shown = icons[d] ~= nil and pcall(texture.SetTexture, texture, icons[d])
		texture:SetShown(shown and true or false)
		any = any or shown
	end
	return any
end

-- Dispellable debuffs under the name; your HoTs above it, with a green circle.
function Display:UpdateDebuffs()
	for i, slice in ipairs(self.slices) do
		local slot = self.slots[i]
		ShowIcons(slot.debuffs, slice.unit and DispelIcons(slice.unit) or {})
		local hot = ShowIcons(slot.hots, slice.unit and YourHots(slice.unit) or {})
		slot.hasHot = hot and true or nil
		slot.rim:SetShown(slot.hasHot or false)
	end
end

-- How full a member is, 0..1, as the client gives it (maybe secret).
-- UnitHealthPercent hands back a value StatusBars accept even in combat.
function Display:HealthFraction(unit, health, maxHealth)
	local pct = UnitHealthPercent and UnitHealthPercent(unit)
	if pct ~= nil then
		if Plain(pct) and pct > 1 then
			self.percentScale = 100 -- this client counts to 100
		end
		return pct, self.percentScale or 1
	end
	if Plain(health) and Plain(maxHealth) and maxHealth > 0 then
		return health / maxHealth, 1
	end
	return 1, 1
end

-- Short name of a key for on a slot: A/B/X/Y for the face buttons, D-pad and
-- shoulders shortened, keyboard keys with s-/c-/a- for Shift/Ctrl/Alt.
local SHORT_KEYS = {
	PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y",
	PADDUP = "D^", PADDDOWN = "Dv", PADDLEFT = "D<", PADDRIGHT = "D>",
	PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT",
	PADLSTICK = "L3", PADRSTICK = "R3", PADBACK = "Back", PADFORWARD = "Start",
	PADPADDLE1 = "P1", PADPADDLE2 = "P2", PADPADDLE3 = "P3", PADPADDLE4 = "P4",
}

function ns.ShortKey(binding)
	if not binding then
		return nil
	end
	local mods, key = binding:match("^(.-)([^%-]+)$")
	mods = (mods or ""):gsub("SHIFT%-", "s-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-")
	return mods .. (SHORT_KEYS[key] or key)
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
		slot.icon:SetAlpha(slice.empty and 0.25 or 1)
		slot.icon:SetShown(self.key ~= "party")
		slot.label:SetShown(slice.unit ~= nil)
		for _, debuff in ipairs(slot.debuffs) do
			debuff:Hide()
		end
		for _, hot in ipairs(slot.hots) do
			hot:Hide()
		end
		slot.hasHot = nil
		if slice.unit then
			local r, g, b = ns.ClassColor(slice.unit)
			slot.label:SetText(slice.name)
			slot.label:SetTextColor(r, g, b)
		end
		slot.halo:SetVertexColor(color[1], color[2], color[3])
		slot.ping:SetVertexColor(color[1], color[2], color[3])
		-- The pizza slices are the targets: no rings or glows around the names.
		local pizza = self.key == "party"
		slot.halo:SetShown(not pizza)
		slot.ping:SetShown(not pizza)
		STYLES[style](slot, color)
		if self.key == "party" then
			slot.rim:Hide()
			slot.border:Hide()
			slot.glow:Hide()
			slot.cooldown:Hide()
		else
			slot.glow:Show()
		end
		slot:Show()
	end
	for i = n + 1, #self.slots do
		self.slots[i]:Hide()
	end
	for i, slice in ipairs(self.slices) do
		self.slots[i].keyLabel:SetText(ns.ShortKey(slice.bind) or "")
	end
	self:LayoutWedges()
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
		if self.key == "party" then
			slot.cooldown:Hide() -- the slices are people, not spells
		elseif start and Plain(start) and Plain(duration) then
			slot.cooldown:Show()
			slot.cooldown:SetCooldown(start, duration)
		elseif not start then
			slot.cooldown:Clear()
		end
		-- Secret cooldowns: keep showing whatever was there before combat.
		local usable, noPower = Usable(slice)
		if not (Plain(usable) and Plain(noPower)) then
			usable, noPower = nil, nil
		end
		if noPower then
			slot.icon:SetVertexColor(0.45, 0.55, 1)
		elseif usable == false then
			slot.icon:SetVertexColor(0.4, 0.4, 0.4)
		else
			slot.icon:SetVertexColor(1, 1, 1)
		end
	end
end

-- Which Hover cast layer is held: "l-" (L2), "r-" (R2) or "".
local EMULATED = { ALT = "GamePadEmulateAlt", CTRL = "GamePadEmulateCtrl", SHIFT = "GamePadEmulateShift" }
local MOD_DOWN = { ALT = "IsAltKeyDown", CTRL = "IsControlKeyDown", SHIFT = "IsShiftKeyDown" }

function Display:HoverLayer()
	if self.header:GetAttribute("layer-l") then
		return "l-"
	elseif self.header:GetAttribute("layer-r") then
		return "r-"
	end
	for mod, cvar in pairs(EMULATED) do
		local down = _G[MOD_DOWN[mod]]
		if down and down() and GetCVar then
			local button = GetCVar(cvar)
			if button == "PADLTRIGGER" then
				return "l-"
			elseif button == "PADRTRIGGER" then
				return "r-"
			end
		end
	end
	return ""
end

function Display:UpdateHint()
	local header = self.header
	local depth = header:GetAttribute("depth") or 0
	local parts = { "A / click select", depth > 0 and "B / right-click back" or "B / right-click close" }
	-- Hover cast: the spells of the layer you're on (L2 / R2 held or not).
	if self.key == "party" and ForeverRingsDB.partyHeals == "hover" then
		local layer = self:HoverLayer()
		parts = { layer == "l-" and "L2:" or layer == "r-" and "R2:" or nil }
		local bar = ns.HoverBarSlots()
		for _, face in ipairs({ "a", "b", "x", "y" }) do
			local spell = ForeverRingsDB.partyHover[layer .. face]
			local name = spell and C_Spell.GetSpellName(spell) or (bar[layer .. face] and ns.ActionName(bar[layer .. face]))
			if name then
				parts[#parts + 1] = face:upper() .. " " .. name
			end
		end
		if layer == "" then
			parts[#parts + 1] = "L2 / R2 more"
		end
		parts[#parts + 1] = "ring button: close"
		self.hint:SetText(table.concat(parts, "  ·  "))
		self.hintLayer = layer
		return
	end
	-- Party ring with a spell per button: say which button heals with what.
	if self.key == "party" and ForeverRingsDB.partyHeals == "buttons" then
		parts = {}
		for index, label in ipairs({ "Release", "A", "X", "Y" }) do
			local spell = ns.PartySpell(index)
			if spell then
				parts[#parts + 1] = label .. " " .. (C_Spell.GetSpellName(spell) or "?")
			end
		end
		parts[#parts + 1] = "B close"
	end
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
			local x, y = cx / scale - header:GetLeft(), cy / scale - header:GetBottom()
			local mvx, mvy = x - mx0, y - my0
			if mvx * mvx + mvy * mvy >= ns.MOVE_ZONE * ns.MOVE_ZONE then
				local ex, ey = x - header:GetWidth() / 2, y - header:GetHeight() / 2
				if ex * ex + ey * ey >= ns.DEAD_ZONE * ns.DEAD_ZONE then
					dx, dy = ex, ey
				end
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

-- Health bars, death and range for the Party ring, every frame. Returns the
-- slot of whoever is lowest (below 80%), when the client lets us know that.
function Display:UpdateGroup()
	local lowest, lowestFraction
	for i, slice in ipairs(self.slices) do
		local unit, slot = slice.unit, self.slots[i]
		if unit then
			local health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
			local okDead, dead = pcall(function() return UnitIsDeadOrGhost(unit) == true end)
			dead = okDead and dead
			slot.icon:SetDesaturated(dead)
			local fraction = type(health) == "number" and Plain(health) and Plain(maxHealth) and maxHealth > 0 and health / maxHealth or nil
			local r, g, b
			if dead then
				r, g, b = 0.35, 0.35, 0.35
			elseif fraction then
				r, g, b = 1 - fraction, 0.3 + 0.6 * fraction, 0.15
				if fraction < 0.8 and (not lowestFraction or fraction < lowestFraction) then
					lowest, lowestFraction = i, fraction
				end
			else
				r, g, b = ns.ClassColor(unit)
			end
			local value, scale = self:HealthFraction(unit, health, maxHealth)
			for _, band in ipairs(slot.bands or {}) do
				if scale ~= 1 then
					band:SetMinMaxValues(band.step * scale, (band.step + RING_RANGE) * scale)
				end
				band:SetValue(dead and 0 or value)
				band:SetStatusBarColor(r, g, b)
			end
			-- UnitInRange can't tell for yourself or when it couldn't check.
			local okRange, outOfRange = pcall(function()
				local inRange, checked = UnitInRange(unit)
				return checked == true and inRange == false
			end)
			slot.outOfRange = okRange and outOfRange
		else
			slot.outOfRange = nil
		end
	end
	return lowest
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
	local rest = ForeverRingsDB.opacity or 1
	self.backdrop:SetAlpha(rest)
	self.track:SetAlpha(rest)
	self.backdrop:SetSize(OUTER_SIZE * (1.15 + 0.25 * open), OUTER_SIZE * (1.15 + 0.25 * open))
	self.track:SetRotation(math.rad(-50 * (1 - open)))
	self.track:SetSize(TRACK_SIZE * (0.85 + 0.15 * open), TRACK_SIZE * (0.85 + 0.15 * open))

	if self.key == "party" and ForeverRingsDB.partyHeals == "hover" and self:HoverLayer() ~= self.hintLayer then
		self:UpdateHint()
	end
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
	local lowest = self:UpdateGroup()
	if self.key == "party" then
		self.auraAge = (self.auraAge or AURA_INTERVAL) + elapsed
		if self.auraAge >= AURA_INTERVAL then
			self.auraAge = 0
			self:UpdateDebuffs()
		end
	end
	for i = 1, #self.slices do
		local slot = self.slots[i]
		local on = i == selected
		-- Slots pop out from the centre one after another.
		local p = EaseOutBack((self.openAge - (i - 1) * STAGGER) / OPEN_TIME)
		PlaceOnCircle(slot, self.frame, slot.angle, RADIUS * (0.5 + 0.5 * p))
		slot.scale = Approach(slot.scale, on and SELECT_SCALE or 1, elapsed, 14)
		slot:SetScale(math.max(0.01, slot.scale * (0.5 + 0.5 * p)))
		-- With something selected, the rest steps back a little; group members
		-- out of range fade further.
		slot:SetAlpha(Clamp(p) * ((selected and not on) and 0.65 or 1) * (slot.outOfRange and 0.45 or 1) * (on and 1 or rest))
		-- Party: the aimed slice lights up, the others step back.
		local w = self.key == "party" and self.wedges and self.wedges[i]
		if w then
			local alpha = Clamp(p) * ((selected and not on) and 0.6 or 1) * (slot.outOfRange and 0.45 or 1) * (on and 1 or rest)
			for _, band in ipairs(w.bands) do
				band:SetAlpha(alpha)
			end
			w.bg:SetAlpha(alpha)
			if on then
				w.bg:SetVertexColor(color[1] * 0.35, color[2] * 0.35, color[3] * 0.35, 0.95)
			elseif i == lowest then
				-- Whoever needs healing most: the slice pulses red.
				local red = 0.25 + 0.2 * math.sin(self.time * 6)
				w.bg:SetVertexColor(red, 0.04, 0.05, 0.95)
			else
				w.bg:SetVertexColor(0.05, 0.06, 0.09, 0.92)
			end
		end
		slot.halo:SetAlpha(on and pulse or 0)
		slot.glow:SetAlpha(not clean and on and pulse or 0)
		if self.key == "party" then
			-- Party: the circle only shows your HoT is on them.
			slot.rim:SetVertexColor(0.35, 1, 0.5)
			slot.rim:SetAlpha(0.9)
		elseif on then
			slot.rim:SetVertexColor(color[1], color[2], color[3])
			slot.rim:SetAlpha(1)
		elseif i == lowest then
			-- Whoever needs healing most pulses red.
			slot.rim:SetVertexColor(1, 0.2, 0.2)
			slot.rim:SetAlpha(0.6 + 0.4 * math.sin(self.time * 6))
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
		self.trackLight:SetAlpha((0.35 + 0.15 * math.sin(self.time * 2)) * rest)
		self.centerGlow:SetAlpha(0.15 * rest)
	end
	PlaceOnCircle(self.trackLight, self.frame, self.lightAngle, TRACK_RADIUS)

	if #self.slices == 0 then
		self.title:SetText(ns.RingLabel(self.key) .. "\n|cff999999(empty)|r")
	elseif selected then
		local slice = self.slices[selected]
		if slice.unit then
			-- Who, in class colour, and what lands on them.
			local r, g, b = ns.ClassColor(slice.unit)
			local action = slice.type == "spell" and C_Spell.GetSpellName(slice.value) or "Target"
			self.title:SetText(("|cff%02x%02x%02x%s|r\n|cff999999%s|r"):format(r * 255, g * 255, b * 255, slice.name or "", action or ""))
		else
			self.title:SetText(slice.name or "")
		end
	else
		local auto = ns.autoRings[self.key]
		local center = auto and auto.center
		self.title:SetText(ns.RingLabel(self.key) .. (center and ("\n|cff999999Middle: " .. center.name .. "|r") or ""))
	end
end
