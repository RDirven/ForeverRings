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

Test("an untouched old default Main gets Quest and Markers; a custom Main is kept", function()
	local old = { rings = { main = { label = "Main", slots = { { ring = "food" }, { ring = "mount" }, { ring = "bag" }, { ring = "tools" } } }, tools = { label = "Tools", slots = {} } } }
	Eq(#Ring(Login(nil, old), "main"), 8, "upgraded")
	local v040 = { rings = { main = { label = "Main", slots = { { ring = "food" }, { ring = "mount" }, { ring = "bag" }, { ring = "quest" }, { ring = "markers" }, { ring = "tools" } } }, tools = { label = "Tools", slots = {} } } }
	Eq(#Ring(Login(nil, v040), "main"), 8, "0.4.0 default upgraded too")
	local v050 = { rings = { main = { label = "Main", slots = { { ring = "food" }, { ring = "mount" }, { ring = "bag" }, { ring = "quest" }, { ring = "markers" }, { ring = "tools" }, { settings = true } } }, tools = { label = "Tools", slots = {} } } }
	Eq(Ring(Login(nil, v050), "main")[7], "menu", "0.5 default gets the Menu ring")
	local custom = { rings = { main = { label = "Main", slots = { { ring = "food" }, { ring = "tools" } } }, tools = { label = "Tools", slots = {} } } }
	Eq(#Ring(Login(nil, custom), "main"), 2, "kept")
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

Test("bag ring: usable items only, no gear, no food, no quest items, toys as toys", function()
	local g = Login()
	local bag = Ring(g, "bag")
	Eq(#bag, 3, "usable count")
	Eq(bag[1], "item:201", "potion")
	Eq(bag[2], "item:6948", "hearthstone")
	Eq(bag[3], 301, "toy value is the item ID")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:bag:t3"), "toy", "toy type")
end)

Test("quest ring: usable quest items", function()
	local quest = Ring(Login(), "quest")
	Eq(#quest, 1, "one quest item")
	Eq(quest[1], "item:202", "strange orb")
end)

Test("markers ring: skull first, all eight; the middle clears", function()
	local g = Login()
	local markers = Ring(g, "markers")
	Eq(#markers, 8, "eight markers")
	Eq(markers[1], 8, "skull first")
	Eq(markers[8], 1, "star last")
	Eq(g.ns.resolved.markers[1].type, "raidtarget", "secure raid mark, no macro")
	Eq(g.ns.resolved.markers[1].name, "Skull", "name")
	Has(g.ns.resolved.markers[1].icon, "UI-RaidTargetingIcon_8", "icon")
	g.Slash("bind markers X")
	g.Press("X", true)
	g.Press("PADRSTICKUP", true)
	g.Press("X", false)
	Eq(g.marks.target, 8, "marked skull")
	Eq(g.casts[1].type, "raidtarget", "secure raidtarget action")
	g.Press("PADRSTICKUP", false)
	g.Press("X", true)
	g.Update()
	Has(g.ns.display.title:GetText(), "Middle: Clear", "the middle is Clear")
	g.Press("X", false)                     -- tap without aiming: the middle
	Eq(g.marks.target, nil, "cleared")
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
	Eq(h:GetAttribute("r:main:n"), 8, "eight slots")
	Eq(h:GetAttribute("r:main:v7"), "menu", "menu ring")
	Eq(h:GetAttribute("r:main:v8"), "settings", "settings slot last")
	Eq(h:GetAttribute("r:main:v5"), "markers", "markers in main")
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
	assert(display.slots[1].halo:GetAlpha() > 0.5, "clean highlight")
	Eq(display.slots[2].halo:GetAlpha(), 0, "others not highlighted")

	g.Press("PADLSHOULDER", false)
	Eq(h:IsShown(), true, "food stays open")
	Eq(h:GetAttribute("active"), "food", "in food ring")
	Eq(#display.slices, 3, "food slots drawn")
	Has(display.hint:GetText(), "right-click back", "hint")

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
	Eq(h:GetAttribute("active"), "markers", "down = markers ring")
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
	Eq(g.marks.target, 8, "marker in combat")
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
	g.Slash("remove main 7")
	Has(g.Slash("add main ring:portals"), "Added Ring: Portals")
	Eq(Ring(g, "main")[8], "portals", "in main ring")
	Eq(g.ns.resolved.main[8].icon, 4001, "own ring: icon of its first action")
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
	g.Slash("remove main 7")
	g.Slash("add main ring:portals")
	Has(g.Slash("list portals"), "2. Arcane Intellect", "list")
	Has(g.Slash("remove portals 1"), "Removed Portal: Darnassus")
	Eq(Ring(g, "portals")[1], 1459, "shifted up")
	Has(g.Slash("delete portals"), "Deleted 'portals'")
	Eq(#Ring(g, "main"), 7, "removed from main too")
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
	Eq(g.ns.display.track.vertex[2], 0.82, "gold track")
	Eq(slot.rim:IsShown(), false, "no clean rim")
end)

-- Cooldowns and usability -----------------------------------------------------

Test("slots show cooldowns and dim what you can't use", function()
	local world = World()
	world.cooldowns = { [458] = { 100, 30 } }
	world.unusable = { [201] = "power", [6948] = true }
	local g = Login(world)
	g.Slash("bind mount M")
	g.Press("M", true)
	local cd = g.ns.display.slots[1].cooldown.cd
	Eq(cd and cd[2], 30, "mount on cooldown")
	g.Press("M", false)
	g.Slash("bind bag B")
	g.Press("B", true)
	local slots = g.ns.display.slots
	Eq(slots[1].icon.vertex[3], 1, "potion: not enough power is blue")
	Eq(slots[1].icon.vertex[1], 0.45, "potion tint")
	Eq(slots[2].icon.vertex[1], 0.4, "hearthstone unusable is dark")
	Eq(slots[3].icon.vertex[1], 1, "toy usable")
	world.unusable[6948] = nil
	for _ = 1, 15 do
		g.Update()
	end
	Eq(slots[2].icon.vertex[1], 1, "updates while open")
end)

-- Sharing ---------------------------------------------------------------------

Test("export a ring as a share code in a copy box", function()
	local g = Login()
	g.Slash("new Portals")
	g.Slash("add portals |Hspell:3565|h")
	g.Slash("add portals 6948")
	g.Slash("add portals ring:food")
	g.Slash("export portals")
	local box = g.env.ForeverRingsCopyBox
	Eq(box:IsShown(), true, "copy box shown")
	Eq(box.edit:GetText(), "FR1:Portals:s3565,i6948,rfood", "code")
	Eq(box.edit.highlighted, true, "selected for Ctrl+C")
	Has(g.Slash("export food"), "nothing to share", "auto rings can't be exported")
	g.Slash("add portals ring:food")
	g.env.ForeverRingsDB.rings.portals.slots[5] = { macro = "Mine" }
	g.env.ForeverRingsDB.rings.portals.slots[6] = { settings = true }
	g.Slash("export portals")
	Eq(g.env.ForeverRingsCopyBox.edit:GetText(), "FR1:Portals:s3565,i6948,rfood,rfood,o", "macros skipped, settings kept")
end)

Test("import a share code from a friend", function()
	local g = Login()
	local msg = g.Slash("import FR1:Portals:s3565,i6948,rfood")
	Has(msg, "Imported 'Portals'", "imported")
	Has(msg, "/frings add main ring:portals", "next step")
	local slots = g.env.ForeverRingsDB.rings.portals.slots
	Eq(#slots, 3, "three slots")
	Eq(slots[1].kind, "spell", "spell")
	Eq(slots[3].ring, "food", "sub-ring")
	Eq(Ring(g, "portals")[2], "item:6948", "live in the secure ring")
end)

Test("import keeps existing rings and skips sub-rings you don't have", function()
	local g = Login()
	g.Slash("new portals")
	local msg = g.Slash("import FR1:Portals:s3565,rnotmine,i6948")
	Has(msg, "Imported 'Portals 2'", "renamed")
	Has(msg, "Skipped 1 slot", "skipped unknown ring")
	Eq(#g.env.ForeverRingsDB.rings.portals2.slots, 2, "two slots")
	Eq(#g.env.ForeverRingsDB.rings.portals.slots, 0, "original untouched")
end)

Test("import round-trips and refuses junk", function()
	local g = Login()
	g.Slash("import FR1:Mix:s3565,i6948,s1459")
	g.Slash("export mix")
	Eq(g.env.ForeverRingsCopyBox.edit:GetText(), "FR1:Mix:s3565,i6948,s1459", "same code back")
	Has(g.Slash("import hello"), "doesn't look like", "junk")
	Has(g.Slash("import FR1:Too:" .. string.rep("s1,", 12)), "Skipped 4", "capped at 8")
	g.SetCombat(true)
	Has(g.Slash("import FR1:X:s1"), "in combat", "not in combat")
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
	g.ns.SetReleasePick(false)
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
	assert(math.abs(g.ns.display.slots[1].scale - 1.22) < 0.01, "selected slot grew")
	assert(g.ns.display.slots[2].alpha < 0.7, "others step back")
	Eq(g.ns.display.track.rotation, 0, "track turned into place")
	Eq(g.ns.display.pointer:IsShown(), true, "pointer visible")
end)

Test("selection ripples and using something flashes its icon", function()
	local g = Login()
	g.Slash("bind mount M")
	g.Press("M", true)
	for _ = 1, 20 do g.Update() end
	g.Press("PADRSTICKUP", true)
	g.Update()
	local slot = g.ns.display.slots[1]
	assert(slot.ping:GetAlpha() > 0.5, "ping starts")
	for _ = 1, 30 do g.Update() end
	Eq(slot.ping:GetAlpha(), 0, "ping fades")
	g.Press("M", false)
	local flash = g.ns.display.flash
	Eq(flash:IsShown(), true, "flash after use")
	Eq(flash.icon:GetTexture(), 5001, "with the mount icon")
	for _ = 1, 30 do g.Update() end
	Eq(flash:IsShown(), false, "flash gone")
end)

Test("cancelling doesn't flash", function()
	local g = Login()
	g.Slash("bind mount M")
	g.Press("M", true)
	g.Update()
	g.Press("M", false)
	Eq(g.ns.display.flash:IsShown(), false, "no flash")
end)

Test("aiming with a stick turns on the client's stick direction buttons", function()
	local g = WoW.New({}).Login()
	Eq(g.cvars.GamePadStickAxisButtons, "1", "on")
end)

Test("the stick still aims with a modifier held (R2 as Ctrl)", function()
	local g = Login()
	g.Slash("bind food F")
	g.Press("F", true)
	g.Press("CTRL-PADRSTICKUP", true)
	g.Press("CTRL-PADRSTICKUP", false)
	Eq(#g.casts, 1, "picked with Ctrl held")
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "closed")
end)

Test("opening a ring turns the stick direction buttons back on", function()
	local g = Login()
	g.cvars.GamePadStickAxisButtons = "0"
	for _, fn in ipairs(g.env.ForeverRingsHeader.hooks.OnShow) do
		fn(g.env.ForeverRingsHeader)
	end
	Eq(g.cvars.GamePadStickAxisButtons, "1", "back on")
end)

Test("letting go of the stick uses the slot it pointed at", function()
	local g = Login()
	g.Slash("bind food F")
	g.Press("F", true)
	g.Press("PADRSTICKUP", true)
	g.Press("PADRSTICKUP", false)
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "closed")
	Eq(#g.casts, 1, "used")
	g.Press("F", false)
	Eq(#g.casts, 1, "ring button release adds nothing")
end)

Test("the camera holds still while a ring is open, and gets its speed back", function()
	local g = WoW.New(World()).Login()
	g.cvars.GamePadCameraYawSpeed, g.cvars.GamePadCameraPitchSpeed = "1.5", "1"
	g.Slash("bind food F")
	g.Press("F", true)
	g.ns.display.frame.scripts.OnShow(g.ns.display.frame)
	Eq(g.cvars.GamePadCameraYawSpeed, "0", "frozen")
	Eq(g.freelook, false, "free look off")
	local eater
	for _, f in ipairs(g.frames) do
		if f.sticks ~= nil then eater = f end
	end
	Eq(eater and eater.sticks, true, "a frame takes the sticks")
	g.Press("F", false)
	g.ns.display.frame.scripts.OnHide(g.ns.display.frame)
	Eq(g.cvars.GamePadCameraYawSpeed, "1.5", "yaw back")
	Eq(g.cvars.GamePadCameraPitchSpeed, "1", "pitch back")
	Eq(g.freelook, true, "free look back")
	Eq(eater.sticks, false, "sticks given back")
	g.ns.SetHoldCamera(false)
	g.Press("F", true)
	g.ns.display.frame.scripts.OnShow(g.ns.display.frame)
	Eq(g.freelook, true, "setting off: camera left alone")
end)

Test("Menu ring: the game panels this client has", function()
	local world = World()
	local g = WoW.New(world)
	g.env.CharacterMicroButton = g.env.CreateFrame("Button", "CharacterMicroButton", g.env.UIParent)
	g.env.ToggleAllBags = function() end
	g.Login()
	local menu = g.ns.resolved.menu
	Eq(menu[1].name, "Character", "character first")
	Eq(menu[2].name, "Bags", "bags")
	Eq(#menu, 2, "only what exists")
	Eq(menu[1].type, "click", "a secure click")
	Eq(menu[1].value, "menu:character", "by name")
	Eq(g.env.ForeverRingsTrigger_main.attrs["clickbutton-menu:character"], g.env.CharacterMicroButton, "ring buttons know which button that is")
	Eq(g.env.ForeverRingsMouse.attrs["clickbutton-menu:character"], g.env.CharacterMicroButton, "the mouse button too")
	Eq(menu[2].type, "run", "bags have no button: the addon opens them")
	g.Slash("new panels")
	g.ns.SetSlot("panels", 1, { menu = "bags" })
	Eq(g.ns.resolved.panels[1].value, "menu:bags", "menus go in your own rings")
	Has(g.ns.ExportRing("panels"), "mbags", "and share")
end)

Test("Reset Main puts the default back", function()
	local g = Login()
	g.Slash("remove main 8")
	g.Slash("remove main 1")
	Eq(#Ring(g, "main"), 6, "trimmed")
	Eq(g.ns.ResetMain(), true, "reset")
	Eq(#Ring(g, "main"), 8, "all back")
	Eq(Ring(g, "main")[8], "settings", "settings too")
end)

Test("from an action bar button: second press opens a menu (no macro inside a macro)", function()
	local g = WoW.New(World())
	local opened = 0
	g.env.ToggleAllBags = function() opened = opened + 1 end
	g.Login()
	g.Slash("new panels")
	g.ns.SetSlot("panels", 1, { menu = "bags" })
	g.ns.SetReleasePick(false)
	local trigger = g.env.ForeverRingsTrigger_panels
	g.ClickButton(trigger, true)            -- the action bar macro: /click ... LeftButton 1
	g.Press("PADRSTICKUP", true)
	g.ClickButton(trigger, true)            -- same button again
	Eq(opened, 1, "bags opened")
	Eq(#g.casts, 0, "no macro involved")
end)

Test("Character from a ring: a secure click on the micro button, no taint", function()
	local g = WoW.New(World())
	g.env.CharacterMicroButton = g.env.CreateFrame("Button", "CharacterMicroButton", g.env.UIParent)
	g.Login()
	g.Slash("bind menu M")
	g.Press("M", true)
	g.Press("PADRSTICKUP", true)
	g.Press("PADRSTICKUP", false)
	Eq(g.casts[1] and g.casts[1].type, "click", "secure click")
	Eq(g.env.CharacterMicroButton.clicked, 1, "character opened")
end)

-- Party ring ------------------------------------------------------------------

local function GroupWorld()
	local world = World()
	world.spells[2061] = { name = "Flash Heal", icon = 6001 }
	world.group = {
		player = { name = "Me", class = "PRIEST", health = 100, max = 100 },
		party1 = { name = "Tank", class = "WARRIOR", health = 30, max = 100 },
		party2 = { name = "Zap", class = "MAGE", health = 90, max = 100, inRange = false },
		party3 = { name = "Stab", class = "ROGUE", health = 0, max = 100, dead = true },
	}
	return world
end

Test("Party ring: you on top, then your group; without a spell it targets", function()
	local g = Login(GroupWorld())
	local h = g.env.ForeverRingsHeader
	local party = Ring(g, "party")
	Eq(#party, 4, "you plus three")
	Eq(party[1], "player", "you first")
	Eq(h:GetAttribute("r:party:t2"), "target", "targets")
	Eq(h:GetAttribute("r:party:u2"), "party1", "unit")
	Eq(g.ns.resolved.party[2].name, "Tank", "name")
	Has(g.ns.resolved.party[2].icon, "ClassIcon_Warrior", "class icon")
	g.Slash("bind party P")
	g.Press("P", true)
	g.Press("PADRSTICKRIGHT", true)
	g.Press("P", false)
	Eq(g.casts[1].type, "target", "targeted")
	Eq(g.casts[1].unit, "party1", "the tank")
end)

Test("Party spell: the heal lands on whoever you aim at, in combat too", function()
	local g = Login(GroupWorld())
	Eq(g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 }), true, "spell set")
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:party:t3"), "spell", "casts")
	Eq(h:GetAttribute("r:party:v3"), 2061, "Flash Heal")
	Eq(h:GetAttribute("r:party:u3"), "party2", "on party2")
	g.Slash("bind party P")
	g.SetCombat(true)
	g.Press("P", true)
	g.Press("PADRSTICKRIGHT", true)
	g.Update()
	Has(g.ns.display.title:GetText(), "Tank", "who")
	Has(g.ns.display.title:GetText(), "Flash Heal", "what")
	g.Press("P", false)
	g.Press("PADRSTICKRIGHT", false)
	Eq(g.casts[1].value, 2061, "heal")
	Eq(g.casts[1].unit, "party1", "on the tank")
	g.Press("P", true)
	g.Press("P", false)
	Eq(g.casts[2] and g.casts[2].unit, "party1", "tap heals the tank again")
	g.SetCombat(false)
	local spell = g.ns.RemoveSlot("party", 1)
	Eq(spell and spell.id, 2061, "cleared")
	Eq(h:GetAttribute("r:party:t1"), "target", "back to targeting")
	Has(select(2, g.ns.SetSlot("party", 1, { kind = "item", id = 6948 })), "pick one from Spells", "only spells")
end)

Test("Party ring shows health, the lowest pulses red, range and death dim", function()
	local world = GroupWorld()
	local g = Login(world)
	g.Slash("bind party P")
	g.Press("P", true)
	for _ = 1, 20 do g.Update() end
	local slots = g.ns.display.slots
	-- Rings lit from the crust inward: a band is full when value reaches its max.
	local function Lit(slot)
		local n = 0
		for _, band in ipairs(slot.bands) do
			if band.value >= band.max then n = n + 1 end
		end
		return n
	end
	Eq(#slots[2].bands, 12, "twelve health rings")
	Eq(Lit(slots[2]), 4, "tank at 30%: the four outer rings")
	Eq(slots[2].bands[1].value >= slots[2].bands[1].max, true, "the crust is lit")
	Eq(slots[2].bands[12].value >= slots[2].bands[12].max, false, "the centre is empty")
	Eq(Lit(slots[1]), 12, "you at full: every ring")
	Eq(slots[2].label:GetText(), "Tank", "name under the slot")
	Eq(slots[2].label.textColor[1], 0.78, "in class colour")
	local wedges = g.ns.display.wedges
	assert(wedges[2].bg.vertex[1] > 0.1 and wedges[2].bg.vertex[2] < 0.1, "lowest: the slice pulses red")
	Eq(slots[3].outOfRange, true, "mage out of range")
	assert(slots[3].alpha < 0.5, "out of range fades")
	Eq(slots[4].icon.desaturated, true, "dead is grey")
	world.group.party1.health = 100
	world.group.party2.health = 50
	g.Update()
	assert(wedges[3].bg.vertex[1] > 0.1 and wedges[3].bg.vertex[2] < 0.1, "now the mage is lowest")
	Eq(Lit(slots[3]), 6, "mage at 50%: six rings")
end)

Test("secret health values still fill the bar but nobody is called lowest", function()
	local world = GroupWorld()
	local g = Login(world)
	local secret = setmetatable({}, { __lt = function() error("secret") end, __div = function() error("secret") end })
	world.group.party1.health = secret
	g.env.issecretvalue = function(v) return v == secret end
	g.env.UnitHealthPercent = function(unit) return unit == "party1" and secret or 1 end
	g.Slash("bind party P")
	g.Press("P", true)
	g.Update()
	local slots = g.ns.display.slots
	Eq(slots[2].bands[1].value, secret, "secret percent passed straight to the rings")
	local bg = g.ns.display.wedges[2].bg.vertex
	Eq(bg[1], 0.05, "slice not red: can't compare")
end)

Test("joining a group refreshes the ring, but only after combat", function()
	local world = GroupWorld()
	local g = Login(world)
	g.SetCombat(true)
	world.group.party4 = { name = "Late", class = "MAGE", health = 100, max = 100 }
	g.Fire("GROUP_ROSTER_UPDATE")
	g.RunTimers()
	Eq(#Ring(g, "party"), 4, "unchanged in combat")
	g.SetCombat(false)
	Eq(#Ring(g, "party"), 5, "added after combat")
end)

Test("spell per button: release, A, X and Y each heal the aimed member", function()
	local world = GroupWorld()
	world.spells[2050] = { name = "Lesser Heal", icon = 6002 }
	world.spells[2060] = { name = "Greater Heal", icon = 6003 }
	world.spells[139] = { name = "Renew", icon = 6004 }
	local g = Login(world)
	g.ns.SetPartyHeals("buttons")
	g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 })
	g.ns.SetSlot("party", 2, { kind = "spell", id = 2050 })
	g.ns.SetSlot("party", 3, { kind = "spell", id = 2060 })
	g.ns.SetSlot("party", 4, { kind = "spell", id = 139 })
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:party:btn-x"), 2060, "X spell pushed")
	g.Slash("bind party P")
	local function AimAtTank(press)
		g.Press("P", true)
		g.Press("PADRSTICKRIGHT", true)
		g.Update()
		press()
		g.Press("PADRSTICKRIGHT", false)
		g.Press("P", false)
	end
	AimAtTank(function() Has(g.ns.display.hint:GetText(), "X Greater Heal", "hint names the X heal") g.Press("PAD3", true) end)
	Eq(g.casts[1].value, 2060, "X = Greater Heal")
	Eq(g.casts[1].unit, "party1", "on the tank")
	AimAtTank(function() g.Press("PAD4", true) end)
	Eq(g.casts[2].value, 139, "Y = Renew")
	AimAtTank(function() g.Press("PAD1", true) end)
	Eq(g.casts[3].value, 2050, "A = Lesser Heal")
	Eq(g.casts[3].unit, "party1", "on the tank")
	AimAtTank(function() end)
	Eq(g.casts[4].value, 2061, "release = Flash Heal")
	g.Press("P", true)
	g.Press("P", false)
	Eq(g.casts[5].value, 2061, "tap repeats the last heal")
	Eq(g.casts[5].unit, "party1", "on the same member")
	g.ns.SetPartyHeals("one")
	Eq(h:GetAttribute("r:party:btn-x"), nil, "one spell: X does nothing")
	AimAtTank(function() g.Press("PAD3", true) end)
	Eq(g.casts[6].value, 2061, "only the release heal")
end)

Test("X and Y do nothing on rings without button spells", function()
	local g = Login()
	g.Slash("bind food F")
	g.Press("F", true)
	g.Press("PADRSTICKUP", true)
	g.Press("PAD3", true)
	g.Press("PAD4", true)
	Eq(#g.casts, 0, "nothing cast")
	Eq(g.env.ForeverRingsHeader:IsShown(), true, "ring still open")
end)

Test("by role: you on top, tank right, DPS below, healer left; empty places stay put", function()
	local world = GroupWorld()
	world.group.party1.role = "DAMAGER"
	world.group.party2.role = "TANK"
	world.group.party3.role = "HEALER"
	world.group.party3.dead = nil
	local g = Login(world)
	g.ns.SetPartyOrder("role")
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:party:n"), 5, "always five places")
	Eq(h:GetAttribute("r:party:u1"), "player", "you on top")
	Eq(h:GetAttribute("r:party:u2"), "party2", "tank right")
	Eq(h:GetAttribute("r:party:u3"), "party1", "DPS below")
	Eq(h:GetAttribute("r:party:t4"), nil, "empty place does nothing")
	Eq(h:GetAttribute("r:party:u5"), "party3", "healer left")
	Eq(g.ns.resolved.party[4].empty, true, "marked empty")
	world.group.party1, world.group.party3 = nil, nil
	g.Fire("GROUP_ROSTER_UPDATE")
	g.RunTimers()
	Eq(h:GetAttribute("r:party:n"), 5, "still five")
	Eq(h:GetAttribute("r:party:u2"), "party2", "tank stays right")
	g.ns.SetPartyOrder("group")
	Eq(h:GetAttribute("r:party:n"), 2, "group order: just who's there")
end)

Test("by role: a main tank assignment counts as tank", function()
	local world = GroupWorld()
	world.group.party2.mainTank = true
	local g = Login(world)
	g.ns.SetPartyOrder("role")
	Eq(g.env.ForeverRingsHeader:GetAttribute("r:party:u2"), "party2", "main tank right")
end)

Test("in a raid: you plus your own subgroup, as raid units", function()
	local world = GroupWorld()
	world.group = {
		player = { name = "Me", class = "PRIEST", health = 100, max = 100 },
		raid1 = { name = "Other", class = "MAGE", health = 100, max = 100 },
		raid2 = { name = "Tank", class = "WARRIOR", health = 100, max = 100 },
	}
	world.group.raid3 = world.group.player
	world.raid = { { name = "Other", subgroup = 1 }, { name = "Tank", subgroup = 2 }, { name = "Me", subgroup = 2 } }
	local party = Ring(Login(world), "party")
	Eq(#party, 2, "you and your group mate")
	Eq(party[1], "player", "you")
	Eq(party[2], "raid2", "group 2 tank, not group 1")
end)

Test("secret cooldowns in combat (retail) don't break the ring", function()
	local g = Login()
	g.env.issecretvalue = function(v) return v == "secret" end
	g.env.C_Spell.GetSpellCooldown = function() return { startTime = "secret", duration = "secret" } end
	g.Slash("new heals")
	g.ns.SetSlot("heals", 1, { kind = "spell", id = 3565 })
	g.Slash("bind heals H")
	g.Press("H", true)
	g.Update()
	g.ns.display:UpdateState()
	Eq(g.ns.display.slots[1].cooldown.cd, nil, "secret cooldown not handed to the Cooldown")
end)

Test("Hover cast: aim, A/B/X/Y and L2/R2 + them each heal; the ring stays open", function()
	local world = GroupWorld()
	world.spells[139] = { name = "Renew", icon = 6002 }
	world.spells[2060] = { name = "Greater Heal", icon = 6003 }
	world.spells[17] = { name = "Power Word: Shield", icon = 6004 }
	local g = Login(world)
	g.ns.SetPartyHeals("hover")
	Eq(g.ns.PartySpellCount(), 12, "twelve buttons")
	g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 })   -- A
	g.ns.SetSlot("party", 2, { kind = "spell", id = 17 })     -- B
	g.ns.SetSlot("party", 5, { kind = "spell", id = 139 })    -- L2 + A
	g.ns.SetSlot("party", 9, { kind = "spell", id = 2060 })   -- R2 + A
	local h = g.env.ForeverRingsHeader
	g.ns.SetPartyOpen("hold")
	g.Slash("bind party P")
	g.Press("P", true)                      -- held from here on
	g.Press("PADRSTICKRIGHT", true)
	g.Press("PADRSTICKRIGHT", false)
	Eq(#g.casts, 0, "letting go of the stick doesn't cast")
	g.Press("PAD1", true)
	Eq(g.casts[1].value, 2061, "A: Flash Heal")
	Eq(g.casts[1].unit, "party1", "on the tank")
	Eq(h:IsShown(), true, "still open")
	g.Press("PAD2", true)
	Eq(g.casts[2].value, 17, "B: Shield, not back")
	g.Press("PADLTRIGGER", true)
	g.Press("PAD1", true)
	Eq(g.casts[3].value, 139, "L2 + A: Renew")
	g.Press("PADLTRIGGER", false)
	g.Press("PADRTRIGGER", true)
	g.Press("PAD1", true)
	Eq(g.casts[4].value, 2060, "R2 + A: Greater Heal")
	g.Press("PADRTRIGGER", false)
	g.Press("PAD3", true)
	Eq(#g.casts, 4, "X without a spell does nothing")
	Eq(h:IsShown(), true, "and keeps the ring open")
	g.Press("P", false)
	Eq(h:IsShown(), false, "letting go closes it")
end)

Test("Hover cast, Tap: a heal casts and closes the ring", function()
	local g = Login(GroupWorld())
	g.ns.SetPartyHeals("hover")
	g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 })
	local h = g.env.ForeverRingsHeader
	g.Slash("bind party P")
	g.Press("P", true)
	g.Press("P", false)
	Eq(h:IsShown(), true, "a tap opens it")
	g.Press("PADRSTICKRIGHT", true)
	g.Press("PAD1", true)
	Eq(g.casts[1].value, 2061, "healed")
	Eq(h:IsShown(), false, "and closed")
end)

Test("Hover cast with L2 as an emulated modifier (Alt): ALT-PAD1 is L2 + A", function()
	local world = GroupWorld()
	world.spells[139] = { name = "Renew", icon = 6002 }
	local g = WoW.New(world)
	g.cvars.GamePadEmulateAlt = "PADLTRIGGER"
	g.Login()
	g.ns.SetPartyHeals("hover")
	g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 })
	g.ns.SetSlot("party", 5, { kind = "spell", id = 139 })
	g.Slash("bind party P")
	g.Press("P", true)
	g.Press("PADRSTICKRIGHT", true)
	g.Press("ALT-PAD1", true)
	Eq(g.casts[1] and g.casts[1].value, 139, "Renew")
	g.Press("P", true)                      -- Tap closed it: open again
	g.Press("PADRSTICKRIGHT", true)
	g.Press("PAD1", true)
	Eq(g.casts[2] and g.casts[2].value, 2061, "plain A: Flash Heal")
end)

Test("Ring opacity: everything see-through except the slot you aim at", function()
	local g = Login()
	g.ns.SetOpacity(0.2)
	g.Slash("bind main F")
	g.Press("F", true)
	for _ = 1, 30 do g.Update() end
	local d = g.ns.display
	Eq(d.backdrop.alpha, 0.2, "backdrop")
	assert(d.slots[1].alpha <= 0.2 + 1e-6, "slots at 20% with nothing aimed")
	g.Press("PADRSTICKUP", true)
	for _ = 1, 30 do g.Update() end
	assert(d.slots[1].alpha > 0.9, "the aimed slot stays solid")
	assert(d.slots[3].alpha < 0.2, "the rest fades")
end)

Test("Hover cast takes the action bar's spells when you haven't picked any", function()
	local world = GroupWorld()
	local g = WoW.New(world)
	g.cvars.GamePadEmulateAlt = "PADLTRIGGER"
	g.bindings.PAD1 = "ACTIONBUTTON1"
	g.bindings["ALT-PAD1"] = "MULTIACTIONBAR1BUTTON2"
	g.Login()
	g.env.CreateFrame("CheckButton", "MultiBarBottomLeftButton2", g.env.UIParent).action = 62
	g.actions[1] = { "spell", 2061 }
	g.actions[62] = { "spell", 139 }
	g.ns.SetPartyHeals("hover")
	local h = g.env.ForeverRingsHeader
	Eq(h:GetAttribute("r:party:btn-a"), 1, "A: action slot 1")
	Eq(h:GetAttribute("r:party:btnk-a"), "action", "as an action")
	Eq(h:GetAttribute("r:party:btn-l-a"), 62, "L2 + A: the Alt binding's slot")
	g.Slash("bind party P")
	g.Press("P", true)
	g.Press("PADRSTICKRIGHT", true)
	g.Press("PAD1", true)
	Eq(g.casts[1].type, "action", "uses the action bar button")
	Eq(g.casts[1].value, 1, "slot 1")
	Eq(g.casts[1].unit, "party1", "on the tank")
	g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 })
	Eq(h:GetAttribute("r:party:btnk-a"), nil, "an own spell wins")
end)

Test("Hover cast, Hold: letting go of the ring button closes it", function()
	local g = Login(GroupWorld())
	g.ns.SetPartyHeals("hover")
	g.ns.SetPartyOpen("hold")
	g.Slash("bind party P")
	g.Press("P", true)
	Eq(g.env.ForeverRingsHeader:IsShown(), true, "open while held")
	g.Press("P", false)
	Eq(g.env.ForeverRingsHeader:IsShown(), false, "closed on release")
end)

Test("Party ring: dispellable debuffs under the name, no circles", function()
	local world = GroupWorld()
	local g = WoW.New(world)
	g.env.C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
		if unit == "party1" and index == 1 and filter == "HARMFUL|RAID" then
			return { icon = 136066 }
		end
	end }
	g.Login()
	g.Slash("bind party P")
	g.Press("P", true)
	for _ = 1, 5 do g.Update() end
	local slots = g.ns.display.slots
	Eq(slots[2].debuffs[1]:IsShown(), true, "the tank's debuff")
	Eq(slots[2].debuffs[1]:GetTexture(), 136066, "its icon")
	Eq(slots[2].debuffs[2]:IsShown(), false, "just one")
	Eq(slots[1].debuffs[1]:IsShown(), false, "you have none")
	Eq(slots[2].rim:IsShown(), false, "no circle around the name")
end)

Test("Party ring: your HoT shows a green circle and its icon", function()
	local world = GroupWorld()
	local g = WoW.New(world)
	g.env.C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
		if unit == "party1" and index == 1 and filter == "HELPFUL|PLAYER" then
			return { icon = 135953 }
		end
	end }
	g.Login()
	g.Slash("bind party P")
	g.Press("P", true)
	for _ = 1, 5 do g.Update() end
	local slots = g.ns.display.slots
	Eq(slots[2].rim:IsShown(), true, "circle on the tank")
	Eq(slots[2].rim.vertex[2], 1, "green")
	Eq(slots[2].hots[1]:GetTexture(), 135953, "the HoT's icon")
	Eq(slots[1].rim:IsShown(), false, "no HoT on you")
	Eq(slots[2].cooldown:IsShown(), false, "no cooldown swipe on people")
end)

Test("Your buffs: long ones (Blessing of the Bronze) and hidden ones don't show", function()
	local world = GroupWorld()
	local g = WoW.New(world)
	local auras = {
		{ name = "Blessing of the Bronze", icon = 1, duration = 3600 },
		{ name = "Reversion", icon = 2, duration = 12 },
		{ name = "Echo", icon = 3, duration = 15 },
	}
	g.env.C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
		if unit == "party1" and filter == "HELPFUL|PLAYER" then return auras[index] end
	end }
	g.Login()
	g.Slash("bind party P")
	g.Press("P", true)
	for _ = 1, 5 do g.Update() end
	local hots = g.ns.display.slots[2].hots
	Eq(hots[1]:GetTexture(), 2, "Reversion first: Bronze is skipped")
	Eq(hots[2]:GetTexture(), 3, "then Echo")
	g.Slash("hidebuff echo")
	g.ns.display.auraAge = 1
	g.Update()
	Eq(hots[2]:IsShown(), false, "Echo hidden")
	g.ns.SetPartyBuffs("all")
	g.ns.display.auraAge = 1
	g.Update()
	Eq(hots[1]:GetTexture(), 1, "All: Bronze shows")
end)

Test("Hover cast, Toggle: stays open after a heal, the button closes it", function()
	local g = Login(GroupWorld())
	g.ns.SetPartyHeals("hover")
	g.ns.SetPartyOpen("toggle")
	g.ns.SetSlot("party", 1, { kind = "spell", id = 2061 })
	local h = g.env.ForeverRingsHeader
	g.Slash("bind party P")
	g.Press("P", true)
	g.Press("P", false)
	g.Press("PADRSTICKRIGHT", true)
	g.Press("PAD1", true)
	Eq(g.casts[1].value, 2061, "healed")
	Eq(h:IsShown(), true, "still open")
	g.Press("P", true)
	Eq(h:IsShown(), false, "pressed again: closed")
end)

Test("Health fills from the centre: other ring textures", function()
	local g = Login(GroupWorld())
	g.ns.SetPartyFill("centre")
	g.Slash("bind party P")
	g.Press("P", true)
	Has(g.ns.display.slots[2].bands[1].ringMask:GetTexture(), "ringc1", "centre rings")
end)

-- Controller works only after /reload (bug report) ---------------------------

-- The fake client doesn't fire OnShow by itself; the camera hold (and with it
-- the stick reader) starts there.
local function Open(g, key)
	g.Press(key, true)
	g.ns.display.frame.scripts.OnShow(g.ns.display.frame)
end


Test("stick direction buttons not arriving: the stick itself still aims out of combat", function()
	local g = Login()
	g.Slash("bind mount M")
	Open(g, "M")
	-- No PADRSTICK* presses at all: only the raw stick reaches the addon.
	g.Stick("Right", 0, 0.9)
	g.Update()
	Eq(g.ns.display:SelectedSlice(), 1, "highlight follows the stick")
	g.Press("M", false)
	Eq(g.casts[1] and g.casts[1].value, 458, "release picks the aimed mount")
	Eq(g.ns.diag.dirPresses, 0, "no direction presses arrived")
	assert(g.ns.diag.fallbackAims > 0, "backup aimed")
end)

Test("letting go of the stick keeps the backup aim", function()
	local g = Login()
	g.Slash("bind food F")
	Open(g, "F")
	g.Stick("Right", 0.9, 0)
	g.Stick("Right", 0.05, 0)
	g.Press("F", false)
	Eq(g.casts[1] and g.casts[1].value, "item:102", "right = slot 2 of 3 kept after letting go")
end)

Test("the other stick and other rings' sticks are ignored", function()
	local g = Login()
	g.Slash("bind mount M")
	Open(g, "M")
	g.Stick("Left", 0, 1)
	Eq(g.env.ForeverRingsHeader:GetAttribute("aim-dx"), nil, "left stick doesn't aim")
end)

Test("in combat the backup stays out of secure state (no blocked actions)", function()
	local g = Login()
	g.Slash("bind mount M")
	g.SetCombat(true)
	Open(g, "M")
	g.Stick("Right", 0, 1)
	Eq(g.env.ForeverRingsHeader:GetAttribute("aim-dx"), nil, "not written in combat")
	Eq(g.ns.diag.stickEvents, 1, "but counted")
end)

Test("stick y is learned from a real direction press", function()
	local g = Login()
	g.Slash("bind mount M")
	Open(g, "M")
	g.Stick("Right", 0, -0.9)          -- this client reports up as negative
	g.Press("PADRSTICKUP", true)
	Eq(g.env.ForeverRingsDB.stickYSign, -1, "flipped")
	g.Press("PADRSTICKUP", false)
	g.Press("M", false)
	Open(g, "M")
	g.Stick("Right", 0, -0.9)
	Eq(g.env.ForeverRingsHeader:GetAttribute("aim-dy"), 0.9, "now aims up")
end)

Test("/frings debug explains what arrives", function()
	local g = Login()
	Has(g.Slash("debug"), "Open a ring", "nothing yet")
	g.Slash("bind mount M")
	Open(g, "M")
	g.Stick("Right", 0, 1)
	g.Press("M", false)
	Has(g.Slash("debug"), "direction buttons don't", "diagnosis")
	Open(g, "M")
	g.Press("PADRSTICKUP", true)
	g.Press("PADRSTICKUP", false)
	g.Press("M", false)
	Has(g.Slash("debug"), "both arrive", "all good")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
