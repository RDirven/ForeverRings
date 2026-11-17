-- Drives the settings screen with a (fake) gamepad.
-- Usage: luajit tests/config_test.lua   (from the repo root)

package.path = "tests/?.lua;" .. package.path
local WoW = require("wowmock")

local function World()
	return {
		items = {
			[101] = { name = "Roasted Boar", icon = 1001, class = 0, subclass = 5, ilvl = 10, count = 5, spell = 433 },
			[201] = { name = "Healing Potion", icon = 2001, class = 0, subclass = 1, ilvl = 20, spell = 441 },
			[301] = { name = "Toy Train", icon = 3001, class = 15, subclass = 0, ilvl = 1, spell = 902 },
		},
		bags = { [0] = { 101, 201 } },
		toys = { [301] = true },
		spells = {
			[3565] = { name = "Portal: Darnassus", icon = 4001 },
			[1459] = { name = "Arcane Intellect", icon = 4002 },
			[999] = { name = "Some Passive", icon = 4003, passive = true },
		},
		spellbook = { 3565, 1459, 999 },
		mounts = { { id = 1, name = "Swift Gryphon", spell = 458, icon = 5001, favorite = true } },
		macros = { { name = "Shout", icon = 7001, body = "/y For the Horde!" } },
	}
end

local function Open()
	local g = WoW.New(World()).Login()
	g.Slash("")
	return g, g.ns.configUI, g.ns.configState
end

-- A, B, X, Y, D-pad and shoulders by name.
local PAD = {
	A = "PAD1", B = "PAD2", X = "PAD3", Y = "PAD4",
	up = "PADDUP", down = "PADDDOWN", left = "PADDLEFT", right = "PADDRIGHT",
	LB = "PADLSHOULDER", RB = "PADRSHOULDER",
}
-- The screen reads the gamepad itself; other names are keyboard keys.
local function Pad(g, ...)
	for _, name in ipairs({ ... }) do
		local button = PAD[name] or name
		if button:match("^PAD") then
			g.GamePadButton(button)
		else
			g.KeyDown(button)
		end
	end
end

local passed, failed = 0, 0
local function Test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local function Eq(actual, expected, what)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function Has(text, part, what)
	if not (text and text:find(part, 1, true)) then
		error(("%s: '%s' not in '%s'"):format(what or "text", part, tostring(text)), 2)
	end
end

local function Lacks(text, part, what)
	if text and text:find(part, 1, true) then
		error(("%s: '%s' should not be in '%s'"):format(what or "text", part, tostring(text)), 2)
	end
end

local function RowText(ui, i)
	return ui.rows[i]:IsShown() and ui.rows[i].text:GetText() or nil
end

Test("/frings opens the screen and takes over the gamepad", function()
	local g, ui = Open()
	Eq(ui.frame:IsShown(), true, "shown")
	Eq(ui.frame.gamepad, true, "reads the gamepad itself")
	Has(RowText(ui, 1), "Main", "first row")
	Has(RowText(ui, 2), "Food", "second row")
	Has(RowText(ui, 10), "New ring", "last row (Party is the 7th ring)")
	Has(ui.hint:GetText(), "A edit", "hint")
	Lacks(ui.hint:GetText(), "X delete", "main can't be deleted")
end)

Test("B closes and gives the buttons back", function()
	local g, ui = Open()
	Pad(g, "B")
	Eq(ui.frame:IsShown(), false, "closed")
	Eq(next(ui.frame.overrides), nil, "overrides cleared")
end)

Test("auto rings are view-only", function()
	local g, ui, st = Open()
	Pad(g, "down")
	Has(ui.hint:GetText(), "A view", "food hint")
	Pad(g, "A")
	Eq(st.mode, "edit", "viewing")
	Has(ui.info:GetText(), "fills itself", "info")
	Pad(g, "A")
	Eq(st.mode, "edit", "A doesn't open a picker")
	Pad(g, "X")
	Eq(#g.ns.resolved.food, 1, "X doesn't remove anything")
	Pad(g, "B")
	Eq(st.mode, "list", "back to list")
end)

Test("create a ring and fill it with a spell, a toy and a bag item", function()
	local g, ui, st = Open()
	Pad(g, "up")
	Has(RowText(ui, st.ringIndex), "New ring", "wrapped to New ring")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.rings.ring1 ~= nil, true, "ring1 created")
	Eq(st.mode, "edit", "editing new ring")
	Eq(ui.slots[1].plus:IsShown(), true, "empty ring shows + slot")

	Pad(g, "A")
	Eq(st.mode, "pick", "picker")
	Eq(ui.categories[st.pickCategory].label:GetText(), "Bags", "starts on Bags")
	Pad(g, "RB")
	Has(RowText(ui, 1), "Arcane Intellect", "spells sorted")
	Eq(RowText(ui, 3), nil, "passive spell hidden")
	Pad(g, "A")
	Eq(st.mode, "edit", "back in editor")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].id, 1459, "spell saved")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:ring1:v1"), 1459, "pushed to secure ring")

	Pad(g, "right", "A")
	Eq(ui.categories[st.pickCategory].label:GetText(), "Spells", "picker remembers the last category")
	Pad(g, "RB", "RB")
	Eq(ui.categories[st.pickCategory].label:GetText(), "Toys", "RB to Toys")
	Pad(g, "A")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:ring1:t2"), "toy", "toy slot")

	Pad(g, "right", "A", "LB", "LB", "LB", "down", "A")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[3].id, 101, "second bag item (sorted: Healing Potion, Roasted Boar)")
end)

Test("replace and clear slots", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "A", "RB", "A")      -- new ring, slot 1 = Arcane Intellect
	Pad(g, "A", "down", "A")                -- replace slot 1 with Portal (still on Spells)
	local slots = g.env.ForeverRingsDB.rings.ring1.slots
	Eq(#slots, 1, "replaced, not added")
	Eq(slots[1].id, 3565, "portal")
	Pad(g, "X")
	Eq(#slots, 1, "first X only asks")
	Has(ui.hint:GetText(), "again to clear", "asks")
	Pad(g, "X")
	Eq(#slots, 0, "cleared")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:ring1:n"), 0, "secure ring empty")
end)

Test("put a ring inside Main", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "A", "RB", "A", "B")  -- create ring1 with a spell, back to list
	Pad(g, "down", "down")                  -- past "+ New ring", wrap to Main
	Eq(g.ns.configUI.ringKeys[st.ringIndex], "main", "on main")
	Pad(g, "A", "left")                     -- the + slot after 4 sub-rings
	Eq(st.slot, 8, "on + slot")
	Pad(g, "A", "LB", "LB")                 -- picker remembered Spells; LB twice wraps to Rings
	Eq(ui.categories[st.pickCategory].label:GetText(), "Rings", "rings category")
	for i = 1, 10 do
		if RowText(ui, i) == "Ring1" then
			for _ = 1, i - 1 do Pad(g, "down") end
		end
	end
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.rings.main.slots[8].ring, "ring1", "ring1 in main")
end)

Test("the ring itself is not offered as its own sub-ring", function()
	local g, ui = Open()
	Pad(g, "A", "left", "A", "LB")
	for i = 1, 10 do
		Lacks(RowText(ui, i), "Main", "row " .. i)
	end
end)

Test("ring buttons are priority overrides, so they beat Blizzard's gamepad bindings", function()
	local g = WoW.New(World()).Login()
	g.Slash("bind food PADLSTICK")
	local found
	for _, f in ipairs(g.frames) do
		local o = f.overrides.PADLSTICK
		if o and o.name == "ForeverRingsTrigger_food" then
			found = true
		end
	end
	Eq(found, true, "override set")
	Eq(g.env.ForeverRingsDB.binds.food, "PADLSTICK", "saved")
	g.Slash("bind mount PADLSTICK")
	Eq(g.env.ForeverRingsDB.binds.food, nil, "one ring per button")
end)

Test("drag a ring from the list to put it on the action bar", function()
	local g, ui, st = Open()
	ui.rows[2].scripts.OnDragStart(ui.rows[2])
	Eq(g.actions[1][1], "macro", "in the first free slot")
	Eq(ui.frame:IsShown(), true, "screen stays open")
end)

-- Row number of a ring in the list.
local function RowOf(ui, key)
	for i, row in ipairs(ui.rows) do
		if ui.ringKeys[ui.listOffset + i] == key then
			return row
		end
	end
end

local function Cell(row, n, button)
	row.cells[n].scripts.OnClick(row.cells[n], button or "LeftButton")
end

Test("every ring row has Edit, Set key, Clear, + and - buttons", function()
	local g, ui, st = Open()
	local main = RowOf(ui, "main")
	Eq(main.cells[1].shown, true, "buttons shown")
	Eq(main.cells[2].text, "Set key", "Set key")
	Eq(main.cells[3].enabled, false, "not on a bar yet: nothing to clear")
	Eq(main.cells[5].enabled, false, "Main can't be deleted")
	Eq(RowOf(ui, "food").cells[4].enabled, false, "auto rings take no +")

	Cell(RowOf(ui, "food"), 1)
	Eq(st.mode, "edit", "Edit opens the editor")
	Eq(g.ns.configUI.ringKeys[st.ringIndex], "food", "for that ring")
end)

Test("Set key: press an action bar button (L2 page included) and the ring goes there", function()
	local g, ui, st = Open()
	local main = RowOf(ui, "main")
	Cell(main, 2)
	Eq(st.capture, "bar", "waiting for an action button")
	Has(ui.capture:GetText(), "L2 + Triangle", "prompt")
	Eq(ui.frame.gamepad, false, "the game's own buttons work meanwhile")
	g.env.ActionButton4.action = 28        -- Triangle while L2 holds page 3
	g.env.ActionButtonDown(4)
	Eq(st.capture, nil, "done")
	Eq(g.actions[28] and g.actions[28][1], "macro", "ring in that slot")
	Has(st.message, "on that button", "told")
	Eq(g.ns.RingOnBar("main"), 28, "found again")
	Eq(ui.frame.gamepad, true, "menu reads the gamepad again")
	Eq(main.cells[3].enabled, true, "Clear on")

	Cell(main, 2)
	g.env.ActionButton1.action = 1
	g.env.ActionButtonDown(1)
	Eq(g.actions[1] and g.actions[1][1], "macro", "moved")
	Eq(g.actions[28], nil, "not twice")

	Cell(main, 3)
	Eq(g.actions[1], nil, "Clear takes it off the bar")
	Eq(g.ns.RingOnBar("main"), nil, "gone")
end)

Test("Set key: the ring is on the cursor; dropping it on a bar button finishes", function()
	local g, ui, st = Open()
	Cell(RowOf(ui, "main"), 2)
	Eq(g.cursorInfo and g.cursorInfo[1], "macro", "ring macro on the cursor")
	g.env.PlaceAction(40)                   -- the player clicks an action button
	g.Fire("ACTIONBAR_SLOT_CHANGED", 40)
	Eq(st.capture, nil, "done")
	Eq(g.ns.RingOnBar("main"), 40, "it's there")
	Has(st.message, "on that button", "told")
end)

Test("Set key on a taken button asks first; pressing it again replaces", function()
	local g, ui, st = Open()
	g.actions[2] = { "spell", 133 }
	g.env.ActionButton2.action = 2
	Cell(RowOf(ui, "main"), 2)
	g.env.ActionButtonDown(2)
	Eq(st.capture, "bar", "still waiting")
	Has(st.message, "Press it again to replace", "asked")
	g.env.ActionButtonDown(2)
	Eq(g.actions[2][1], "macro", "replaced")
end)

Test("Set key: right-click or 15 seconds cancel", function()
	local g, ui, st = Open()
	Cell(RowOf(ui, "main"), 2)
	ui.frame.scripts.OnMouseDown(ui.frame, "RightButton")
	Eq(st.capture, nil, "right-click cancels")
	Cell(RowOf(ui, "main"), 2)
	g.RunTimers()
	Eq(st.capture, nil, "timed out")
	Has(st.message, "cancelled", "told")
end)

Test("ring keys from older versions are removed once at login", function()
	local g = WoW.New(World())
	g.bindings.PAD4 = "CLICK ForeverRingsTrigger_main:LeftButton"
	g.Login()
	Eq(g.bindings.PAD4, nil, "PAD4 is the game's again")
	Eq(g.env.ForeverRingsDB.keysCleared, true, "only once")
end)
Test("row + adds to that ring, row - deletes it (twice)", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "B")                  -- create ring1
	local row = RowOf(ui, "ring1")
	Cell(row, 4)
	Eq(st.mode, "pick", "+ opens the picker")
	Pad(g, "A")
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 1, "added")
	Pad(g, "B")
	row = RowOf(ui, "ring1")
	Cell(row, 5)
	Eq(g.env.ForeverRingsDB.rings.ring1 ~= nil, true, "first click only asks")
	Has(row.cells[5].text, "?", "button asks")
	Cell(row, 5)
	Eq(g.env.ForeverRingsDB.rings.ring1, nil, "second click deletes")
end)

Test("editor toolbar: + adds a slot, - clears it, Back returns", function()
	local g, ui, st = Open()
	Pad(g, "up", "A")                       -- create ring1, in the editor
	Eq(ui.plus:IsShown(), true, "+ shown")
	ui.plus.scripts.OnClick(ui.plus)
	Pad(g, "A")
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 1, "slot added")
	ui.minus.scripts.OnClick(ui.minus)
	ui.minus.scripts.OnClick(ui.minus)
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 0, "slot cleared (asks first)")
	ui.back.scripts.OnClick(ui.back)
	Eq(st.mode, "list", "back to the list")
	Eq(ui.plus:IsShown(), false, "toolbar hidden in the list")
end)

Test("/frings unbind removes a ring's button", function()
	local g = WoW.New(World()).Login()
	g.Slash("bind food G")
	g.Slash("unbind food")
	Eq(g.ns.GetRingBinding("food"), nil, "unbound")
	g.Press("G", true)
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "G no longer opens it")
end)

Test("gamepad: Right walks the row's buttons, A presses", function()
	local g, ui, st = Open()
	Pad(g, "right")
	Eq(st.col, 1, "on Edit")
	Eq(RowOf(ui, "main").cells[1].highlight, true, "Edit lit")
	Has(ui.hint:GetText(), "A press", "hint")
	Pad(g, "right", "right")
	Eq(st.col, 4, "skips Clear (not on a bar), on +")
	Pad(g, "right")
	Eq(st.col, 4, "stops at +: Main can't be deleted")
	Pad(g, "left", "left", "left")
	Eq(st.col, nil, "left off the first button")
	Pad(g, "right", "B")
	Eq(st.col, nil, "B leaves the buttons")
	Eq(ui.frame:IsShown(), true, "without closing the screen")
	Pad(g, "right", "right", "A")
	Eq(st.capture, "bar", "A on Set key")
end)
Test("a ring on the D-pad doesn't steal it from the settings screen", function()
	local g = WoW.New(World()).Login()
	g.Slash("bind main PADDUP")
	g.Slash("")
	local st = g.ns.configState
	Pad(g, "down", "down", "up")
	Eq(st.ringIndex, 2, "D-pad up moved the list")
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "no ring opened")
	Pad(g, "B")
	g.Press("PADDUP", true)
	Eq(g.env.ForeverRingsHeader:IsShown(), true, "ring button back after closing")
end)

Test("X twice deletes a custom ring and removes it from Main", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "B")                  -- create ring1
	g.ns.SetSlot("main", 8, { ring = "ring1" })
	Pad(g, "X")
	Has(ui.hint:GetText(), "(or X) again", "confirm")
	Eq(g.env.ForeverRingsDB.rings.ring1 ~= nil, true, "not yet")
	Pad(g, "X")
	Eq(g.env.ForeverRingsDB.rings.ring1, nil, "deleted")
	Eq(#g.env.ForeverRingsDB.rings.main.slots, 7, "removed from main")
end)

Test("moving away cancels a pending delete", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "B", "X", "down", "up", "X")
	Eq(g.env.ForeverRingsDB.rings.ring1 ~= nil, true, "still there")
end)

Test("settings tab: style, aim and settings button", function()
	local g, ui, st = Open()
	Pad(g, "RB")
	Eq(st.tab, "settings", "settings tab")
	Has(RowText(ui, 1), "Style", "style row")
	Pad(g, "right")
	Eq(g.env.ForeverRingsDB.style, "classic", "style changed")
	Has(ui.rows[1].right:GetText(), "Classic", "shown")
	Pad(g, "down", "right")
	Eq(g.env.ForeverRingsDB.input, "lstick", "aim changed")
	Eq(g.env.ForeverRingsHeader:GetAttribute("key-up"), "PADLSTICKUP", "applied to rings")
	Pad(g, "left")
	Eq(g.env.ForeverRingsDB.input, "rstick", "back to right stick")
	Pad(g, "down", "down", "down", "down", "down", "down", "A") -- past Ring size, Pick on stick release, Hold camera still, Tap to repeat and Vibration
	Eq(st.capture, "config", "capturing settings button")
	g.GamePadButton("PADSOCIAL")
	Pad(g, "B")
	Eq(ui.frame:IsShown(), false, "closed")
	g.Press("PADSOCIAL", true)
	Eq(ui.frame:IsShown(), true, "settings button opens the screen")
	Pad(g, "LB")
	Eq(st.tab, "rings", "LB back to rings")
end)

Test("settings: tap to repeat and vibration toggles", function()
	local g, ui, st = Open()
	Pad(g, "RB", "down", "down", "down")
	Has(RowText(ui, 4), "Pick on stick release", "row")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.releasePick, false, "release-pick off")
	Eq(g.env.ForeverRingsHeader:GetAttribute("release-pick"), nil, "secure flag off")
	Pad(g, "down")
	Has(RowText(ui, 5), "Hold still while aiming", "row")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.holdCamera, false, "camera setting off")
	Pad(g, "down")
	Has(RowText(ui, 6), "Tap to repeat", "row")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.tapRepeat, false, "off")
	Eq(g.env.ForeverRingsHeader:GetAttribute("tap-repeat"), nil, "secure flag off")
	Pad(g, "right")
	Eq(g.env.ForeverRingsHeader:GetAttribute("tap-repeat"), true, "back on")
	Pad(g, "down", "A")
	Eq(g.env.ForeverRingsDB.vibration, false, "vibration off")
end)

Test("entering combat closes the screen cleanly", function()
	local g, ui = Open()
	g.SetCombat(true)
	Eq(ui.frame:IsShown(), false, "closed")
	Eq(next(ui.frame.overrides), nil, "gamepad released before lockdown")
	Has(g.printed[#g.printed], "closed for combat", "told the player")
	Has(g.Slash(""), "in combat", "can't reopen in combat")
	Eq(ui.frame:IsShown(), false, "still closed")
end)

Test("mouse: hover selects, click opens", function()
	local g, ui, st = Open()
	ui.rows[4].scripts.OnEnter(ui.rows[4])
	Eq(g.ns.configUI.ringKeys[st.ringIndex], "bag", "hovered bag")
	ui.rows[4].scripts.OnClick(ui.rows[4])
	Eq(st.mode, "edit", "clicked into bag")
end)

Test("mouse: click the Settings tab, wheel scrolls", function()
	local g, ui, st = Open()
	ui.tabButtons.settings.scripts.OnClick(ui.tabButtons.settings)
	Eq(st.tab, "settings", "Settings tab")
	ui.list.scripts.OnMouseWheel(ui.list, -1)
	Eq(st.settingIndex, 2, "wheel down")
	ui.rows[1].scripts.OnClick(ui.rows[1], "LeftButton")
	Eq(g.env.ForeverRingsDB.style, "classic", "click changes the style")
	ui.tabButtons.rings.scripts.OnClick(ui.tabButtons.rings)
	Eq(st.tab, "rings", "Rings tab")
end)

Test("mouse: drag a spell onto a slot, right-click clears it", function()
	local g, ui, st = Open()
	Pad(g, "up", "A")
	Eq(st.mode, "edit", "editing the new ring")
	g.cursorInfo = { "spell", 1, "spell", 3565 }
	ui.slots[1].scripts.OnReceiveDrag(ui.slots[1])
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].kind, "spell", "dropped")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].id, 3565, "the portal")
	Eq(g.cursorInfo, nil, "cursor cleared")
	g.cursorInfo = { "item", 101 }
	ui.slots[2].scripts.OnClick(ui.slots[2], "LeftButton")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[2].id, 101, "click drops too")
	ui.slots[1].scripts.OnClick(ui.slots[1], "RightButton")
	ui.slots[1].scripts.OnClick(ui.slots[1], "RightButton")
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 1, "cleared")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].id, 101, "item left")
end)

Test("mouse: dropping on an auto ring is refused", function()
	local g, ui, st = Open()
	g.cursorInfo = { "item", 101 }
	ui.rows[2].scripts.OnReceiveDrag(ui.rows[2])
	Has(st.message, "fills itself", "refused")
	Eq(g.cursorInfo, nil, "cursor cleared")
end)

Test("put a ring on the action bar: a macro in the first free slot that clicks it", function()
	local g, ui, st = Open()
	g.actions[1] = { "spell", 133 }
	g.Slash("bar food")
	local name, _, body = g.env.GetMacroInfo(g.env.GetMacroIndexByName("FR Food"))
	Eq(name, "FR Food", "macro made")
	Eq(body, "/click ForeverRingsTrigger_food LeftButton 1", "clicks the ring")
	Eq(g.actions[1][1], "spell", "taken slot left alone")
	Eq(g.actions[2][1], "macro", "next free slot")
	Eq(g.cursorInfo, nil, "nothing left on the cursor")
	g.Slash("bar food")
	Eq(g.env.GetNumMacros(), 2, "reused, not duplicated")
	Eq(g.actions[3], nil, "not placed twice")
end)

Test("Bar picks a visible action button (the gamepad bar shows other slots)", function()
	local g, ui, st = Open()
	for i = 1, 12 do
		g.env["ActionButton" .. i].shown = false   -- main bar hidden, like the gamepad bar
	end
	local hidden = g.env.CreateFrame("CheckButton", nil, g.env.UIParent)
	hidden.action = 3
	hidden.shown = false
	local taken = g.env.CreateFrame("CheckButton", nil, g.env.UIParent)
	taken.action = 25
	g.actions[25] = { "spell", 133 }
	local free = g.env.CreateFrame("CheckButton", nil, g.env.UIParent)
	free.action = 97
	g.env.EnumerateFrames = function(after)
		local found = after == nil
		for _, f in ipairs(g.frames) do
			if found then
				return f
			end
			found = f == after
		end
	end
	g.Slash("bar food")
	Eq(g.actions[97] and g.actions[97][1], "macro", "the visible free one")
	Eq(g.actions[3], nil, "not the hidden one")
end)

Test("full action bars: the ring stays on the cursor to drop yourself", function()
	local g, ui, st = Open()
	for slot = 1, 72 do
		g.actions[slot] = { "spell", 133 }
	end
	g.Slash("bar food")
	Eq(g.cursorInfo[1], "macro", "on the cursor")
end)

Test("editor: the list shows the ring's slots; click picks, right-click clears", function()
	local g, ui, st = Open()
	Pad(g, "up", "A")                       -- new ring1, in the editor
	Eq(ui.listTitle:GetText(), "Ring1", "title says which ring")
	Has(RowText(ui, 1), "+ Add", "empty ring: just Add")
	Eq(ui.rows[1].cells[1].shown, false, "no ring buttons in the editor")
	ui.rows[1].scripts.OnClick(ui.rows[1], "LeftButton")
	Eq(st.mode, "pick", "Add opens the picker")
	Has(ui.listTitle:GetText(), "slot 1", "title shows the slot")
	Eq(ui.categories[1]:IsShown(), true, "categories on their own row")
	Pad(g, "A")
	Has(RowText(ui, 1), "Healing Potion", "slot listed")
	Has(RowText(ui, 2), "+ Add", "then Add")
	ui.rows[1].scripts.OnClick(ui.rows[1], "RightButton")
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 1, "first right-click asks")
	ui.rows[1].scripts.OnClick(ui.rows[1], "RightButton")
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 0, "second clears it")
end)

Test("Settings > Main ring: Reset asks once, then restores Main", function()
	local g, ui, st = Open()
	g.Slash("remove main 8")
	Pad(g, "RB", "up")                      -- last setting (the list scrolls)
	local row = st.settingIndex - (ui.listOffset or 0)
	Has(RowText(ui, row), "Main ring", "row")
	Pad(g, "A")
	Has(ui.rows[row].right:GetText(), "Press again", "asks")
	Eq(#g.env.ForeverRingsDB.rings.main.slots, 7, "not yet")
	Pad(g, "A")
	Eq(#g.env.ForeverRingsDB.rings.main.slots, 8, "reset")
	Has(st.message, "default", "told")
end)

Test("Menus category lists the game panels", function()
	local world = World()
	local g = WoW.New(world)
	g.env.CharacterMicroButton = g.env.CreateFrame("Button", "CharacterMicroButton", g.env.UIParent)
	g.Login()
	g.Slash("")
	local ui, st = g.ns.configUI, g.ns.configState
	Pad(g, "up", "A", "A")                  -- new ring, picker
	for _ = 1, 5 do Pad(g, "RB") end
	Eq(ui.categories[st.pickCategory].label:GetText(), "Menus", "Menus category")
	Has(RowText(ui, 1), "Character", "character panel")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].menu, "character", "in the ring")
end)

Test("Party heals: Hover cast lists twelve buttons", function()
	local g, ui, st = Open()
	g.ns.SetPartyHeals("hover")
	for i, k in ipairs(ui.ringKeys) do
		if k == "party" then st.ringIndex = i end
	end
	Pad(g, "A")
	Has(ui.listTitle:GetText(), "Hover cast", "title")
	Has(RowText(ui, 1), "A:", "A first")
	Has(RowText(ui, 5), "L2 + A:", "then L2")
	Has(RowText(ui, 10), "R2 + B:", "then R2")
	Pad(g, "down", "A")                     -- B: pick a spell
	Eq(st.mode, "pick", "picker")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.partyHover.b ~= nil, true, "B has a spell")
end)

Test("mouse: click a picker category", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "A")                  -- new ring, picker open on Bags
	Eq(st.mode, "pick", "picking")
	Eq(ui.categories[2]:IsShown(), true, "categories shown")
	ui.categories[2].scripts.OnClick(ui.categories[2])
	Eq(st.pickCategory, 2, "Spells")
	Has(RowText(ui, 1), "Arcane Intellect", "spells listed")
	Pad(g, "B", "B")
	Eq(ui.categories[2]:IsShown(), false, "hidden outside the picker")
end)

Test("spells show their rank, highest rank first", function()
	local world = World()
	world.spells[1459].rank = "Rank 1"
	world.spells[1460] = { name = "Arcane Intellect", icon = 4002, rank = "Rank 2" }
	table.insert(world.spellbook, 1460)
	local g = WoW.New(world).Login()
	g.Slash("")
	local ui, st = g.ns.configUI, g.ns.configState
	Pad(g, "up", "A", "A", "RB")
	Has(RowText(ui, 1), "Arcane Intellect (Rank 2)", "rank 2 first")
	Has(RowText(ui, 2), "Arcane Intellect (Rank 1)", "then rank 1")
	Has(RowText(ui, 3), "Portal: Darnassus", "no rank, no brackets")
	Lacks(RowText(ui, 3), "(", "nothing added")
	Pad(g, "A")
	Eq(g.ns.resolved.ring1[1].name, "Arcane Intellect (Rank 2)", "ring slot shows the rank")
	Eq(g.ns.resolved.ring1[1].value, 1460, "casts that rank")
end)

Test("keyboard: arrows, Enter and Esc", function()
	local g, ui, st = Open()
	g.KeyDown("DOWN")
	g.KeyDown("ENTER")
	Eq(st.mode, "edit", "Enter opens")
	g.KeyDown("ESCAPE")
	Eq(st.mode, "list", "Esc goes back")
	g.KeyDown("ESCAPE")
	Eq(ui.frame:IsShown(), false, "Esc closes")
end)

Test("toggle via its own binding and via /frings config", function()
	local g, ui = Open()
	g.Slash("config")
	Eq(ui.frame:IsShown(), false, "toggled off")
	g.env.ForeverRings_ToggleConfig()
	Eq(ui.frame:IsShown(), true, "toggled on")
end)

-- Controller-only setup ------------------------------------------------------

Test("first login opens the screen with a welcome on Main", function()
	local world = World()
	local g = WoW.New(world).Login()
	g.RunTimers()
	local ui, st = g.ns.configUI, g.ns.configState
	Eq(ui.frame:IsShown(), true, "opened by itself")
	Has(ui.info:GetText(), "Welcome to Forever Rings", "welcome text")
	Eq(ui.ringKeys[st.ringIndex], "main", "Main selected")
	Pad(g, "Y")
	Eq(st.capture, "bar", "Y: pick an action bar button")
	g.env.ActionButton1.action = 1
	g.env.ActionButtonDown(1)
	Pad(g, "B")
	Eq(g.ns.RingOnBar("main"), 1, "set up without a keyboard")
	local again = WoW.New(World()).Login(g.env.ForeverRingsDB)
	again.RunTimers()
	Eq(again.ns.configUI, nil, "only the first time")
end)

Test("the Settings slot in Main opens this screen and isn't remembered for tap", function()
	local g = WoW.New(World()).Login({ welcomed = true })
	g.RunTimers()
	g.Slash("bind main PADLSTICK")
	g.Press("PADLSTICK", true)
	g.Press("PADRSTICKUP", true)
	g.Press("PADRSTICKLEFT", true)  -- up-left = slot 8 of 8
	g.Press("PADLSTICK", false)
	Eq(g.env.ForeverRingsConfig and g.env.ForeverRingsConfig:IsShown(), true, "settings opened")
	Eq(#g.casts, 0, "no macro")
	Eq(g.env.ForeverRingsHeader:GetAttribute("last:main:t"), nil, "not stored as last used")
end)

Test("Options > AddOns has a page with an open button", function()
	local g = WoW.New(World()).Login({ welcomed = true })
	Eq(g.optionsPages[1] and g.optionsPages[1].name, "Forever Rings", "registered")
	g.ns.optionsButton.scripts.OnClick()
	Eq(g.env.ForeverRingsConfig:IsShown(), true, "opens the screen")
end)

Test("rename a ring by picking a name", function()
	local g, ui, st = Open()
	Pad(g, "up", "A")                  -- new Ring1, editing
	Pad(g, "Y")
	Eq(st.mode, "name", "name picker")
	Pad(g, "down", "A")
	Eq(g.env.ForeverRingsDB.rings.ring1.label, "Travel", "renamed")
	Eq(st.mode, "edit", "back to editor")
	Pad(g, "B")
	Has(RowText(ui, st.ringIndex), "Travel", "new name in list")
	Pad(g, "down", "down", "A", "Y")   -- wrap to Main
	Eq(st.mode, "edit", "Main can't be renamed")
end)

Test("macros: pick your own macro, it follows edits, and survives deletion", function()
	local world = World()
	local g = WoW.New(world).Login({ welcomed = true })
	g.Slash("")
	local ui, st = g.ns.configUI, g.ns.configState
	Pad(g, "up", "A", "A", "RB", "RB", "RB", "RB")
	Eq(ui.categories[st.pickCategory].label:GetText(), "Macros", "macros category")
	Has(RowText(ui, 1), "Shout", "macro listed")
	Pad(g, "A")
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:ring1:t1"), "macro", "macro slot")
	Eq(h:GetAttribute("r:ring1:v1"), "/y For the Horde!", "macro text")
	world.macros[1].body = "/y For the Alliance!"
	g.Fire("UPDATE_MACROS")
	g.RunTimers()
	Eq(h:GetAttribute("r:ring1:v1"), "/y For the Alliance!", "follows edits")
	table.remove(world.macros, 1)
	g.Fire("UPDATE_MACROS")
	g.RunTimers()
	Eq(h:GetAttribute("r:ring1:t1"), nil, "no action")
	Has(g.ns.resolved.ring1[1].name, "(missing)", "shown as missing")
	Eq(#g.env.ForeverRingsDB.rings.ring1.slots, 1, "slot kept")
end)

Test("Settings can be put in any ring from the Rings picker", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "A", "LB")
	Has(RowText(ui, 1), "Settings", "first entry")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].settings, true, "added")
end)

Test("ring size setting scales the ring", function()
	local g, ui, st = Open()
	Pad(g, "RB", "down", "down")
	Has(RowText(ui, 3), "Ring size", "row")
	Pad(g, "right")
	Eq(g.env.ForeverRingsDB.scale, 1.1, "bigger")
	Has(ui.rows[3].right:GetText(), "110%", "shown")
	Pad(g, "B")
	g.Slash("bind food F")
	g.Press("F", true)
	Eq(g.ns.display.frame.scale, 1.1, "ring drawn bigger")
end)

Test("Party ring: A picks the heal from Spells, X clears it", function()
	local g, ui, st = Open()
	for _ = 1, 6 do Pad(g, "down") end
	Eq(ui.ringKeys[st.ringIndex], "party", "on Party")
	Pad(g, "A")
	Has(ui.info:GetText(), "targets them", "no spell yet")
	Has(ui.hint:GetText(), "A choose spell", "hint")
	Pad(g, "A")
	Eq(st.mode, "pick", "picker")
	Has(RowText(ui, 1), "Arcane Intellect", "opens on Spells")
	Pad(g, "A")
	Eq(st.mode, "edit", "back in the editor")
	Eq(g.env.ForeverRingsDB.partySpell, 1459, "spell saved")
	Has(ui.info:GetText(), "Arcane Intellect", "shown")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:party:t1"), "spell", "ring casts it")
	Pad(g, "X")
	Eq(g.env.ForeverRingsDB.partySpell, nil, "cleared")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:party:t1"), "target", "targets again")
end)

Test("Party options in Settings, and a heal per button in the editor", function()
	local g, ui, st = Open()
	Pad(g, "RB")
	for _ = 1, 8 do Pad(g, "down") end
	local row = st.settingIndex - (ui.listOffset or 0)
	Has(RowText(ui, row), "Party heals", "row")
	Has(ui.rows[row].right:GetText(), "One spell", "default")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.partyHeals, "buttons", "spell per button")
	Pad(g, "down")
	Has(RowText(ui, st.settingIndex - (ui.listOffset or 0)), "Party button", "tap or hold")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.partyOpen, "toggle", "toggle")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.partyOpen, "hold", "hold")
	Pad(g, "down", "A")
	Eq(g.env.ForeverRingsDB.partyFill, "centre", "fills from the centre")
	Pad(g, "down", "A")
	Eq(g.env.ForeverRingsDB.partyBuffs, "all", "all buffs")
	Pad(g, "down", "A")
	Eq(g.env.ForeverRingsDB.partyOrder, "role", "by role")
	Pad(g, "LB")
	for _ = 1, 6 do Pad(g, "down") end
	Pad(g, "A")
	Has(RowText(ui, 1), "Release:", "release row")
	Has(RowText(ui, 3), "X:", "X row")
	Pad(g, "down", "down")
	Has(ui.listTitle:GetText(), "heal per button", "title")
	Pad(g, "A")
	Eq(st.mode, "pick", "picker for X")
	Pad(g, "A")
	Eq(g.env.ForeverRingsDB.partyButtons.x, 1459, "X heal saved")
	Has(RowText(ui, 3), "Arcane Intellect", "shown on the X row")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:party:btn-x"), 1459, "ring knows")
	Pad(g, "X")
	Eq(g.env.ForeverRingsDB.partyButtons.x, nil, "cleared")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
