-- Threat window: the threat of every unit LibVanillaThreat-1.0 knows of on
-- the current target, highest first. The mob is the target when it can be
-- attacked, otherwise the target's target (a healer targeting the tank sees
-- the tank's mob). Mobs are keyed by name (1.12 has no GUIDs).
--
-- The tank (LibVanillaThreat-1.0's GetTank: the mob's target, unless the
-- unit with the most threat has enough to have pulled it off them) shows
-- "(tank)", every other row its share of the tank's threat; the bars are
-- scaled to the highest value. The player's row is highlighted and always
-- shown: when it would fall below the last bar, it takes the last bar's
-- place, keeping its rank.
--
-- The window redraws from a dirty flag (threat changes, target changes) on
-- a ticker, and every second while in combat: the target's target changes
-- without an event.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

P.threat = {
	shown = true,
	locked = false,
	point = "TOPLEFT",
	x = 50,
	y = -380,
	width = 217,
	height = 115,
	barHeight = 18,
	barSpacing = 1,
	texture = "Stuffs Flat",
	bodyAlpha = 0.35,
}

local REFRESH_INTERVAL = 0.25
local COMBAT_REFRESH = 1.0
local PET_SHADE = 0.7

local dirty = true
local lastCombatRefresh = 0

local rows = {}
local rowPool = {}

function S:RequestThreatRefresh()
	dirty = true
end

local function Attackable(unit)
	return Compat.bool(UnitExists(unit)) and Compat.bool(UnitCanAttack("player", unit))
end

-- The mob the window shows and its unit id, or nil.
function S:ThreatMob()
	if Attackable("target") then
		return UnitName("target"), "target"
	elseif Attackable("targettarget") then
		return UnitName("targettarget"), "targettarget"
	end
	return nil
end

local function RowColor(self, name)
	local entry = self:RosterEntry(name)
	local color = self:ClassColor(entry and entry.class)
	local shade = 1
	if entry and entry.isPet then shade = PET_SHADE end
	return color.r * shade, color.g * shade, color.b * shade
end

local function RowText(name, value, tankName, tankThreat)
	if name == tankName then
		return string.format(L["%s (tank)"], S.FormatNumber(value))
	end
	local percent = 0
	if tankThreat and tankThreat > 0 then
		percent = value / tankThreat * 100
	end
	return string.format("%s (%.0f%%)", S.FormatNumber(value), percent)
end

function S:RefreshThreatWindow()
	local window = self.threatWindow
	if not window then return end

	for i = Compat.getn(rows), 1, -1 do
		table.insert(rowPool, table.remove(rows, i))
	end

	local mob, mobUnit = self:ThreatMob()
	if mob then
		local LVT = self:Threat()
		local tankName, tankThreat = LVT:GetTank(mob, mobUnit)
		local top, playerIndex
		local name, value
		for name, value in LVT:IterateGroupThreatForTarget(mob) do
			if value > 0 then
				top = top or value
				local rank = Compat.getn(rows) + 1
				local row = table.remove(rowPool) or {}
				row.label = rank .. ". " .. name
				row.value = value
				row.max = top
				row.text = RowText(name, value, tankName, tankThreat)
				row.highlight = name == LVT.playerName
				if row.highlight then playerIndex = rank end
				row.r, row.g, row.b = RowColor(self, name)
				row.split = nil
				table.insert(rows, row)
			end
		end

		local count = window:BarCount()
		if playerIndex and count > 0 and playerIndex > count then
			table.insert(rows, count, table.remove(rows, playerIndex))
		end
		window:SetTitle(string.format(L["Threat: %s"], mob), "")
	else
		window:SetTitle(L["Threat"], "")
	end
	window:SetRows(rows)
end

function S:SetThreatWindowShown(shown)
	local db = self.db.profile.threat
	db.shown = shown and true or false
	self.threatWindow:ApplyShown()
	if db.shown then
		self:RefreshThreatWindow()
	end
end

function S:ToggleThreatWindow()
	self:SetThreatWindowShown(not self.db.profile.threat.shown)
end

-- Puts the window back to the default position and size.
function S:ResetThreatWindowPosition()
	local db = self.db.profile.threat
	db.point, db.x, db.y = P.threat.point, P.threat.x, P.threat.y
	db.width, db.height = P.threat.width, P.threat.height
	self.threatWindow:ApplyStyle()
end

-- Re-applies every window setting from the profile.
function S:ApplyThreatWindowSettings()
	local window = self.threatWindow
	window:ApplyStyle()
	window:ApplyLock()
	window:ApplyShown()
	self:RefreshThreatWindow()
end

function S:InitializeThreatWindow()
	self.threatWindow = self:CreateMeterWindow(self.db.profile.threat)
	self:RefreshThreatWindow()

	local LVT = self:Threat()
	self.threatCallbacks = self.threatCallbacks or {}
	LVT.RegisterCallback(self.threatCallbacks, "ThreatUpdated", function() dirty = true end)
	LVT.RegisterCallback(self.threatCallbacks, "ThreatCleared", function() dirty = true end)
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "RequestThreatRefresh")
	self:RegisterEvent("UNIT_TARGET", "RequestThreatRefresh")

	self:AddTicker(REFRESH_INTERVAL, function(now)
		if not S.db.profile.threat.shown then return end
		local inCombat = S.InCombat("player")
		if dirty or (inCombat and now - lastCombatRefresh >= COMBAT_REFRESH) then
			dirty = false
			lastCombatRefresh = now
			S:RefreshThreatWindow()
		end
	end)
end
