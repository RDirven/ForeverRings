-- Runs the secure snippets against a mock restricted environment.
-- Usage: luajit tests/snippets_test.lua   (from the repo root)

local ns = {}
assert(loadfile("Snippets.lua"))("ForeverRings", ns)

local function Handle(attrs)
	local h = { attrs = attrs or {}, shown = false, bindings = {}, w = 1000, h = 600, mouse = { 0.5, 0.5 } }
	function h:GetAttribute(k) return self.attrs[k] end
	function h:SetAttribute(k, v) self.attrs[k] = v end
	function h:Show() self.shown = true end
	function h:Hide() self.shown = false end
	function h:IsShown() return self.shown end
	function h:GetWidth() return self.w end
	function h:GetHeight() return self.h end
	function h:GetMousePosition() return self.mouse[1], self.mouse[2] end
	function h:SetBindingClick(_, key, name) self.bindings[key] = name end
	function h:ClearBindings() self.bindings = {} end
	return h
end

local header, compiled = nil, {}
local function Run(name, self, down)
	if not compiled[name] then
		local fn, err = loadstring("local self, button, down = ...\n" .. ns.snippets[name], name)
		assert(fn, err)
		compiled[name] = fn
	end
	setfenv(compiled[name], { owner = header, math = math })
	return compiled[name](self, "LeftButton", down)
end

local function Ring(key, slices)
	header.attrs["r:" .. key .. ":n"] = #slices
	for i, s in ipairs(slices) do
		header.attrs["r:" .. key .. ":t" .. i] = s[1]
		header.attrs["r:" .. key .. ":v" .. i] = s[2]
	end
end

local function Setup()
	header = Handle({
		depth = 0,
		["key-up"] = "PADRSTICKUP", ["key-right"] = "PADRSTICKRIGHT",
		["key-down"] = "PADRSTICKDOWN", ["key-left"] = "PADRSTICKLEFT",
		["key-confirm"] = "PAD1", ["key-back"] = "PAD2",
	})
	Ring("main", { { "ring", "food" }, { "spell", 111 }, { "ring", "mount" }, { "item", "item:6948" } })
	Ring("food", {
		{ "item", "item:1" }, { "item", "item:2" }, { "item", "item:3" }, { "item", "item:4" },
		{ "item", "item:5" }, { "item", "item:6" }, { "item", "item:7" }, { "item", "item:8" },
	})
	Ring("mount", {})
end

local dirs = {}
local function Dir(d, down)
	dirs[d] = dirs[d] or Handle({ dir = d })
	Run("direction", dirs[d], down)
end

local passed, failed = 0, 0
local function Test(name, fn)
	Setup()
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
		error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
	end
end

-- 4-slice main ring: up=1 (food), right=2 (spell), down=3 (mount), left=4 (item)

Test("press opens ring and grabs gamepad keys", function()
	local t = Handle({ ring = "main" })
	Eq(Run("trigger", t, true), false, "down blocks click")
	Eq(header.shown, true, "shown")
	Eq(header.attrs.active, "main", "active")
	Eq(header.bindings.PADRSTICKUP, "ForeverRingsDir_up", "stick bound")
	Eq(header.bindings.PAD1, "ForeverRingsConfirm", "A bound")
end)

Test("release with stick right casts the spell", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Dir("right", true)
	Eq(Run("trigger", t, false), nil, "click proceeds")
	Eq(t.attrs.type, "spell", "type")
	Eq(t.attrs.typerelease, "spell", "typerelease")
	Eq(t.attrs.spell, 111, "spell value")
	Eq(header.shown, false, "closed")
	Eq(next(header.bindings), nil, "bindings cleared")
	Eq(header.attrs["held-right"], nil, "held reset")
end)

Test("release in the middle cancels", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Eq(Run("trigger", t, false), false, "blocked")
	Eq(t.attrs.type, nil, "no action")
	Eq(header.shown, false, "closed")
end)

Test("diagonal picks between directions on an 8-slice ring", function()
	local t = Handle({ ring = "food" })
	Run("trigger", t, true)
	Dir("up", true)
	Dir("right", true)
	Run("trigger", t, false)
	Eq(t.attrs.item, "item:2", "up-right = slice 2")
end)

Test("all 8 directions map to their own slice", function()
	local combos = {
		{ "up" }, { "up", "right" }, { "right" }, { "down", "right" },
		{ "down" }, { "down", "left" }, { "left" }, { "up", "left" },
	}
	for i, combo in ipairs(combos) do
		Setup()
		dirs = {}
		local t = Handle({ ring = "food" })
		Run("trigger", t, true)
		for _, d in ipairs(combo) do Dir(d, true) end
		Run("trigger", t, false)
		Eq(t.attrs.item, "item:" .. i, table.concat(combo, "+"))
	end
end)

Test("release on a sub-ring opens it and keeps it open", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Dir("up", true)
	Eq(Run("trigger", t, false), false, "no action")
	Eq(header.shown, true, "still open")
	Eq(header.attrs.active, "food", "sub-ring active")
	Eq(header.attrs.sticky, true, "sticky")
	Eq(header.attrs.depth, 1, "depth")
end)

Test("A in a sub-ring uses the item", function()
	local t = Handle({ ring = "main" })
	local a = Handle({})
	Run("trigger", t, true)
	Dir("up", true)
	Run("trigger", t, false)
	Dir("up", false)
	Dir("down", true)
	Eq(Run("confirm", a, true), nil, "click proceeds")
	Eq(a.attrs.item, "item:5", "down = slice 5")
	Eq(header.shown, false, "closed")
end)

Test("A with stick neutral keeps the ring open", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Eq(Run("confirm", Handle({}), true), false, "blocked")
	Eq(header.shown, true, "still open")
end)

Test("A on a sub-ring while holding the trigger, then release picks from it", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Dir("up", true)
	Run("confirm", Handle({}), true)
	Eq(header.attrs.active, "food", "entered food")
	Dir("up", false)
	Dir("left", true)
	Run("trigger", t, false)
	Eq(t.attrs.item, "item:7", "left = slice 7")
end)

Test("B goes back one level, then closes", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Dir("up", true)
	Run("trigger", t, false)
	Run("back", Handle({}), true)
	Eq(header.attrs.active, "main", "back to main")
	Eq(header.attrs.depth, 0, "depth 0")
	Run("back", Handle({}), true)
	Eq(header.shown, false, "closed")
end)

Test("mouse movement aims when the stick is neutral", function()
	local t = Handle({ ring = "main" })
	header.mouse = { 0.5, 0.5 }
	Run("trigger", t, true)
	header.mouse = { 0.5, 0.4 } -- 60px down
	Run("trigger", t, false)
	Eq(header.attrs.active, "mount", "down = mount sub-ring")
end)

Test("tiny mouse movement stays in the dead zone", function()
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	header.mouse = { 0.51, 0.5 } -- 10px
	Eq(Run("trigger", t, false), false, "cancelled")
	Eq(header.shown, false, "closed")
end)

Test("empty ring closes on release", function()
	local t = Handle({ ring = "mount" })
	Run("trigger", t, true)
	Dir("up", true)
	Eq(Run("trigger", t, false), false, "blocked")
	Eq(header.shown, false, "closed")
end)

Test("tap repeats the last action used from that ring", function()
	header.attrs["tap-repeat"] = true
	local t = Handle({ ring = "food" })
	Run("trigger", t, true)
	Dir("left", true)
	Run("trigger", t, false)
	Dir("left", false)
	Eq(t.attrs.item, "item:7", "first use")
	t.attrs.item = nil
	Run("trigger", t, true)
	Eq(Run("trigger", t, false), nil, "tap fires")
	Eq(t.attrs.item, "item:7", "repeated")
	Eq(header.shown, false, "closed")
end)

Test("touching the stick and returning to center cancels instead of repeating", function()
	header.attrs["tap-repeat"] = true
	header.attrs["last:food:t"], header.attrs["last:food:v"] = "item", "item:3"
	local t = Handle({ ring = "food" })
	Run("trigger", t, true)
	Dir("up", true)
	Dir("up", false)
	Eq(Run("trigger", t, false), false, "cancelled")
	Eq(t.attrs.type, nil, "nothing fired")
end)

Test("tap does nothing when the option is off", function()
	header.attrs["last:food:t"], header.attrs["last:food:v"] = "item", "item:3"
	local t = Handle({ ring = "food" })
	Run("trigger", t, true)
	Eq(Run("trigger", t, false), false, "cancelled")
end)

Test("actions from a sub-ring count as last used for the ring you opened", function()
	header.attrs["tap-repeat"] = true
	local t = Handle({ ring = "main" })
	Run("trigger", t, true)
	Dir("up", true)
	Run("trigger", t, false)        -- into food
	Dir("up", false)
	Dir("right", true)
	Run("confirm", Handle({}), true) -- food slice 3
	Eq(header.attrs["last:main:t"], "item", "stored under main")
	Eq(header.attrs["last:main:v"], "item:3", "value")
	Dir("right", false)
	Run("trigger", t, true)
	Run("trigger", t, false)
	Eq(t.attrs.item, "item:3", "tapping main repeats it")
end)

Test("macro slices load their text into macrotext", function()
	Ring("food", { { "macro", "/use item:1\n/use item:2" } })
	local t = Handle({ ring = "food" })
	Run("trigger", t, true)
	Dir("up", true)
	Run("trigger", t, false)
	Eq(t.attrs.type, "macro", "type")
	Eq(t.attrs.macrotext, "/use item:1\n/use item:2", "macrotext")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
