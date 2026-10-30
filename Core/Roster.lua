-- Group roster: who counts as "us" in the combat log.
--
-- S.roster maps a unit name to { unit, class, isPet, owner }. It holds the
-- player, the party or raid members and every pet of theirs; a pet carries
-- its owner's name and class. Combat log lines only name units, so this is
-- the table that decides whether a line's source belongs to the group.
--
-- Roster events only flag the table; the ticker rebuilds it. Group events
-- fire very often on Unreal Azeroth, and a name lookup that misses while the
-- table is flagged rebuilds it on the spot, so a pet summoned mid-fight is
-- counted from its first hit.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

S.roster = {}

local ROSTER_EVENTS = {
	"PARTY_MEMBERS_CHANGED",
	"RAID_ROSTER_UPDATE",
	"UNIT_PET",
	"UNIT_NAME_UPDATE",
	"PLAYER_PET_CHANGED",
	"PLAYER_ENTERING_WORLD",
}

local rosterDirty = true

local function AddUnit(roster, unit)
	local name = UnitName(unit)
	if not name or name == UNKNOWNOBJECT or name == UKNOWNBEING then return end
	local _, class = UnitClass(unit)
	roster[name] = { unit = unit, class = class }
	return name, class
end

local function AddPet(roster, petUnit, ownerName, ownerClass)
	if not ownerName or not Compat.bool(UnitExists(petUnit)) then return end
	local name = UnitName(petUnit)
	if not name or name == UNKNOWNOBJECT or name == UKNOWNBEING then return end
	-- A pet never replaces a player of the same name.
	if roster[name] and not roster[name].isPet then return end
	roster[name] = { unit = petUnit, class = ownerClass, isPet = true, owner = ownerName }
end

function S:RebuildRoster()
	local roster = {}

	local name, class = AddUnit(roster, "player")
	AddPet(roster, "pet", name, class)

	local raidCount = GetNumRaidMembers() or 0
	if raidCount > 0 then
		for i = 1, raidCount do
			name, class = AddUnit(roster, "raid" .. i)
			AddPet(roster, "raidpet" .. i, name, class)
		end
	else
		for i = 1, GetNumPartyMembers() or 0 do
			name, class = AddUnit(roster, "party" .. i)
			AddPet(roster, "partypet" .. i, name, class)
		end
	end

	self.roster = roster
	rosterDirty = false
end

function S:MarkRosterDirty()
	rosterDirty = true
end

-- The roster entry of a name, or nil when it is not in the group.
function S:RosterEntry(name)
	if not name then return nil end
	local entry = self.roster[name]
	if not entry and rosterDirty then
		self:RebuildRoster()
		entry = self.roster[name]
	end
	return entry
end

-- The unit ids of the group (players and pets), for the combat poll.
function S:RosterUnits()
	return self.roster
end

function S:InitializeRoster()
	for i = 1, Compat.getn(ROSTER_EVENTS) do
		self:RegisterEvent(ROSTER_EVENTS[i], "MarkRosterDirty")
	end
	self:RebuildRoster()

	self:AddTicker(0.5, function()
		if rosterDirty then
			S:RebuildRoster()
		end
	end)
end
