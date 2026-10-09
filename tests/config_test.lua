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
local function Pad(g, ...)
	for _, name in ipairs({ ... }) do
		g.Press(PAD[name] or name, true)
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
	Eq(ui.frame.overrides.PAD1.name, "ForeverRingsConfigInput", "A bound")
	Has(RowText(ui, 1), "Main", "first row")
	Has(RowText(ui, 2), "Food", "second row")
	Has(RowText(ui, 8), "New ring", "last row")
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
	Has(ui.listTitle:GetText(), "Bags", "starts on Bags")
	Pad(g, "RB")
	Has(RowText(ui, 1), "Arcane Intellect", "spells sorted")
	Eq(RowText(ui, 3), nil, "passive spell hidden")
	Pad(g, "A")
	Eq(st.mode, "edit", "back in editor")
	Eq(g.env.ForeverRingsDB.rings.ring1.slots[1].id, 1459, "spell saved")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:ring1:v1"), 1459, "pushed to secure ring")

	Pad(g, "right", "A")
	Has(ui.listTitle:GetText(), "|cffffffffSpells", "picker remembers the last category")
	Pad(g, "RB", "RB")
	Has(ui.listTitle:GetText(), "|cffffffffToys", "RB to Toys")
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
	Has(ui.listTitle:GetText(), "|cffffffffRings", "rings category")
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

Test("Y sets a ring button with the next gamepad press", function()
	local g, ui, st = Open()
	Pad(g, "down", "Y")
	Eq(st.capture, "food", "capturing")
	Has(ui.capture:GetText(), "Press the button for Food", "prompt")
	Eq(ui.frame.overrides.PAD1, nil, "own bindings off while capturing")
	g.GamePadButton("PAD1")
	Eq(st.capture, "food", "A refused")
	Has(ui.hint:GetText(), "used inside rings", "warning")
	g.GamePadButton("PADRSHOULDER")
	Eq(st.capture, nil, "done")
	Eq(g.env.GetBindingKey(g.ns.TriggerCommand("food")), "PADRSHOULDER", "bound")
	Has(ui.rows[2].right:GetText(), "PADRSHOULDER", "shown in list")
	Eq(ui.frame.overrides.PAD1.name, "ForeverRingsConfigInput", "bindings back")

	Pad(g, "Y")
	g.GamePadButton("PADLSHOULDER")
	Eq(g.env.GetBindingKey(g.ns.TriggerCommand("food")), "PADLSHOULDER", "old button replaced")
	Eq(g.bindings.PADRSHOULDER, nil, "old button freed")
end)

Test("binding a shoulder button works but warns about Blizzard's gamepad UI", function()
	local g, ui, st = Open()
	Pad(g, "Y")
	Has(ui.capture:GetText(), "L3 or paddles", "tip in prompt")
	g.GamePadButton("PADRSHOULDER")
	Eq(g.env.GetBindingKey(g.ns.TriggerCommand("main")), "PADRSHOULDER", "still bound")
	Has(ui.hint:GetText(), "targets enemies", "warning")
	Pad(g, "Y")
	g.GamePadButton("PADLSTICK")
	Lacks(ui.hint:GetText(), "Note:", "no warning for L3")
	Pad(g, "Y")
	g.GamePadButton("PADRSTICK")
	Has(ui.hint:GetText(), "you aim with this stick", "warning for R3 while aiming with the right stick")
end)

Test("B cancels button capture", function()
	local g, ui, st = Open()
	Pad(g, "Y")
	g.GamePadButton("PAD2")
	Eq(st.capture, nil, "cancelled")
	Eq(g.env.GetBindingKey(g.ns.TriggerCommand("main")), nil, "nothing bound")
end)

Test("keyboard keys can be captured too, modifiers alone are ignored", function()
	local g, ui, st = Open()
	Pad(g, "Y")
	g.KeyDown("LSHIFT")
	Eq(st.capture, "main", "still capturing")
	g.KeyDown("F")
	Eq(g.env.GetBindingKey(g.ns.TriggerCommand("main")), "F", "bound F")
end)

Test("a bound ring opens after closing the screen", function()
	local g, ui = Open()
	Pad(g, "Y")
	g.GamePadButton("PADLSHOULDER")
	Pad(g, "B")
	g.Press("PADLSHOULDER", true)
	Eq(g.env.ForeverRingsHeader:IsShown(), true, "ring opens")
end)

Test("X twice deletes a custom ring and removes it from Main", function()
	local g, ui, st = Open()
	Pad(g, "up", "A", "B")                  -- create ring1
	g.ns.SetSlot("main", 8, { ring = "ring1" })
	Pad(g, "X")
	Has(ui.hint:GetText(), "Press X again", "confirm")
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
	Pad(g, "down", "down", "down", "down", "A") -- past Ring size, Tap to repeat and Vibration
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
	Has(RowText(ui, 4), "Tap to repeat", "row")
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

Test("keyboard: arrows, Enter and Esc", function()
	local g, ui, st = Open()
	g.Press("DOWN", true)
	g.Press("ENTER", true)
	Eq(st.mode, "edit", "Enter opens")
	g.Press("ESCAPE", true)
	Eq(st.mode, "list", "Esc goes back")
	g.Press("ESCAPE", true)
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
	g.GamePadButton("PADLSTICK")
	Pad(g, "B")
	Eq(g.env.GetBindingKey(g.ns.TriggerCommand("main")), "PADLSTICK", "set up without a keyboard")
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
	g.Press("PADRSTICKLEFT", true)  -- up-left = slot 7 of 7
	g.Press("PADLSTICK", false)
	Eq(g.casts[1] and g.casts[1].value, "/frings config", "settings macro")
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
	Has(ui.listTitle:GetText(), "|cffffffffMacros", "macros category")
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

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
