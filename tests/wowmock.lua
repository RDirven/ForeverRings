-- A small fake of the WoW client: frames, secure snippets, bindings, bags,
-- items, spells and mounts. Loads the addon in a fresh environment so tests
-- can log in, press gamepad buttons and read back what got cast.
--
-- Only methods the addon uses exist, with their real WoW names, so a typo in
-- a method name fails loudly. Protected frames raise ADDON_ACTION_BLOCKED when
-- touched from insecure code in combat, like the real client.

local M = {}

local TOC_FILES = { "Snippets.lua", "Data.lua", "Display.lua", "Core.lua", "Config.lua" }

local function DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = DeepCopy(v)
	end
	return copy
end

function M.New(world)
	world = world or {}
	local game = {
		items = world.items or {},     -- [itemID] = { name, icon, class, subclass, ilvl, spell, count }
		bags = world.bags or {},       -- [bag] = { [slot] = itemID }
		spells = world.spells or {},   -- [spellID] = { name, icon }
		mounts = world.mounts or {},   -- list of { id, name, spell, icon, usable, favorite, collected, hidden }
		toys = world.toys or {},       -- [itemID] = true
		spellbook = world.spellbook or {}, -- list of spellIDs
		inCombat = false,
		inSecure = false,
		bindings = {},
		casts = {},
		vibrations = 0,
		printed = {},
		timers = {},
		cursor = { 960, 540 },
		frames = {},
	}

	local env = setmetatable({}, { __index = _G })
	env._G = env

	local function Blocked(frame, method)
		if frame.protected and game.inCombat and not game.inSecure then
			error(("ADDON_ACTION_BLOCKED: %s:%s() in combat"):format(frame.name or "frame", method), 3)
		end
	end

	-- Regions (textures, masks, font strings) ---------------------------------

	local Region = {}
	Region.__index = Region
	local function NewRegion(kind, parent)
		return setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1, masks = {} }, Region)
	end
	function Region:SetPoint() end
	function Region:ClearAllPoints() end
	function Region:SetSize() end
	function Region:SetWidth() end
	function Region:SetHeight() end
	function Region:SetJustifyH() end
	function Region:SetTextColor(r, g, b) self.textColor = { r, g, b } end
	function Region:SetAllPoints() end
	function Region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
	function Region:SetTexture(tex) self.texture = tex end
	function Region:GetTexture() return self.texture end
	function Region:SetTexCoord(...) self.texCoord = { ... } end
	function Region:SetBlendMode(mode) self.blend = mode end
	function Region:SetAlpha(a) self.alpha = a end
	function Region:GetAlpha() return self.alpha end
	function Region:SetDesaturated(on) self.desaturated = on end
	function Region:AddMaskTexture(mask) self.masks[mask] = true end
	function Region:RemoveMaskTexture(mask) self.masks[mask] = nil end
	function Region:SetText(text) self.text = text ~= nil and tostring(text) or nil end
	function Region:GetText() return self.text end
	function Region:Show() self.shown = true end
	function Region:Hide() self.shown = false end
	function Region:SetShown(on) self.shown = not not on end
	function Region:IsShown() return self.shown end

	-- Frames ------------------------------------------------------------------

	local Frame = {}
	Frame.__index = Frame

	local function CreateFrame(kind, name, parent, template)
		local f = setmetatable({
			kind = kind, name = name, parent = parent, template = template,
			protected = template ~= nil and template:find("Secure") ~= nil,
			attrs = {}, scripts = {}, hooks = {}, events = {}, wraps = {},
			overrides = {}, clicks = {}, shown = true, scale = 1,
			width = 100, height = 100, regions = {},
		}, Frame)
		if name then
			env[name] = f
		end
		table.insert(game.frames, f)
		return f
	end

	function Frame:SetSize(w, h) self.width, self.height = w, h end
	function Frame:SetPoint() Blocked(self, "SetPoint") end
	function Frame:ClearAllPoints() Blocked(self, "ClearAllPoints") end
	function Frame:SetAllPoints(target)
		Blocked(self, "SetAllPoints")
		target = target or self.parent
		self.width, self.height = target.width, target.height
	end
	function Frame:SetFrameStrata(strata) self.strata = strata end
	function Frame:EnableMouse(on) self.mouse = on end
	function Frame:RegisterForClicks(...)
		self.clicks = {}
		for _, c in ipairs({ ... }) do
			self.clicks[c] = true
		end
	end
	function Frame:GetWidth() return self.width end
	function Frame:GetHeight() return self.height end
	function Frame:GetEffectiveScale() return 1 end
	function Frame:GetLeft() return 0 end
	function Frame:GetBottom() return 0 end
	function Frame:GetCenter() return self.width / 2, self.height / 2 end
	function Frame:GetMousePosition()
		return game.cursor[1] / self.width, game.cursor[2] / self.height
	end
	function Frame:Show() Blocked(self, "Show") self.shown = true end
	function Frame:Hide() Blocked(self, "Hide") self.shown = false end
	function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
	function Frame:IsShown() return self.shown end
	function Frame:SetScale(s) self.scale = s end
	function Frame:SetAlpha(a) self.alpha = a end
	function Frame:EnableKeyboard(on) self.keyboard = on end
	function Frame:SetPropagateKeyboardInput(on) self.propagate = on end
	function Frame:EnableGamePadButton(on) self.gamepad = on end
	function Frame:SetAttribute(k, v)
		Blocked(self, "SetAttribute")
		self.attrs[k] = v
		for _, fn in ipairs(self.hooks.OnAttributeChanged or {}) do
			fn(self, k, v)
		end
	end
	function Frame:GetAttribute(k) return self.attrs[k] end
	function Frame:SetScript(script, fn) self.scripts[script] = fn end
	function Frame:GetScript(script) return self.scripts[script] end
	function Frame:HookScript(script, fn)
		self.hooks[script] = self.hooks[script] or {}
		table.insert(self.hooks[script], fn)
	end
	function Frame:RegisterEvent(event) self.events[event] = true end
	function Frame:UnregisterEvent(event) self.events[event] = nil end
	function Frame:CreateTexture() local r = NewRegion("Texture", self) table.insert(self.regions, r) return r end
	function Frame:CreateMaskTexture() return NewRegion("MaskTexture", self) end
	function Frame:CreateFontString() local r = NewRegion("FontString", self) table.insert(self.regions, r) return r end
	-- Restricted-environment handle methods (the mock uses frames as handles).
	-- EditBox
	function Frame:SetAutoFocus(on) self.autoFocus = on end
	function Frame:SetText(text) self.text = text end
	function Frame:GetText() return self.text end
	function Frame:HighlightText() self.highlighted = true end
	function Frame:SetFocus() self.focused = true end
	function Frame:ClearFocus() self.focused = false end
	function Frame:SetBindingClick(_, key, buttonName)
		Blocked(self, "SetBindingClick")
		self.overrides[key] = { name = buttonName }
	end
	function Frame:ClearBindings()
		Blocked(self, "ClearBindings")
		self.overrides = {}
	end

	local UIParent = CreateFrame("Frame", "UIParent")
	UIParent:SetSize(1920, 1080)

	-- Secure execution --------------------------------------------------------

	local function SecureHandlerWrapScript(frame, script, header, body)
		local fn, err = loadstring("local self, button, down = ...\n" .. body, (frame.name or "?") .. ":" .. script)
		assert(fn, err)
		frame.wraps[script] = { header = header, fn = fn }
	end

	-- Simulates a click from a key binding: runs the wrapped snippet, then the
	-- secure action unless the snippet returned false.
	local function Click(frame, down, button)
		if not frame.clicks[down and "AnyDown" or "AnyUp"] then
			return
		end
		if not frame.wraps.OnClick and frame.scripts.OnClick then
			return frame.scripts.OnClick(frame, button or "LeftButton", down)
		end
		local wrap = frame.wraps.OnClick
		local result
		if wrap then
			setfenv(wrap.fn, { owner = wrap.header, math = math })
			game.inSecure = true
			local ok, err = pcall(function() result = wrap.fn(frame, "LeftButton", down) end)
			game.inSecure = false
			assert(ok, err)
		end
		if result ~= false then
			local kind = frame.attrs.type
			if kind then
				table.insert(game.casts, { type = kind, value = frame.attrs[kind == "macro" and "macrotext" or kind] })
			end
		end
	end

	-- Presses a key: override bindings (owned by the ring header) win.
	function game.Press(key, down)
		if down == nil then
			game.Press(key, true)
			return game.Press(key, false)
		end
		local override
		for _, f in ipairs(game.frames) do
			if f.overrides[key] then
				override = f.overrides[key]
			end
		end
		if override then
			return Click(env[override.name], down, override.button)
		end
		local command = game.bindings[key]
		local clickTarget = command and command:match("^CLICK ([%w_]+):")
		if clickTarget then
			Click(env[clickTarget], down)
		elseif command == "FOREVERRINGS_CONFIG" and down then
			env.ForeverRings_ToggleConfig()
		end
	end

	-- Raw key or gamepad button reaching frames that capture input.
	function game.KeyDown(key)
		for _, f in ipairs(game.frames) do
			if f.shown and f.keyboard and f.scripts.OnKeyDown then
				return f.scripts.OnKeyDown(f, key)
			end
		end
	end

	function game.GamePadButton(button)
		for _, f in ipairs(game.frames) do
			if f.shown and f.gamepad and f.scripts.OnGamePadButtonDown then
				return f.scripts.OnGamePadButtonDown(f, button)
			end
		end
	end

	function game.Fire(event, ...)
		for _, f in ipairs(game.frames) do
			if f.events[event] and f.scripts.OnEvent then
				f.scripts.OnEvent(f, event, ...)
			end
		end
	end

	function game.RunTimers()
		local timers = game.timers
		game.timers = {}
		for _, fn in ipairs(timers) do
			fn()
		end
	end

	function game.Update()
		for _, f in ipairs(game.frames) do
			if f.scripts.OnUpdate then
				f.scripts.OnUpdate(f, 0.016)
			end
		end
	end

	function game.Slash(msg)
		env.SlashCmdList.FOREVERRINGS(msg)
		return table.remove(game.printed)
	end

	-- Like the client: PLAYER_REGEN_DISABLED fires just before lockdown starts.
	function game.SetCombat(on)
		if on then
			game.Fire("PLAYER_REGEN_DISABLED")
			game.inCombat = true
		else
			game.inCombat = false
			game.Fire("PLAYER_REGEN_ENABLED")
		end
	end

	-- Game API ----------------------------------------------------------------

	local function Item(id)
		return game.items[id]
	end

	local function Count(id)
		local n = 0
		for _, slots in pairs(game.bags) do
			for _, itemID in pairs(slots) do
				if itemID == id then
					n = n + (Item(id) and Item(id).count or 1)
				end
			end
		end
		return n
	end

	local api = {
		UIParent = UIParent,
		CreateFrame = CreateFrame,
		SecureHandlerWrapScript = SecureHandlerWrapScript,
		InCombatLockdown = function() return game.inCombat end,
		GetCursorPosition = function() return game.cursor[1], game.cursor[2] end,
		SetBindingClick = function(key, name, button)
			game.bindings[key] = "CLICK " .. name .. ":" .. (button or "LeftButton")
		end,
		SetBinding = function(key, command) game.bindings[key] = command end,
		GetBindingKey = function(command)
			local keys = {}
			for key, c in pairs(game.bindings) do
				if c == command then
					keys[#keys + 1] = key
				end
			end
			table.sort(keys)
			return unpack(keys)
		end,
		SetOverrideBindingClick = function(owner, _, key, name, button)
			if game.inCombat and not game.inSecure then
				error("ADDON_ACTION_BLOCKED: SetOverrideBindingClick() in combat", 2)
			end
			owner.overrides[key] = { name = name, button = button }
		end,
		ClearOverrideBindings = function(owner)
			if game.inCombat and not game.inSecure then
				error("ADDON_ACTION_BLOCKED: ClearOverrideBindings() in combat", 2)
			end
			owner.overrides = {}
		end,
		SaveBindings = function() end,
		GetCurrentBindingSet = function() return 1 end,
		CopyTable = DeepCopy,
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(game.printed, table.concat(parts, " "))
		end,
		SlashCmdList = {},
		NUM_BAG_SLOTS = 4,
		NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5,
		C_Timer = { After = function(_, fn) table.insert(game.timers, fn) end },
		C_GamePad = {
			SetVibration = function() game.vibrations = game.vibrations + 1 end,
			StopVibration = function() end,
		},
		PlayerHasToy = function(id) return game.toys[id] == true end,
		Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } },
		C_SpellBook = {
			GetNumSpellBookSkillLines = function() return 1 end,
			GetSpellBookSkillLineInfo = function()
				return { itemIndexOffset = 0, numSpellBookItems = #game.spellbook }
			end,
			GetSpellBookItemInfo = function(slot)
				local id = game.spellbook[slot]
				local spell = game.spells[id]
				return { itemType = 1, spellID = id, name = spell.name, iconID = spell.icon, isPassive = spell.passive == true }
			end,
		},
		C_ToyBox = {
			GetNumFilteredToys = function()
				local n = 0
				for _ in pairs(game.toys) do n = n + 1 end
				return n
			end,
			GetToyFromIndex = function(i)
				local ids = {}
				for id in pairs(game.toys) do ids[#ids + 1] = id end
				table.sort(ids)
				return ids[i]
			end,
			GetToyInfo = function(id)
				local it = game.items[id]
				return id, it and it.name, it and it.icon
			end,
		},
		C_Container = {
			GetContainerNumSlots = function(bag) return game.bags[bag] and 16 or 0 end,
			GetContainerItemInfo = function(bag, slot)
				local id = game.bags[bag] and game.bags[bag][slot]
				return id and { itemID = id, stackCount = Item(id) and Item(id).count or 1 } or nil
			end,
		},
		C_Item = {
			GetItemInfoInstant = function(id)
				local it = Item(id)
				if it then
					return id, "", "", "", it.icon, it.class, it.subclass
				end
			end,
			GetItemInfo = function(id)
				local it = Item(id)
				if it and not it.uncached then
					return it.name, "link", 1, it.ilvl
				end
			end,
			GetItemIconByID = function(id) return Item(id) and Item(id).icon end,
			GetItemNameByID = function(id)
				local it = Item(id)
				return it and not it.uncached and it.name or nil
			end,
			GetItemCount = Count,
			GetItemSpell = function(id)
				local it = Item(id)
				if it and it.spell then
					local spell = game.spells[it.spell]
					return spell and spell.name or "Use", it.spell
				end
			end,
		},
		C_Spell = {
			GetSpellTexture = function(id) return game.spells[id] and game.spells[id].icon end,
			GetSpellName = function(id)
				if game.spells[id] then
					return game.spells[id].name
				end
				for _, m in ipairs(game.mounts) do
					if m.spell == id then
						return m.name
					end
				end
			end,
		},
		C_MountJournal = {
			GetMountIDs = function()
				local ids = {}
				for _, m in ipairs(game.mounts) do
					ids[#ids + 1] = m.id
				end
				return ids
			end,
			GetMountInfoByID = function(id)
				for _, m in ipairs(game.mounts) do
					if m.id == id then
						return m.name, m.spell, m.icon, false, m.usable ~= false, 0, m.favorite == true,
							false, nil, m.hidden == true, m.collected ~= false, m.id
					end
				end
			end,
		},
	}
	for k, v in pairs(api) do
		env[k] = v
	end

	game.env = env
	game.ns = {}

	-- Loads the addon files in .toc order and fires PLAYER_LOGIN.
	function game.Login(savedVariables)
		env.ForeverRingsDB = DeepCopy(savedVariables)
		for _, file in ipairs(TOC_FILES) do
			local chunk = assert(loadfile(file))
			setfenv(chunk, env)
			chunk("ForeverRings", game.ns)
		end
		game.Fire("PLAYER_LOGIN")
		return game
	end

	return game
end

return M
