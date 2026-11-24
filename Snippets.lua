local _, ns = ...

-- Secure snippets for the restricted environment. Everything that decides
-- what a ring does lives here, so rings keep working in combat.
--
-- Header attributes (set out of combat by Core.lua):
--   r:<ring>:n          number of slices
--   r:<ring>:t<i>       "item" | "toy" | "spell" | "macro" | "ring"
--   r:<ring>:v<i>       action value, or the sub-ring key for "ring"
--   r:<ring>:u<i>       unit the action is used on (Party ring: party2...)
--   r:<ring>:btn-a/x/y  spell for that face button, cast on the aimed unit
--                       (Party ring with "spell per button")
--   r:<ring>:hover      Hover cast: aim, then A/B/X/Y (or L2/R2 + them) each
--                       cast their spell (btn-a, btn-l-a, btn-r-a...) and the
--                       ring stays open; the ring button closes it
--   r:<ring>:btnk-<id>  "action" when btn-<id> is an action bar slot, not a spell
--   r:<ring>:k<i>       optional key that picks slot i while the ring is open
--   r:<ring>:keys       the ring has slot keys: a tap opens it and it stays open
--   r:<ring>:roll       shown as a rollout (a column) instead of a ring:
--                       the stick steps up/down through it (sel)
--   r:<ring>:rx/ry/rstep/rdir   rollout geometry in header units: centre of
--                       the first item, distance between items, +1 up / -1 down
--   modlayer-<MODS>     "l" or "r": which trigger the client turns into that
--                       modifier (GamePadEmulate*), e.g. modlayer-ALT- = "l"
--   key-up/right/down/left, key-confirm, key-back   gamepad keys
--   tap-repeat          tapping a ring button repeats its last action
--   release-pick        letting go of the stick picks what it pointed at
-- Runtime state:
--   active, sticky, depth, stack<d>, held-<dir>, moved, mx0/my0
--   aim-dx/aim-dy       last stick direction, kept after the stick is let go
--   held                the ring button is down (not set by an action bar click)
--   layer-l / layer-r   L2 / R2 held (when they're plain buttons)
--   sel                 selected item of an open rollout
--   last:<ring>:t / :v / :u   last action used from each ring

ns.DEAD_ZONE = 40
ns.MOVE_ZONE = 8

-- The direction/confirm/back keys, also with a modifier held: a pad button
-- set as Ctrl (R2 by default) turns PADRSTICKUP into CTRL-PADRSTICKUP, which
-- would otherwise miss the ring and leave the stick dead.
local GRAB = {}
for _, mod in ipairs({ "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-" }) do
	for _, key in ipairs({
		{ "key-up", "ForeverRingsDir_up" }, { "key-right", "ForeverRingsDir_right" },
		{ "key-down", "ForeverRingsDir_down" }, { "key-left", "ForeverRingsDir_left" },
		{ "key-confirm", "ForeverRingsConfirm" }, { "key-back", "ForeverRingsBack" },
		{ "key-x", "ForeverRingsButtonX" }, { "key-y", "ForeverRingsButtonY" },
	}) do
		-- The modifier travels along as the click's button ("mod-ALT-"), so
		-- Hover cast can tell L2 + A from A.
		GRAB[#GRAB + 1] = ('		owner:SetBindingClick(true, "%s" .. owner:GetAttribute("%s"), "%s", "%s")')
			:format(mod, key[1], key[2], mod == "" and "LeftButton" or ("mod-" .. mod))
	end
end
-- L2 / R2 as plain buttons: held state for Hover cast.
GRAB[#GRAB + 1] = '		owner:SetBindingClick(true, "PADLTRIGGER", "ForeverRingsLayer_l")'
GRAB[#GRAB + 1] = '		owner:SetBindingClick(true, "PADRTRIGGER", "ForeverRingsLayer_r")'

-- Expects local `openKey`. Shows the ring and grabs the direction/confirm/back
-- keys, then the ring's own slot keys (they win over the others, so a slot can
-- be on B or on the ring's own button). Grabbed again for every ring, so a
-- sub-ring has its own slot keys.
local OPEN = [[
	owner:SetAttribute("active", openKey)
	if not owner:IsShown() then
		owner:Show()
	end
	owner:ClearBindings()
]] .. table.concat(GRAB, "\n") .. [[

	for i = 1, owner:GetAttribute("r:" .. openKey .. ":n") or 0 do
		local slotKey = owner:GetAttribute("r:" .. openKey .. ":k" .. i)
		if slotKey then
			owner:SetBindingClick(true, slotKey, "ForeverRingsSlot" .. i)
		end
	end
	owner:SetAttribute("sel", nil)
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
	owner:SetAttribute("layer-l", nil)
	owner:SetAttribute("layer-r", nil)
	owner:SetAttribute("sel", nil)
]]

-- Expects `kind`, `value` and `unit` (may be nil). Loads the action into self; the secure click
-- that follows performs it. Macros keep their text in "macrotext".
-- No macros for the addon's own actions: a macro can't start another macro,
-- so they'd do nothing from an action bar button. And Blizzard panels and
-- raid marks must be done by secure code, or the client blames the addon.
--   click       clicks a game button (micro menu), value = "menu:<id>"
--   raidtarget  sets (toggles) or clears a raid mark on the target
--   run         the addon's own things (its settings screen, bags...), insecure
local FIRE = [[
	self:SetAttribute("unit", nil)
	if kind == "run" then
		-- Cancel the click itself: newer clients error on a secure click that
		-- has nothing to do.
		owner:SetAttribute("run", nil)
		owner:SetAttribute("run", value)
		return false
	elseif kind == "click" then
		-- Secure code can't hand over a button, only its name: every ring
		-- button has "clickbutton-<value>" set to the micro menu button, and
		-- returning value as the mouse button makes the click use that one.
		self:SetAttribute("type", "click")
		self:SetAttribute("typerelease", "click")
		return value
	elseif kind == "raidtarget" then
		self:SetAttribute("type", "raidtarget")
		self:SetAttribute("typerelease", "raidtarget")
		self:SetAttribute("unit", "target")
		self:SetAttribute("marker", value)
		self:SetAttribute("action", value == 0 and "clear" or "toggle")
	else
		self:SetAttribute("type", kind)
		self:SetAttribute("typerelease", kind)
		self:SetAttribute(kind == "macro" and "macrotext" or kind, value)
	end
	-- Cast on (or target) a group member without changing your target first.
	if unit then
		self:SetAttribute("unit", unit)
	end
]]

-- Sets locals `key` and `pick`. The stick direction wins, then the last one it
-- pointed at (so letting go keeps the selection). Otherwise, once the mouse
-- has moved, its direction from the middle of the ring (the screen centre)
-- is used, wherever the mouse was when the ring opened.
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
			local w, h = owner:GetWidth(), owner:GetHeight()
			local mvx, mvy = mx * w - mx0, my * h - my0
			if mvx * mvx + mvy * mvy >= %d then
				local ex, ey = mx * w - w / 2, my * h - h / 2
				if ex * ex + ey * ey >= %d then
					dx, dy = ex, ey
				end
			end
		end
	end
	if n > 0 and (dx ~= 0 or dy ~= 0) then
		local step = 360 / n
		local angle = math.deg(math.atan2(dx, dy)) %% 360
		pick = math.floor((angle + step / 2) / step) %% n + 1
	end
	-- A rollout: what the stick stepped to, or the item under a moved mouse.
	if key and owner:GetAttribute("r:" .. key .. ":roll") then
		pick = owner:GetAttribute("sel")
		local mx, my = owner:GetMousePosition()
		local mx0, my0 = owner:GetAttribute("mx0"), owner:GetAttribute("my0")
		local rx, ry = owner:GetAttribute("r:" .. key .. ":rx"), owner:GetAttribute("r:" .. key .. ":ry")
		local rstep, rdir = owner:GetAttribute("r:" .. key .. ":rstep"), owner:GetAttribute("r:" .. key .. ":rdir") or 1
		if mx and mx0 and rx and rstep then
			local w, h = owner:GetWidth(), owner:GetHeight()
			local mvx, mvy = mx * w - mx0, my * h - my0
			if mvx * mvx + mvy * mvy >= %d and math.abs(mx * w - rx) <= rstep / 2 then
				local i = math.floor((my * h - ry) * rdir / rstep + 0.5) + 1
				if i >= 1 and i <= n then
					pick = i
				end
			end
		end
		if pick and (pick < 1 or pick > n) then
			pick = nil
		end
	end
]]):format(ns.MOVE_ZONE * ns.MOVE_ZONE, ns.DEAD_ZONE * ns.DEAD_ZONE, ns.MOVE_ZONE * ns.MOVE_ZONE)

-- Expects `key`, `pick`, `closeIfNothing` and `useButton` ("a", "x", "y" or
-- nil). Enters a sub-ring, or fires the
-- action and remembers it as the last one used from the ring that was opened.
-- A ring can have an action in its middle (Markers: clear): used when nothing
-- is aimed at.
local ACT = [[
	if not pick and owner:GetAttribute("r:" .. key .. ":ct") then
		local kind = owner:GetAttribute("r:" .. key .. ":ct")
		local value = owner:GetAttribute("r:" .. key .. ":cv")
		local unit = nil
]] .. CLOSE .. FIRE .. [[
		return
	end
	if not pick then
		if closeIfNothing then
]] .. CLOSE .. [[
		end
		return false
	end
	local kind = owner:GetAttribute("r:" .. key .. ":t" .. pick)
	local value = owner:GetAttribute("r:" .. key .. ":v" .. pick)
	local unit = owner:GetAttribute("r:" .. key .. ":u" .. pick)
	-- A face button with its own spell casts that on the aimed person instead.
	local buttonSpell = useButton and unit and owner:GetAttribute("r:" .. key .. ":btn-" .. useButton)
	local hover = owner:GetAttribute("r:" .. key .. ":hover")
	if hover and not buttonSpell then
		return false
	end
	if buttonSpell then
		-- "action": what's on that action bar button (Hover cast without an
		-- own spell), cast on the aimed person.
		kind, value = owner:GetAttribute("r:" .. key .. ":btnk-" .. useButton) or "spell", buttonSpell
	end
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
	-- Hover cast stays open after a heal with "Toggle" and "Hold"; with "Tap"
	-- a heal closes it.
	if not (hover and owner:GetAttribute("r:" .. key .. ":staysopen")) then
]] .. CLOSE .. [[
	end
	if not kind then
		return false
	end
	if value ~= "settings" then
		owner:SetAttribute("last:" .. root .. ":t", kind)
		owner:SetAttribute("last:" .. root .. ":u", unit)
		owner:SetAttribute("last:" .. root .. ":v", value)
	end
]] .. FIRE

-- Hover cast: sets local `hover` for the open ring and, when it's on, turns
-- `useButton` ("a") into its layer's id ("l-a" with L2, "r-a" with R2).
local LAYER = [[
	local hover = owner:GetAttribute("r:" .. (owner:GetAttribute("active") or "") .. ":hover")
	if hover and useButton then
		local layer = ""
		if owner:GetAttribute("layer-l") then
			layer = "l-"
		elseif owner:GetAttribute("layer-r") then
			layer = "r-"
		end
		if button and strsub(button, 1, 4) == "mod-" then
			local fromMod = owner:GetAttribute("modlayer-" .. strsub(button, 5))
			if fromMod then
				layer = fromMod .. "-"
			end
		end
		useButton = layer .. useButton
	end
]]

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
		if owner:GetAttribute("r:" .. (owner:GetAttribute("active") or "") .. ":hover") then
]] .. CLOSE .. [[
			return false
		end
]] .. PICK .. ACT .. [[
		return
	end
	if not owner:IsShown() or not owner:GetAttribute("held") then
		return false
	end
	owner:SetAttribute("held", nil)
	self:SetAttribute("useOnKeyDown", false)
	if owner:GetAttribute("r:" .. (owner:GetAttribute("active") or "") .. ":hover") then
		-- Hover cast: letting go keeps it open, unless it's set to "hold".
		if owner:GetAttribute("r:" .. (owner:GetAttribute("active") or "") .. ":holdclose") then
]] .. CLOSE .. [[
		end
		return false
	end
]] .. PICK .. [[
	-- Rings with slot keys and rollouts stay open after a tap: press a slot's
	-- key, or aim and press again. Holding, aiming and letting go still picks.
	if not pick and not owner:GetAttribute("moved")
		and (owner:GetAttribute("r:" .. key .. ":keys") or owner:GetAttribute("r:" .. key .. ":roll")) then
		owner:SetAttribute("sticky", true)
		return false
	end
	if not pick and owner:GetAttribute("tap-repeat") and not owner:GetAttribute("sticky") and not owner:GetAttribute("moved")
		and not owner:GetAttribute("r:" .. key .. ":ct") then
		local kind = owner:GetAttribute("last:" .. key .. ":t")
		local value = owner:GetAttribute("last:" .. key .. ":v")
		local unit = owner:GetAttribute("last:" .. key .. ":u")
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
	local useButton = "a"
]] .. LAYER .. PICK .. ACT,

	-- X / Y: only do something on rings that give them a spell (Party ring
	-- with "spell per button"): cast it on whoever is aimed at.
	buttonx = [[
	if not down or not owner:IsShown() then
		return false
	end
	local closeIfNothing = false
	local useButton = "x"
]] .. LAYER .. PICK .. [[
	if not pick or not owner:GetAttribute("r:" .. key .. ":btn-" .. useButton) then
		return false
	end
]] .. ACT,

	buttony = [[
	if not down or not owner:IsShown() then
		return false
	end
	local closeIfNothing = false
	local useButton = "y"
]] .. LAYER .. PICK .. [[
	if not pick or not owner:GetAttribute("r:" .. key .. ":btn-" .. useButton) then
		return false
	end
]] .. ACT,

	-- B: one sub-ring back, or close.
	back = [[
	if not down then
		return false
	end
	local closeIfNothing = false
	local useButton = "b"
]] .. LAYER .. [[
	if hover then
]] .. PICK .. [[
		if pick and owner:GetAttribute("r:" .. key .. ":btn-" .. useButton) then
]] .. ACT .. [[
			return
		end
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
	local useButton = owner:GetAttribute("r:" .. (owner:GetAttribute("active") or "") .. ":hover") and "a" or nil
]] .. PICK .. ACT,

	-- A slot's own key while its ring is open: use that slot.
	slot = [[
	if not down or not owner:IsShown() then
		return false
	end
	local key = owner:GetAttribute("active")
	local pick = self:GetAttribute("slot")
	if not key or pick > (owner:GetAttribute("r:" .. key .. ":n") or 0) then
		return false
	end
	local closeIfNothing = false
	local useButton = nil
]] .. ACT,

	-- L2 / R2 held (plain buttons): which Hover cast layer A/B/X/Y use.
	layer = [[
	owner:SetAttribute("layer-" .. self:GetAttribute("layer"), down or nil)
	return false
]],

	-- Stick/D-pad directions: diagonals are two held directions at once.
	-- With release-pick on, letting go of the last held direction picks.
	direction = [[
	owner:SetAttribute("held-" .. self:GetAttribute("dir"), down or nil)
	-- A rollout: up and down step through the column; nothing picks on release.
	local rollKey = owner:GetAttribute("active")
	if rollKey and owner:GetAttribute("r:" .. rollKey .. ":roll") then
		local dir = self:GetAttribute("dir")
		local n = owner:GetAttribute("r:" .. rollKey .. ":n") or 0
		if down and n > 0 and (dir == "up" or dir == "down") then
			local step = (dir == "up") and 1 or -1
			step = step * (owner:GetAttribute("r:" .. rollKey .. ":rdir") or 1)
			local sel = owner:GetAttribute("sel")
			if not sel then
				sel = step > 0 and 1 or n
			else
				sel = sel + step
			end
			if sel < 1 then sel = 1 end
			if sel > n then sel = n end
			owner:SetAttribute("sel", sel)
			owner:SetAttribute("moved", true)
		end
		return false
	end
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
	if not owner:IsShown() or not owner:GetAttribute("release-pick")
		or owner:GetAttribute("r:" .. (owner:GetAttribute("active") or "") .. ":hover") then
		return false
	end
	if owner:GetAttribute("held-up") or owner:GetAttribute("held-right")
		or owner:GetAttribute("held-down") or owner:GetAttribute("held-left") then
		return false
	end
	local closeIfNothing = false
]] .. PICK .. [[
	-- Only an aimed slot: never the ring's middle action.
	if not pick then
		return false
	end
]] .. ACT,
}
