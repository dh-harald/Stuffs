-- Damage window: the group's damage or healing, current fight or overall.
--
-- Modes: Damage, DPS, Healing (effective), HPS (effective) and Total
-- healing (the combat log amount, overheal included, with the overheal
-- share). Per-second values divide by the segment's active time. In Total
-- healing the bar shows the effective part in the class colour and the
-- overheal after it in a darker shade. The profile's modes table decides
-- which modes the title bar click cycles through.
--
-- Pets have their own row, in a darker shade of their owner's class colour,
-- or with mergePets their numbers are added to their owner's row (at draw
-- time, so the toggle needs no data reset).
--
-- Hovering a bar shows a tooltip: the unit's totals for the mode's kind
-- (damage or healing) and its breakdown by spell; a merged pet's spells are
-- listed as "<pet>: <spell>".
--
-- Title bar clicks: left = next mode, right = current/overall,
-- Shift + left = reset. The window redraws from a dirty flag on a ticker,
-- and every second while a fight runs (per-second values change with time
-- alone).

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

P.damage = {
	shown = true,
	locked = false,
	mode = "damage",
	segment = "current",
	modes = { damage = true, dps = true, healing = true, hps = true, rawhealing = true },
	mergePets = false,
	tooltip = true,
	tooltipSpells = 10,
	point = "TOPLEFT",
	x = 50,
	y = -200,
	width = 217,
	height = 161,
	barHeight = 18,
	barSpacing = 1,
	texture = "Stuffs Flat",
	bodyAlpha = 0.35,
}

local REFRESH_INTERVAL = 0.25
local FIGHT_REFRESH = 1.0
local PET_SHADE = 0.7
local OVERHEAL_SHADE = 0.45

local refreshDirty = true
local lastFightRefresh = 0

local function ShareText(amount, total)
	local percent = 0
	if total > 0 then percent = amount / total * 100 end
	return string.format("%s (%.1f%%)", S.FormatNumber(amount), percent)
end

local function RateText(value)
	return string.format("%.1f", value)
end

-- Each mode: its title label, its kind (which tooltip it gets), the bar
-- value of a unit, the value text, and optionally split: the part of the bar
-- drawn in the full colour, the rest of the bar then taking the darker
-- overheal shade.
S.DAMAGE_MODES = { "damage", "dps", "healing", "hps", "rawhealing" }
local MODES = S.DAMAGE_MODES
local MODE_DEFS = {
	damage = {
		label = "Damage",
		kind = "damage",
		value = function(unit) return unit.damage end,
		text = function(unit, segment) return ShareText(unit.damage, segment.damage) end,
	},
	dps = {
		label = "DPS",
		kind = "damage",
		value = function(unit, seconds) return unit.damage / seconds end,
		text = function(unit, segment, value) return RateText(value) end,
	},
	healing = {
		label = "Healing",
		kind = "heal",
		value = function(unit) return unit.heal end,
		text = function(unit, segment) return ShareText(unit.heal, segment.heal) end,
	},
	hps = {
		label = "HPS",
		kind = "heal",
		value = function(unit, seconds) return unit.heal / seconds end,
		text = function(unit, segment, value) return RateText(value) end,
	},
	rawhealing = {
		label = "Total healing",
		kind = "heal",
		value = function(unit) return unit.rawHeal end,
		split = function(unit) return unit.heal end,
		text = function(unit)
			local overheal = 0
			if unit.rawHeal > 0 then
				overheal = (unit.rawHeal - unit.heal) / unit.rawHeal * 100
			end
			return string.format(L["%s (%.0f%% OH)"], S.FormatNumber(unit.rawHeal), overheal)
		end,
	},
}

local function ModeDef(mode)
	return MODE_DEFS[mode] or MODE_DEFS.damage
end

function S:DamageModeLabel(mode)
	return L[ModeDef(mode).label]
end

local function SegmentLabel(segment)
	if segment == "overall" then
		return L["Overall"]
	end
	return L["Current"]
end

function S:RequestRefresh()
	refreshDirty = true
end

-- The enabled mode after `mode` in cycle order, or `mode` itself when no
-- other is enabled.
local function NextMode(db, mode)
	local count = Compat.getn(MODES)
	local index = 1
	for i = 1, count do
		if MODES[i] == mode then index = i end
	end
	for step = 1, count do
		local candidate = MODES[Compat.mod(index - 1 + step, count) + 1]
		if db.modes[candidate] then
			return candidate
		end
	end
	return mode
end

-- Keeps the shown mode one of the enabled ones.
function S:ValidateDamageMode()
	local db = self.db.profile.damage
	if not db.modes[db.mode] then
		db.mode = NextMode(db, db.mode)
	end
end

-- Merged view: every pet's numbers added to its owner's row. A view entry
-- has the unit fields plus parts, the units it was built from. Rebuilt on
-- every draw.
local function AddInto(view, unit)
	view.damage = view.damage + unit.damage
	view.heal = view.heal + unit.heal
	view.rawHeal = view.rawHeal + unit.rawHeal
	table.insert(view.parts, unit)
end

local function MergedUnits(segment)
	local merged = {}
	local name, unit
	for name, unit in pairs(segment.units) do
		local key = name
		if unit.isPet and unit.owner then key = unit.owner end
		local view = merged[key]
		if not view then
			view = { name = key, class = unit.class, damage = 0, heal = 0, rawHeal = 0, parts = {} }
			merged[key] = view
		end
		AddInto(view, unit)
	end
	return merged
end

-- The spell breakdown of a row's unit; a merged row combines its parts,
-- prefixing a pet's spells with the pet's name.
local function RowSpells(unit, kind)
	local field = "damageSpells"
	if kind == "heal" then field = "healSpells" end
	if not unit.parts then
		return unit[field]
	end

	local spells = {}
	for i = 1, Compat.getn(unit.parts) do
		local part = unit.parts[i]
		-- The loop key is copied, never reassigned: Lua 5.0's next() fails
		-- on a modified control variable.
		local key, spell
		for key, spell in pairs(part[field]) do
			local label = key
			if part.isPet then
				label = part.name .. ": " .. key
			end
			spells[label] = spell
		end
	end
	return spells
end

local rows = {}
local rowPool = {}

local function SortRows(a, b)
	if a.value ~= b.value then
		return a.value > b.value
	end
	return a.label < b.label
end

function S:RefreshDamageWindow()
	local window = self.damageWindow
	if not window then return end

	local db = self.db.profile.damage
	local segment = self.segments[db.segment] or self.segments.current
	local duration = self:SegmentDuration(segment)
	local seconds = duration
	if seconds < 1 then seconds = 1 end

	for i = Compat.getn(rows), 1, -1 do
		table.insert(rowPool, table.remove(rows, i))
	end

	local units = segment.units
	if db.mergePets then
		units = MergedUnits(segment)
	end

	local def = ModeDef(db.mode)
	local name, unit
	for name, unit in pairs(units) do
		local value = def.value(unit, seconds)
		if value > 0 then
			local row = table.remove(rowPool) or {}
			local color = self:ClassColor(unit.class)
			local shade = 1
			if unit.isPet then shade = PET_SHADE end
			local r, g, b = color.r * shade, color.g * shade, color.b * shade
			row.unit = unit
			row.label = name
			row.value = value
			row.text = def.text(unit, segment, value)
			if def.split then
				local split = row.splitData or {}
				row.splitData = split
				split.value = def.split(unit)
				split.r, split.g, split.b = r, g, b
				row.split = split
				row.r, row.g, row.b = r * OVERHEAL_SHADE, g * OVERHEAL_SHADE, b * OVERHEAL_SHADE
			else
				row.split = nil
				row.r, row.g, row.b = r, g, b
			end
			table.insert(rows, row)
		end
	end

	table.sort(rows, SortRows)

	local top = 0
	if rows[1] then top = rows[1].value end
	for i = 1, Compat.getn(rows) do
		local row = rows[i]
		row.max = top
		row.label = i .. ". " .. row.label
	end

	window:SetTitle(L[def.label] .. ": " .. SegmentLabel(db.segment), S.FormatDuration(duration))
	window:SetRows(rows)
end

-- Tooltip

local spellList = {}

local function Percent(part, whole)
	if whole > 0 then
		return part / whole * 100
	end
	return 0
end

local function SortSpells(a, b)
	if a.spell.amount ~= b.spell.amount then
		return a.spell.amount > b.spell.amount
	end
	if a.spell.raw ~= b.spell.raw then
		return a.spell.raw > b.spell.raw
	end
	return a.name < b.name
end

local function AddTotalLine(label, value)
	GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1)
end

local function AddSpellLines(spells, total, isHeal, maxSpells)
	if maxSpells <= 0 then return end

	for i = Compat.getn(spellList), 1, -1 do
		table.remove(spellList, i)
	end
	local name, spell
	for name, spell in pairs(spells) do
		table.insert(spellList, { name = name, spell = spell })
	end
	table.sort(spellList, SortSpells)

	local count = Compat.getn(spellList)
	if count == 0 then return end
	GameTooltip:AddLine(" ")

	local shown = count
	if shown > maxSpells then shown = maxSpells end
	for i = 1, shown do
		local entry = spellList[i]
		local spell = entry.spell
		local detail
		if isHeal then
			detail = string.format(L["%d hits, %.0f%% OH"], spell.hits, Percent(spell.raw - spell.amount, spell.raw))
		else
			detail = string.format(L["%d hits, %.0f%% crit"], spell.hits, Percent(spell.crits, spell.hits))
		end
		GameTooltip:AddDoubleLine(entry.name .. " |cff999999(" .. detail .. ")|r",
			ShareText(spell.amount, total), 1, 1, 1, 1, 1, 1)
	end
	if count > shown then
		GameTooltip:AddLine(string.format(L["... and %d more"], count - shown), 0.6, 0.6, 0.6)
	end
end

function S:ShowBarTooltip(bar, row)
	local unit = row.unit
	local db = self.db.profile.damage
	if not unit or not db.tooltip then return end

	local def = ModeDef(db.mode)
	local segment = self.segments[db.segment] or self.segments.current
	local seconds = self:SegmentDuration(segment)
	if seconds < 1 then seconds = 1 end

	-- Open towards the middle of the screen.
	local anchor = "ANCHOR_RIGHT"
	local x = bar:GetCenter()
	local screenWidth = UIParent:GetRight()
	if x and screenWidth and x > screenWidth / 2 then
		anchor = "ANCHOR_LEFT"
	end
	GameTooltip:SetOwner(bar, anchor)

	local color = self:ClassColor(unit.class)
	GameTooltip:AddLine(unit.name, color.r, color.g, color.b)
	if unit.isPet and unit.owner then
		GameTooltip:AddLine(string.format(L["Pet of %s"], unit.owner), 0.7, 0.7, 0.7)
	end

	if def.kind == "heal" then
		local overheal = unit.rawHeal - unit.heal
		AddTotalLine(L["Healing"], ShareText(unit.heal, segment.heal))
		AddTotalLine(L["HPS"], RateText(unit.heal / seconds))
		AddTotalLine(L["Overheal"], string.format("%s (%.0f%%)", S.FormatNumber(overheal), Percent(overheal, unit.rawHeal)))
		AddSpellLines(RowSpells(unit, "heal"), unit.heal, true, db.tooltipSpells)
	else
		AddTotalLine(L["Damage"], ShareText(unit.damage, segment.damage))
		AddTotalLine(L["DPS"], RateText(unit.damage / seconds))
		AddSpellLines(RowSpells(unit, "damage"), unit.damage, false, db.tooltipSpells)
	end

	GameTooltip:Show()
end

function S:OnDamageTitleClick(button)
	local db = self.db.profile.damage
	if button == "LeftButton" and Compat.bool(IsShiftKeyDown()) then
		self:ResetData()
	elseif button == "LeftButton" then
		db.mode = NextMode(db, db.mode)
	elseif button == "RightButton" then
		if db.segment == "current" then
			db.segment = "overall"
		else
			db.segment = "current"
		end
	end
	self:RefreshDamageWindow()
end

function S:SetDamageWindowShown(shown)
	local db = self.db.profile.damage
	db.shown = shown and true or false
	self.damageWindow:ApplyShown()
	if db.shown then
		self:RefreshDamageWindow()
	end
end

function S:ToggleDamageWindow()
	self:SetDamageWindowShown(not self.db.profile.damage.shown)
end

-- Locks or unlocks every window.
function S:SetLocked(locked)
	self.db.profile.damage.locked = locked and true or false
	self.damageWindow:ApplyLock()
	if self.threatWindow then
		self.db.profile.threat.locked = locked and true or false
		self.threatWindow:ApplyLock()
	end
	if locked then
		self:Print(L["Windows locked."])
	else
		self:Print(L["Windows unlocked. Drag the title bar to move a window, the bottom right corner to resize it."])
	end
end

-- Puts the window back to the default position and size.
function S:ResetDamageWindowPosition()
	local db = self.db.profile.damage
	db.point, db.x, db.y = P.damage.point, P.damage.x, P.damage.y
	db.width, db.height = P.damage.width, P.damage.height
	self.damageWindow:ApplyStyle()
end

-- Re-applies every window setting from the profile.
function S:ApplyDamageWindowSettings()
	self:ValidateDamageMode()
	local window = self.damageWindow
	window:ApplyStyle()
	window:ApplyLock()
	window:ApplyShown()
	self:RefreshDamageWindow()
end

function S:InitializeDamageWindow()
	self:ValidateDamageMode()
	self.damageWindow = self:CreateMeterWindow(self.db.profile.damage, function(button)
		S:OnDamageTitleClick(button)
	end, function(bar, row)
		S:ShowBarTooltip(bar, row)
	end)
	self:RefreshDamageWindow()

	self:AddTicker(REFRESH_INTERVAL, function(now)
		if not S.db.profile.damage.shown then return end
		if refreshDirty or (S.fighting and now - lastFightRefresh >= FIGHT_REFRESH) then
			refreshDirty = false
			lastFightRefresh = now
			S:RefreshDamageWindow()
		end
	end)
end
