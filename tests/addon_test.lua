-- Loads the whole addon in the fake client and plays through real scenarios.
-- Usage: luajit tests/addon_test.lua   (from the repo root)

package.path = "tests/?.lua;" .. package.path
local WoW = require("wowmock")

local FOOD, CONSUMABLE, POTION, WEAPON, TRADE, QUEST, MISC = 0, 0, 1, 2, 7, 12, 15

local function World()
	return {
		items = {
			[101] = { name = "Roasted Boar", icon = 1001, class = FOOD, subclass = 5, ilvl = 10, count = 5 },
			[102] = { name = "Mage Bread", icon = 1002, class = FOOD, subclass = 5, ilvl = 30, count = 2 },
			[103] = { name = "Sweet Water", icon = 1003, class = FOOD, subclass = 5, ilvl = 30, count = 8 },
			[201] = { name = "Healing Potion", icon = 2001, class = CONSUMABLE, subclass = POTION, ilvl = 20, count = 3, spell = 441 },
			[202] = { name = "Strange Orb", icon = 2002, class = QUEST, subclass = 0, ilvl = 1, spell = 900 },
			[203] = { name = "Sword of Use", icon = 2003, class = WEAPON, subclass = 7, ilvl = 40, spell = 901 },
			[204] = { name = "Linen Cloth", icon = 2004, class = TRADE, subclass = 5, ilvl = 5 },
			[301] = { name = "Toy Train", icon = 3001, class = MISC, subclass = 0, ilvl = 1, spell = 902 },
			[6948] = { name = "Hearthstone", icon = 6948, class = MISC, subclass = 0, ilvl = 1, spell = 8690 },
		},
		bags = {
			[0] = { 101, 102, 103, 201, 202, 203, 204, 6948, 101 },
			[1] = { 301 },
		},
		toys = { [301] = true },
		spells = {
			[3565] = { name = "Portal: Darnassus", icon = 4001 },
			[1459] = { name = "Arcane Intellect", icon = 4002 },
		},
		mounts = {
			{ id = 1, name = "Swift Gryphon", spell = 458, icon = 5001, favorite = true },
			{ id = 2, name = "Brown Horse", spell = 470, icon = 5002 },
			{ id = 3, name = "Unowned Drake", spell = 999, icon = 5003, favorite = true, collected = false },
			{ id = 4, name = "Other Faction", spell = 998, icon = 5004, favorite = true, hidden = true },
		},
	}
end

local function Login(world, saved)
	return WoW.New(world or World()).Login(saved)
end

local function Ring(g, key)
	local h, list = g.env.ForeverRingsHeader, {}
	for i = 1, h:GetAttribute("r:" .. key .. ":n") or 0 do
		list[i] = h:GetAttribute("r:" .. key .. ":v" .. i)
	end
	return list
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

-- Loading ---------------------------------------------------------------------

Test("loads and logs in without errors", function()
	local g = Login()
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "ring hidden at login")
	for _, key in ipairs({ "main", "food", "bag", "mount", "tools" }) do
		assert(g.env["ForeverRingsTrigger_" .. key], "trigger for " .. key)
	end
	Eq(g.env.BINDING_HEADER_FOREVERRINGS, "Forever Rings", "binding header")
	Eq(g.env.ForeverRingsDB.style, "clean", "default style")
end)

Test("keeps saved rings and settings", function()
	local g = Login(nil, {
		style = "classic",
		rings = { main = { label = "Main", slots = { { ring = "portals" } } }, portals = { label = "Portals", slots = { { kind = "spell", id = 3565 } } } },
	})
	assert(g.env.ForeverRingsTrigger_portals, "custom ring trigger")
	Eq(Ring(g, "portals")[1], 3565, "portal spell")
	Eq(g.env.ForeverRingsDB.style, "classic", "style kept")
	Eq(g.env.ForeverRingsDB.input, "rstick", "missing default filled in")
end)

-- Auto rings ------------------------------------------------------------------

Test("food ring: best item level first, then biggest stack, no duplicates", function()
	local food = Ring(Login(), "food")
	Eq(#food, 3, "food count")
	Eq(food[1], "item:103", "ilvl 30, 8 stack")
	Eq(food[2], "item:102", "ilvl 30, 2 stack")
	Eq(food[3], "item:101", "ilvl 10")
end)

Test("bag ring: usable items only, no gear, no food, toys as toys", function()
	local g = Login()
	local bag = Ring(g, "bag")
	Eq(#bag, 4, "usable count")
	Eq(bag[1], "item:201", "potion")
	Eq(bag[2], "item:202", "quest item")
	Eq(bag[3], "item:6948", "hearthstone")
	Eq(bag[4], 301, "toy value is the item ID")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:bag:t4"), "toy", "toy type")
end)

Test("mount ring: collected, visible favorites", function()
	local mounts = Ring(Login(), "mount")
	Eq(#mounts, 1, "one favorite")
	Eq(mounts[1], 458, "gryphon spell")
end)

Test("mount ring: all usable mounts when nothing is favorited", function()
	local world = World()
	for _, m in ipairs(world.mounts) do
		m.favorite = false
	end
	local mounts = Ring(Login(world), "mount")
	Eq(#mounts, 2, "collected and not hidden")
end)

Test("rings cap at 8 slots", function()
	local world = World()
	for i = 1, 12 do
		world.items[1000 + i] = { name = "Food " .. i, icon = 1, class = FOOD, subclass = 5, ilvl = i }
		world.bags[2] = world.bags[2] or {}
		world.bags[2][i] = 1000 + i
	end
	Eq(#Ring(Login(world), "food"), 8, "capped")
end)

Test("main ring holds the auto rings as sub-rings", function()
	local g = Login()
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:main:n"), 4, "four slots")
	Eq(h:GetAttribute("r:main:t1"), "ring", "slot 1 is a ring")
	Eq(h:GetAttribute("r:main:v1"), "food", "slot 1 opens food")
end)

Test("items without cached info don't break anything", function()
	local world = World()
	world.items[102].uncached = true
	local g = Login(world)
	g.Slash("bind food PADLSHOULDER")
	g.Press("PADLSHOULDER", true)
	g.Press("PADRSTICKRIGHT", true)
	g.Update()
end)

-- Playing with a controller ---------------------------------------------------

Test("hold LB, stick up into Food, A picks the best food", function()
	local g = Login()
	local h, display = g.env.ForeverRingsHeader, g.ns.display
	Has(g.Slash("bind main PADLSHOULDER"), "targets allies", "warned")
	Has(g.printed[#g.printed], "Bound PADLSHOULDER", "bound")

	g.Press("PADLSHOULDER", true)
	Eq(h:IsShown(), true, "ring open")
	g.Update()
	Eq(display.title:GetText(), "Main", "title")

	g.Press("PADRSTICKUP", true)
	g.Update()
	Eq(display.title:GetText(), "Food", "highlighted food")
	assert(display.slots[1].disc:GetAlpha() > 0.5, "clean highlight")
	Eq(display.slots[2].disc:GetAlpha(), 0, "others not highlighted")

	g.Press("PADLSHOULDER", false)
	Eq(h:IsShown(), true, "food stays open")
	Eq(h:GetAttribute("active"), "food", "in food ring")
	Eq(#display.slices, 3, "food slots drawn")
	Has(display.hint:GetText(), "B back", "hint")

	g.Press("PAD1", true)
	Eq(#g.casts, 1, "one cast")
	Eq(g.casts[1].value, "item:103", "used best food")
	Eq(h:IsShown(), false, "closed")
	Eq(next(h.overrides), nil, "gamepad keys released")
end)

Test("release on an action uses it right away", function()
	local g = Login()
	g.Slash("bind mount PADRSHOULDER")
	g.Press("PADRSHOULDER", true)
	g.Press("PADRSTICKUP", true)
	g.Press("PADRSHOULDER", false)
	Eq(g.casts[1] and g.casts[1].type, "spell", "spell cast")
	Eq(g.casts[1].value, 458, "gryphon")
end)

Test("B backs out of a sub-ring, then closes", function()
	local g = Login()
	local h = g.env.ForeverRingsHeader
	g.Slash("bind main PADLSHOULDER")
	g.Press("PADLSHOULDER", true)
	g.Press("PADRSTICKDOWN", true)
	g.Press("PADLSHOULDER", false)
	Eq(h:GetAttribute("active"), "bag", "in bag ring")
	g.Press("PAD2", true)
	Eq(h:GetAttribute("active"), "main", "back to main")
	g.Press("PAD2", true)
	Eq(h:IsShown(), false, "closed")
	Eq(#g.casts, 0, "nothing used")
end)

Test("the whole flow works in combat without blocked actions", function()
	local g = Login()
	g.Slash("bind main PADLSHOULDER")
	g.SetCombat(true)
	g.Press("PADLSHOULDER", true)
	g.Press("PADRSTICKDOWN", true)
	g.Press("PADLSHOULDER", false)
	g.Update()
	g.Press("PADRSTICKDOWN", false)
	g.Press("PADRSTICKUP", true)
	g.Press("PAD1", true)
	Eq(g.casts[1] and g.casts[1].value, "item:201", "potion in combat")
end)

Test("the fake client does block protected changes in combat", function()
	local g = Login()
	g.SetCombat(true)
	local ok, err = pcall(function() g.env.ForeverRingsHeader:SetAttribute("x", 1) end)
	Eq(ok, false, "blocked")
	Has(err, "ADDON_ACTION_BLOCKED")
end)

Test("D-pad input mode", function()
	local g = Login()
	g.Slash("input dpad")
	g.Slash("bind mount PADLSHOULDER")
	g.Press("PADLSHOULDER", true)
	g.Press("PADDUP", true)
	g.Press("PADLSHOULDER", false)
	Eq(g.casts[1] and g.casts[1].value, 458, "picked with D-pad")
end)

-- Keyboard and mouse ----------------------------------------------------------

Test("mouse aim with a keyboard binding", function()
	local g = Login()
	g.Slash("bind food F")
	g.cursor = { 960, 540 }
	g.Press("F", true)
	g.cursor = { 1040, 540 } -- 80px right: slice 2 of 3 (120 degrees) is closest
	g.Update()
	Eq(g.ns.display.title:GetText(), "Mage Bread", "highlight follows mouse")
	g.Press("F", false)
	Eq(g.casts[1] and g.casts[1].value, "item:102", "mouse pick")
end)

-- Updates and combat ----------------------------------------------------------

Test("bag changes refresh rings, but only after combat", function()
	local world = World()
	local g = Login(world)
	g.SetCombat(true)
	world.items[105] = { name = "Feast", icon = 1005, class = FOOD, subclass = 5, ilvl = 50 }
	world.bags[1][2] = 105
	g.Fire("BAG_UPDATE_DELAYED")
	g.RunTimers()
	Eq(#Ring(g, "food"), 3, "unchanged in combat")
	g.SetCombat(false)
	Eq(#Ring(g, "food"), 4, "refreshed after combat")
end)

Test("new food in bags shows up after refresh", function()
	local world = World()
	local g = Login(world)
	world.items[105] = { name = "Feast", icon = 1005, class = FOOD, subclass = 5, ilvl = 50 }
	world.bags[1][2] = 105
	g.Fire("BAG_UPDATE_DELAYED")
	g.RunTimers()
	Eq(Ring(g, "food")[1], "item:105", "best new food first")
end)

Test("empty ring shows (empty)", function()
	local g = Login()
	g.Slash("bind tools T")
	g.Press("T", true)
	g.Update()
	Has(g.ns.display.title:GetText(), "(empty)", "title")
	g.Press("T", false)
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "closed")
end)

-- Slash commands --------------------------------------------------------------

Test("create a ring, fill it, put it in main, bind and use it", function()
	local g = Login()
	Has(g.Slash("new Portals"), "Created 'portals'")
	Has(g.Slash("add portals |cff71d5ff|Hspell:3565:0|h[Portal: Darnassus]|h|r"), "Added Portal: Darnassus")
	Has(g.Slash("add portals 6948"), "Added Hearthstone")
	Has(g.Slash("add main ring:portals"), "Added Ring: Portals")
	Eq(Ring(g, "main")[5], "portals", "in main ring")
	Eq(g.ns.resolved.main[5].icon, 4001, "sub-ring borrows first icon")
	g.Slash("bind portals PADPADDLE1")
	g.Press("PADPADDLE1", true)
	g.Press("PADRSTICKUP", true)
	g.Press("PADPADDLE1", false)
	Eq(g.casts[1] and g.casts[1].value, 3565, "portal cast")
end)

Test("list, remove and delete", function()
	local g = Login()
	g.Slash("new portals")
	g.Slash("add portals |Hspell:3565|h")
	g.Slash("add portals |Hspell:1459|h")
	g.Slash("add main ring:portals")
	Has(g.Slash("list portals"), "2. Arcane Intellect", "list")
	Has(g.Slash("remove portals 1"), "Removed Portal: Darnassus")
	Eq(Ring(g, "portals")[1], 1459, "shifted up")
	Has(g.Slash("delete portals"), "Deleted 'portals'")
	Eq(#Ring(g, "main"), 4, "removed from main too")
	Eq(Ring(g, "portals")[1], nil, "ring gone")
end)

Test("commands refuse bad input", function()
	local g = Login()
	Has(g.Slash("add food 6948"), "fills itself")
	Has(g.Slash("add nope 6948"), "No ring named")
	Has(g.Slash("add tools"), "Usage")
	Has(g.Slash("add main ring:main"), "can't contain itself")
	Has(g.Slash("new food"), "already exists")
	Has(g.Slash("new a-b"), "Usage")
	Has(g.Slash("delete main"), "can't be deleted")
	Has(g.Slash("remove tools 5"), "No slot 5")
	Has(g.Slash("remove tools"), "Usage")
	Has(g.Slash("bind nope X"), "Usage")
	Has(g.Slash("style neon"), "Usage")
	Has(g.Slash("input wheel"), "Usage")
	Has(g.Slash("help"), "/frings")
end)

Test("/frings bind warns for buttons Blizzard's gamepad UI uses", function()
	local g = Login()
	Has(g.Slash("bind food PADLTRIGGER"), "action bar modifier", "trigger warning")
	Has(g.Slash("bind food PADLSTICK"), "Bound PADLSTICK", "no warning for L3")
end)

Test("full ring refuses a 9th slot", function()
	local g = Login()
	for _ = 1, 8 do
		g.Slash("add tools 6948")
	end
	Has(g.Slash("add tools 6948"), "full")
end)

Test("ring changes are refused in combat", function()
	local g = Login()
	g.SetCombat(true)
	Has(g.Slash("new portals"), "in combat")
	Has(g.Slash("add tools 6948"), "in combat")
	Has(g.Slash("style classic"), "Style: classic")
end)

Test("classic style draws borders and square icons", function()
	local g = Login()
	g.Slash("style classic")
	g.Slash("bind food F")
	g.Press("F", true)
	g.Press("PADRSTICKUP", true)
	g.Update()
	local slot = g.ns.display.slots[1]
	Eq(slot.border:IsShown(), true, "border")
	Eq(next(slot.icon.masks), nil, "no round mask")
	assert(slot.glow:GetAlpha() > 0.5, "glow on selection")
	Eq(g.ns.display.backdrop:IsShown(), false, "no backdrop")
end)

-- Eat & Drink, tap to repeat, vibration, animation ---------------------------

local function FoodWorld()
	local world = World()
	world.spells[433] = { name = "Food", icon = 1 }
	world.spells[430] = { name = "Drink", icon = 2 }
	world.items[101].spell = 433 -- Roasted Boar: food
	world.items[102].spell = 433 -- Mage Bread: food (better)
	world.items[103].spell = 430 -- Sweet Water: drink
	return world
end

Test("food ring starts with Eat & Drink using the best of each", function()
	local g = Login(FoodWorld())
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:food:t1"), "macro", "macro slot")
	Eq(h:GetAttribute("r:food:v1"), "/use item:102\n/use item:103", "best food + drink")
	Eq(g.ns.resolved.food[1].name, "Eat & Drink", "name")
	Eq(g.ns.resolved.food[1].icon2, 1003, "drink icon")
	Eq(#Ring(g, "food"), 4, "plus the 3 items")
	g.Slash("bind food F")
	g.Press("F", true)
	g.Press("PADRSTICKUP", true)
	g.Press("F", false)
	Eq(g.casts[1].type, "macro", "cast macro")
end)

Test("no Eat & Drink slot without both food and drink", function()
	local world = FoodWorld()
	world.items[103].spell = 433 -- no drink left
	Eq(Login(world).env.ForeverRingsHeader:GetAttribute("r:food:t1"), "item", "plain items")
end)

Test("tap repeats, shows a hint, and survives a reload", function()
	local g = Login()
	g.Slash("bind mount M")
	g.Press("M", true)
	g.Press("PADRSTICKUP", true)
	g.Press("M", false)
	g.Press("PADRSTICKUP", false)
	g.Press("M", true)
	g.Update()
	Has(g.ns.display.hint:GetText(), "Tap: Swift Gryphon", "hint")
	g.Press("M", false)
	Eq(#g.casts, 2, "tap cast again")
	Eq(g.casts[2].value, 458, "same mount")

	local saved = g.env.ForeverRingsDB
	local g2 = WoW.New(World()).Login(saved)
	g2.SetCombat(false)
	g2.bindings.M = "CLICK ForeverRingsTrigger_mount:LeftButton"
	g2.Press("M", true)
	g2.Press("M", false)
	Eq(g2.casts[1] and g2.casts[1].value, 458, "remembered after reload")
end)

Test("vibrates when the stick moves to another slot, not for the mouse", function()
	local g = Login()
	g.Slash("bind food F")
	g.Press("F", true)
	g.Update()
	Eq(g.vibrations, 0, "nothing yet")
	g.Press("PADRSTICKUP", true)
	g.Update()
	g.Update()
	Eq(g.vibrations, 1, "one buzz per change")
	g.Press("PADRSTICKUP", false)
	g.Press("PADRSTICKRIGHT", true)
	g.Update()
	Eq(g.vibrations, 2, "buzz on new slot")
	g.Press("F", false)
	g.Press("PADRSTICKRIGHT", false)
	g.Press("F", true)
	g.cursor = { 1040, 540 }
	g.Update()
	Eq(g.vibrations, 2, "no buzz for mouse")
	g.env.ForeverRingsDB.vibration = false
	g.Press("PADRSTICKUP", true)
	g.Update()
	Eq(g.vibrations, 2, "off means off")
end)

Test("ring pops open and settles", function()
	local g = Login()
	g.Slash("bind food F")
	g.Press("F", true)
	local frame = g.ns.display.frame
	assert(frame.alpha < 0.2, "starts faded: " .. tostring(frame.alpha))
	for _ = 1, 20 do
		g.Update()
	end
	Eq(frame.alpha, 1, "fully visible")
	g.Press("PADRSTICKUP", true)
	for _ = 1, 30 do
		g.Update()
	end
	assert(math.abs(g.ns.display.slots[1].scale - 1.2) < 0.01, "selected slot grew")
	Eq(g.ns.display.pointer:IsShown(), true, "pointer visible")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
