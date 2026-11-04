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
--   release-pick        letting go of the stick picks what it pointed at
-- Runtime state:
--   active, sticky, depth, stack<d>, held-<dir>, moved, mx0/my0
--   aim-dx/aim-dy       last stick direction, kept after the stick is let go
--   held                the ring button is down (not set by an action bar click)
--   last:<ring>:t / last:<ring>:v   last action used from each ring

ns.DEAD_ZONE = 40

-- Expects local `openKey`. Shows the ring and grabs the direction/confirm/back keys.
local OPEN = [[
	owner:SetAttribute("active", openKey)
	if not owner:IsShown() then
		owner:Show()
		owner:SetBindingClick(true, owner:GetAttribute("key-up"), "ForeverRingsDir_up")
		owner:SetBindingClick(true, owner:GetAttribute("key-right"), "ForeverRingsDir_right")
		owner:SetBindingClick(true, owner:GetAttribute("key-down"), "ForeverRingsDir_down")
		owner:SetBindingClick(true, owner:GetAttribute("key-left"), "ForeverRingsDir_left")
		owner:SetBindingClick(true, owner:GetAttribute("key-confirm"), "ForeverRingsConfirm")
		owner:SetBindingClick(true, owner:GetAttribute("key-back"), "ForeverRingsBack")
	end
	owner:SetAttribute("aim-dx", nil)
	owner:SetAttribute("aim-dy", nil)
	-- Read the mouse once shown: a hidden frame has no mouse position.
	local mx, my = owner:GetMousePosition()
	owner:SetAttribute("mx0", mx and mx * owner:GetWidth())
	owner:SetAttribute("my0", my and my * owner:GetHeight())
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
	owner:SetAttribute("held", nil)
	owner:SetAttribute("aim-dx", nil)
	owner:SetAttribute("aim-dy", nil)
]]

-- Expects `kind` and `value`. Loads the action into self; the secure click
-- that follows performs it. Macros keep their text in "macrotext".
local FIRE = [[
	self:SetAttribute("type", kind)
	self:SetAttribute("typerelease", kind)
	self:SetAttribute(kind == "macro" and "macrotext" or kind, value)
]]

-- Sets locals `key` and `pick`. The stick direction wins, then the last one it
-- pointed at (so letting go keeps the selection); otherwise the mouse movement
-- since the ring opened is used, so keyboard players can aim too.
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
		dx, dy = owner:GetAttribute("aim-dx") or 0, owner:GetAttribute("aim-dy") or 0
	end
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
	if value ~= "/frings config" then
		owner:SetAttribute("last:" .. root .. ":t", kind)
		owner:SetAttribute("last:" .. root .. ":v", value)
	end
]] .. FIRE

-- B: one sub-ring back, or close.
local BACK = [[
	local depth = owner:GetAttribute("depth") or 0
	if depth > 0 then
		local openKey = owner:GetAttribute("stack" .. depth)
		owner:SetAttribute("depth", depth - 1)
]] .. OPEN .. [[
	else
]] .. CLOSE .. [[
	end
	return false
]]

ns.snippets = {
	-- Ring button: press opens the ring, release picks. A quick tap without
	-- touching the stick repeats the last action from this ring.
	-- A press while the ring is already open picks right away, so a one-click
	-- action bar button works too: click to open, aim, click again.
	trigger = [[
	local closeIfNothing = true
	if down then
		if not owner:IsShown() then
			owner:SetAttribute("depth", 0)
			local openKey = self:GetAttribute("ring")
]] .. OPEN .. [[
			owner:SetAttribute("held", true)
			return false
		end
		owner:SetAttribute("held", nil)
		self:SetAttribute("useOnKeyDown", true)
]] .. PICK .. ACT .. [[
		return
	end
	if not owner:IsShown() or not owner:GetAttribute("held") then
		return false
	end
	owner:SetAttribute("held", nil)
	self:SetAttribute("useOnKeyDown", false)
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
]] .. BACK,

	-- Mouse anywhere on screen while a ring is open: left click picks,
	-- right click goes back.
	mouse = [[
	if not down or not owner:IsShown() then
		return false
	end
	if button == "RightButton" then
]] .. BACK .. [[
	end
	local closeIfNothing = false
]] .. PICK .. ACT,

	-- Stick/D-pad directions: diagonals are two held directions at once.
	-- With release-pick on, letting go of the last held direction picks.
	direction = [[
	owner:SetAttribute("held-" .. self:GetAttribute("dir"), down or nil)
	-- Only presses change the aim: letting go (even one half of a diagonal
	-- first) keeps what was selected.
	if down then
		owner:SetAttribute("moved", true)
		local dx, dy = 0, 0
		if owner:GetAttribute("held-right") then dx = dx + 1 end
		if owner:GetAttribute("held-left") then dx = dx - 1 end
		if owner:GetAttribute("held-up") then dy = dy + 1 end
		if owner:GetAttribute("held-down") then dy = dy - 1 end
		owner:SetAttribute("aim-dx", dx)
		owner:SetAttribute("aim-dy", dy)
		return false
	end
	if not owner:IsShown() or not owner:GetAttribute("release-pick") then
		return false
	end
	if owner:GetAttribute("held-up") or owner:GetAttribute("held-right")
		or owner:GetAttribute("held-down") or owner:GetAttribute("held-left") then
		return false
	end
	local closeIfNothing = false
]] .. PICK .. ACT,
}
