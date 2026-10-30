-- Fight segments: "current" (the running or the last fight) and "overall"
-- (every fight since the last reset), kept in memory only.
--
-- A segment holds per-unit sums, keyed by name:
--   units[name] = { name, class, isPet, owner, damage, heal, rawHeal,
--                   damageSpells, healSpells }
-- heal is the effective healing, rawHeal the combat log amount (overheal
-- included); the segment keeps the same three totals. The spell tables break
-- a unit's sums down by spell name:
--   damageSpells[spell] = { amount, hits, crits }
--   healSpells[spell] = { amount (effective), raw, hits, crits }
-- Melee hits go under "Melee", damage shields under "Damage Shield", and a
-- periodic tick under "<spell> (DoT)" / "<spell> (HoT)", so a spell with a
-- direct and a periodic part shows both.
-- and its active time: duration (finished fights) plus the running fight's
-- share while startTime is set. DPS and HPS divide by this active time, so
-- idle time between fights does not dilute the overall numbers.
--
-- A fight starts on PLAYER_REGEN_DISABLED or on the first damage a group
-- member deals while no fight runs, and ends once no group unit (players and
-- pets) is in combat any more. The end is polled every second as well,
-- because Unreal Azeroth's events are not guaranteed.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

local COMBAT_POLL = 1.0

S.fighting = false

local function NewSegment()
	return { units = {}, damage = 0, heal = 0, rawHeal = 0, duration = 0 }
end

S.segments = { current = NewSegment(), overall = NewSegment() }

function S:SegmentDuration(segment)
	local duration = segment.duration
	if segment.startTime then
		duration = duration + GetTime() - segment.startTime
	end
	return duration
end

function S:StartFight()
	if self.fighting then return end
	self.fighting = true

	local now = GetTime()
	local current = NewSegment()
	current.startTime = now
	self.segments.current = current
	self.segments.overall.startTime = now

	self:RequestRefresh()
end

function S:EndFight()
	if not self.fighting then return end
	self.fighting = false

	local now = GetTime()
	local segments = self.segments
	local i, segment
	for i, segment in pairs(segments) do
		if segment.startTime then
			segment.duration = segment.duration + now - segment.startTime
			segment.startTime = nil
		end
	end

	self:RequestRefresh()
end

local function GroupInCombat()
	local name, entry
	for name, entry in pairs(S.roster) do
		if S.InCombat(entry.unit) then
			return true
		end
	end
	return false
end

function S:CheckFightEnd()
	if self.fighting and not GroupInCombat() then
		self:EndFight()
	end
end

function S:ResetData()
	local fighting = self.fighting
	self.segments = { current = NewSegment(), overall = NewSegment() }
	if fighting then
		local now = GetTime()
		self.segments.current.startTime = now
		self.segments.overall.startTime = now
	end
	self:RequestRefresh()
	self:Print(L["Data reset."])
end

local function UnitEntry(segment, name, rosterEntry)
	local unit = segment.units[name]
	if not unit then
		unit = {
			name = name,
			class = rosterEntry.class,
			isPet = rosterEntry.isPet,
			owner = rosterEntry.owner,
			damage = 0,
			heal = 0,
			rawHeal = 0,
			damageSpells = {},
			healSpells = {},
		}
		segment.units[name] = unit
	end
	return unit
end

-- The breakdown key of a combat log record.
local function SpellKey(rec)
	if rec.kind == "melee" then
		return L["Melee"]
	elseif rec.kind == "shield" then
		return L["Damage Shield"]
	elseif rec.kind == "dot" then
		return string.format(L["%s (DoT)"], rec.spell or "?")
	elseif rec.kind == "hot" then
		return string.format(L["%s (HoT)"], rec.spell or "?")
	end
	return rec.spell or "?"
end

local function SpellEntry(spells, key)
	local spell = spells[key]
	if not spell then
		spell = { amount = 0, raw = 0, hits = 0, crits = 0 }
		spells[key] = spell
	end
	return spell
end

local function AddDamage(segment, name, rosterEntry, rec, key)
	local amount = rec.amount
	local unit = UnitEntry(segment, name, rosterEntry)
	unit.damage = unit.damage + amount
	segment.damage = segment.damage + amount

	local spell = SpellEntry(unit.damageSpells, key)
	spell.amount = spell.amount + amount
	spell.hits = spell.hits + 1
	if rec.crit then spell.crits = spell.crits + 1 end
end

local function AddHeal(segment, name, rosterEntry, rec, key, effective)
	local raw = rec.amount
	local unit = UnitEntry(segment, name, rosterEntry)
	unit.heal = unit.heal + effective
	unit.rawHeal = unit.rawHeal + raw
	segment.heal = segment.heal + effective
	segment.rawHeal = segment.rawHeal + raw

	local spell = SpellEntry(unit.healSpells, key)
	spell.amount = spell.amount + effective
	spell.raw = spell.raw + raw
	spell.hits = spell.hits + 1
	if rec.crit then spell.crits = spell.crits + 1 end
end

-- Combat log listener. Damage counts when the source is in the group and
-- the target is not (no friendly fire, no damage to oneself), and starts a
-- fight. Healing counts when the source is in the group, only during a
-- fight: topping up between pulls is not part of any fight.
function S:OnSegmentCombatLine(category, rec)
	local amount = rec.amount
	if not amount or amount <= 0 then return end

	local source = self:RosterEntry(rec.source)
	if not source then return end

	if category == "damage" then
		if self:RosterEntry(rec.target) then return end
		if not self.fighting then
			self:StartFight()
		end
		local key = SpellKey(rec)
		AddDamage(self.segments.current, rec.source, source, rec, key)
		AddDamage(self.segments.overall, rec.source, source, rec, key)
		self:RequestRefresh()
	elseif category == "heal" then
		if not self.fighting then return end
		local effective = rec.effective or amount
		local key = SpellKey(rec)
		AddHeal(self.segments.current, rec.source, source, rec, key, effective)
		AddHeal(self.segments.overall, rec.source, source, rec, key, effective)
		self:RequestRefresh()
	end
end

function S:InitializeSegments()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "StartFight")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "CheckFightEnd")

	self:AddCombatListener(function(category, rec)
		S:OnSegmentCombatLine(category, rec)
	end)

	self:AddTicker(COMBAT_POLL, function()
		S:CheckFightEnd()
	end)
end
