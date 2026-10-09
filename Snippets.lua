local _, ns = ...

-- Secure snippets for the restricted environment. Everything that decides
-- what a ring does lives here, so rings keep working in combat.
--
-- Header attributes (set out of combat by Core.lua):
--   r:<ring>:n          number of slices
--   r:<ring>:t<i>       "item" | "toy" | "spell" | "macro" | "ring"
--   r:<ring>:v<i>       action value, or the sub-ring key for "ring"
--   key-up/right/down/left, key-confirm, key-back   gamepad keys
--   tap-repeat          tapping a ring button repeats its last action
-- Runtime state:
--   active, sticky, depth, stack<d>, held-<dir>, moved, mx0/my0
--   last:<ring>:t / last:<ring>:v   last action used from each ring

ns.DEAD_ZONE = 40

-- Expects local `openKey`. Shows the ring and grabs the direction/confirm/back keys.
local OPEN = [[
	owner:SetAttribute("active", openKey)
	local mx, my = owner:GetMousePosition()
	owner:SetAttribute("mx0", mx and mx * owner:GetWidth())
	owner:SetAttribute("my0", my and my * owner:GetHeight())
	if not owner:IsShown() then
		owner:Show()
		owner:SetBindingClick(true, owner:GetAttribute("key-up"), "ForeverRingsDir_up")
		owner:SetBindingClick(true, owner:GetAttribute("key-right"), "ForeverRingsDir_right")
		owner:SetBindingClick(true, owner:GetAttribute("key-down"), "ForeverRingsDir_down")
		owner:SetBindingClick(true, owner:GetAttribute("key-left"), "ForeverRingsDir_left")
		owner:SetBindingClick(true, owner:GetAttribute("key-confirm"), "ForeverRingsConfirm")
		owner:SetBindingClick(true, owner:GetAttribute("key-back"), "ForeverRingsBack")
	end
]]

local CLOSE = [[
	owner:ClearBindings()
	owner:Hide()
	owner:SetAttribute("active", nil)
	owner:SetAttribute("sticky", nil)
	owner:SetAttribute("depth", 0)
	owner:SetAttribute("held-up", nil)
	owner:SetAttribute("held-right", nil)
	owner:SetAttribute("held-down", nil)
	owner:SetAttribute("held-left", nil)
	owner:SetAttribute("moved", nil)
]]

-- Expects `kind` and `value`. Loads the action into self; the secure click
-- that follows performs it. Macros keep their text in "macrotext".
local FIRE = [[
	self:SetAttribute("type", kind)
	self:SetAttribute("typerelease", kind)
	self:SetAttribute(kind == "macro" and "macrotext" or kind, value)
]]

-- Sets locals `key` and `pick`. The stick direction wins; otherwise the mouse
-- movement since the ring opened is used, so keyboard players can aim too.
local PICK = ([[
	local pick
	local key = owner:GetAttribute("active")
	local n = key and owner:GetAttribute("r:" .. key .. ":n") or 0
	local dx, dy = 0, 0
	if owner:GetAttribute("held-right") then dx = dx + 1 end
	if owner:GetAttribute("held-left") then dx = dx - 1 end
	if owner:GetAttribute("held-up") then dy = dy + 1 end
	if owner:GetAttribute("held-down") then dy = dy - 1 end
	if dx == 0 and dy == 0 then
		local mx, my = owner:GetMousePosition()
		local mx0, my0 = owner:GetAttribute("mx0"), owner:GetAttribute("my0")
		if mx and mx0 then
			local ex, ey = mx * owner:GetWidth() - mx0, my * owner:GetHeight() - my0
			if ex * ex + ey * ey >= %d then
				dx, dy = ex, ey
			end
		end
	end
	if n > 0 and (dx ~= 0 or dy ~= 0) then
		local step = 360 / n
		local angle = math.deg(math.atan2(dx, dy)) %% 360
		pick = math.floor((angle + step / 2) / step) %% n + 1
	end
]]):format(ns.DEAD_ZONE * ns.DEAD_ZONE)

-- Expects `key`, `pick`, `closeIfNothing`. Enters a sub-ring, or fires the
-- action and remembers it as the last one used from the ring that was opened.
local ACT = [[
	if not pick then
		if closeIfNothing then
]] .. CLOSE .. [[
		end
		return false
	end
	local kind = owner:GetAttribute("r:" .. key .. ":t" .. pick)
	local value = owner:GetAttribute("r:" .. key .. ":v" .. pick)
	if kind == "ring" then
		local depth = (owner:GetAttribute("depth") or 0) + 1
		owner:SetAttribute("depth", depth)
		owner:SetAttribute("stack" .. depth, key)
		owner:SetAttribute("sticky", true)
		local openKey = value
]] .. OPEN .. [[
		return false
	end
	local depth = owner:GetAttribute("depth") or 0
	local root = depth > 0 and owner:GetAttribute("stack1") or key
]] .. CLOSE .. [[
	if not kind then
		return false
	end
	owner:SetAttribute("last:" .. root .. ":t", kind)
	owner:SetAttribute("last:" .. root .. ":v", value)
]] .. FIRE

ns.snippets = {
	-- Ring button: press opens the ring, release picks. A quick tap without
	-- touching the stick repeats the last action from this ring.
	trigger = [[
	if down then
		if not owner:IsShown() then
			owner:SetAttribute("depth", 0)
			local openKey = self:GetAttribute("ring")
]] .. OPEN .. [[
		end
		return false
	end
	if not owner:IsShown() then
		return false
	end
	local closeIfNothing = true
]] .. PICK .. [[
	if not pick and owner:GetAttribute("tap-repeat") and not owner:GetAttribute("sticky") and not owner:GetAttribute("moved") then
		local kind = owner:GetAttribute("last:" .. key .. ":t")
		local value = owner:GetAttribute("last:" .. key .. ":v")
		if kind then
]] .. CLOSE .. FIRE .. [[
			return
		end
	end
]] .. ACT,

	-- A: pick without closing when nothing is selected.
	confirm = [[
	if not down or not owner:IsShown() then
		return false
	end
	local closeIfNothing = false
]] .. PICK .. ACT,

	-- B: one sub-ring back, or close.
	back = [[
	if not down then
		return false
	end
	local depth = owner:GetAttribute("depth") or 0
	if depth > 0 then
		local openKey = owner:GetAttribute("stack" .. depth)
		owner:SetAttribute("depth", depth - 1)
]] .. OPEN .. [[
	else
]] .. CLOSE .. [[
	end
	return false
]],

	-- Stick/D-pad directions: diagonals are two held directions at once.
	direction = [[
	owner:SetAttribute("held-" .. self:GetAttribute("dir"), down or nil)
	if down then
		owner:SetAttribute("moved", true)
	end
	return false
]],
}
